import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors, buildAppTheme;
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/fake_pdf_document.dart';
import '../../helpers/number_pad_keyboard.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/project_scratch_folder.dart';
import '../../helpers/settle_async.dart';

/// The media viewer panel (R4, §6-h): images and PDF pages inside the
/// canvas shell, page stepping, and the honest refusals. The PDF renderer
/// is INJECTED — flutter_tester never touches the FFI plugin.
///
/// 🪦One of those refusals used to be 「no viewer for the KIND」, and the
/// kind it meant was audio. Sound has a picture now — its waveform — so
/// what is left is a sound this build could not READ, which is the same
/// shape the video arm has. The waveform itself is pinned next door, in
/// `an_audio_file_opens_as_its_waveform_test`.
void main() {
  late EditorSessionManager session;
  late MediaViewerSlot slot;


  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    slot = MediaViewerSlot();
  });

  tearDown(() {
    PdfRenderService.debugResetForTests();
    slot.dispose();
    session.dispose();
  });

  /// The position lives ABOVE the panel in the app (the workspace owns
  /// it, so a folded-away rail cannot lose the page you were on), so the
  /// harness has to hold it too — a host with nowhere to put the answer
  /// simply never turns a page.
  Widget hostIn(
    MediaViewerSlot slot, {
    required String viewerId,
    CanvasViewport? viewport,
    ValueChanged<CanvasViewport>? onViewportChanged,
  }) => ValueListenableBuilder<int>(
    valueListenable: slot.position,
    builder: (context, position, _) => MediaViewerTabHost(
      viewerId: viewerId,
      session: session,
      request: slot.request,
      position: slot.position,
      viewport: viewport,
      onViewportChanged: onViewportChanged,
    ),
  );

  Future<void> pumpViewer(
    WidgetTester tester, {
    String viewerId = 'media-viewer',
    CanvasViewport? viewport,
    ValueChanged<CanvasViewport>? onViewportChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: hostIn(
            slot,
            viewerId: viewerId,
            viewport: viewport,
            onViewportChanged: onViewportChanged,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('with nothing to view the panel says so', (tester) async {
    await pumpViewer(tester);
    expect(
      find.byKey(const ValueKey<String>('media-viewer-message')),
      findsOneWidget,
    );
    expect(find.text(AppText.strings.mediaViewerEmpty), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('media-viewer-page')),
      findsNothing,
    );
  });

  // F-77 (유저: 「뷰어패널 열린거 없으면 확대나 스크롤바같은 조작 버튼
  // 비활성화」). An empty viewer still frames a stage, so every view verb
  // used to zoom and pan nothing at all.

  testWidgets('🐛F-77: with nothing to view, the zoom readout stays in its '
      'place and neither scrubs nor opens its field', (tester) async {
    await pumpViewer(tester);
    final label = find.byKey(
      const ValueKey<String>('canvas-viewport-zoom-label'),
    );
    expect(label, findsOneWidget, reason: 'in its place, not removed');
    String zoomText() => tester
        .widget<Text>(find.descendant(of: label, matching: find.byType(Text)))
        .data!;
    final before = zoomText();

    final gesture = await tester.startGesture(tester.getCenter(label));
    for (var step = 0; step < 6; step += 1) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(zoomText(), before, reason: 'an empty stage has no view to zoom');

    await tester.tap(label);
    await tester.pumpAndSettle();
    // The pad, not its field: a pencil's pad opens with no field in it
    // (I-134), so a field missing says nothing about what opened.
    expect(
      theNumberPadsNumber,
      findsNothing,
      reason: 'and a tap opens no pad',
    );
  });

  testWidgets('🐛F-77: with nothing to view, neither panbar pans', (
    tester,
  ) async {
    final seen = <CanvasViewport>[];
    // Zoomed in, so both lanes have somewhere to go — without range a panbar
    // takes no drag anyway, and the test would measure nothing.
    await pumpViewer(
      tester,
      viewport: CanvasViewport(zoom: 4.0),
      onViewportChanged: seen.add,
    );
    seen.clear();
    for (final (key, delta) in const [
      ('canvas-viewport-horizontal-scrollbar', Offset(-60, 0)),
      ('canvas-viewport-vertical-scrollbar', Offset(0, -60)),
    ]) {
      final bar = find.byKey(ValueKey<String>(key));
      expect(bar, findsOneWidget, reason: '$key is in its place');
      await tester.drag(bar, delta);
      await tester.pumpAndSettle();
      expect(seen, isEmpty, reason: '$key moved an empty stage');
    }
  });

  // F-315 (유저 2026-10-08): 「뷰어패널에 1:1 보기버튼 넣고」 — on the pill,
  // where it was one tap away behind the gear.
  testWidgets('🐛F-77: with nothing to view, 1:1 on the pill moves no view', (
    tester,
  ) async {
    final seen = <CanvasViewport>[];
    await pumpViewer(
      tester,
      viewport: CanvasViewport(zoom: 4.0),
      onViewportChanged: seen.add,
    );
    seen.clear();
    final button = find.byKey(const ValueKey<String>('canvas-viewport-reset'));
    expect(button, findsOneWidget, reason: 'on the pill, in its place');
    await tester.tap(button, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(seen, isEmpty, reason: '1:1 of an empty stage');
  });

  testWidgets('a PDF request pages through the fake document: readout, '
      'next/previous stepping, lazy per-page renders', (tester) async {
    final fake = FakePdfDocument(
      pageSizes: List<ui.Size>.filled(4, const ui.Size(595, 842)),
    );
    PdfRenderService.debugOpenerOverride = (_) async => fake;
    await pumpViewer(tester);

    slot.request.value = const MediaViewerRequest(
      path: 'C:/work/conte.pdf',
      kind: MediaAssetKind.pdf,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('media-viewer-page')),
      findsOneWidget,
    );
    expect(find.text('1 / 4'), findsOneWidget);
    // Lazy (§6-m): only the pages ON SCREEN are asked for. The pages lie one
    // under another (F-201), so the fit of the first shows the top of the
    // second under it — and nothing further down is asked for.
    expect(
      fake.renderRequests.map((request) => request.$1).toSet(),
      {0, 1},
      reason: 'the pages on screen, and only those',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-next-page-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 / 4'), findsOneWidget);
    expect(
      fake.renderRequests.map((request) => request.$1),
      isNot(contains(3)),
      reason: 'the last page is still off screen',
    );
  });

  // 🗣️F-381 (유저 2026-10-17): 「뷰어패널에서 1:1버튼누르면 페이지가 초기화되서
  // 98페이지에서 1페이지로 초기화됨. 같은 페이지,상태에서 바껴야하는건데」.
  testWidgets('🗣️1:1 on a page past the first keeps you on that page', (
    tester,
  ) async {
    final fake = FakePdfDocument(
      pageSizes: List<ui.Size>.filled(4, const ui.Size(595, 842)),
    );
    PdfRenderService.debugOpenerOverride = (_) async => fake;
    await pumpViewer(tester);
    slot.request.value = const MediaViewerRequest(
      path: 'C:/work/conte.pdf',
      kind: MediaAssetKind.pdf,
    );
    await tester.pumpAndSettle();
    for (var page = 1; page < 3; page += 1) {
      await tester.tap(
        find.byKey(const ValueKey<String>('media-viewer-next-page-button')),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('3 / 4'), findsOneWidget, reason: '⛔premise');

    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-viewport-reset')),
    );
    await tester.pumpAndSettle();

    expect(find.text('100.00%'), findsOneWidget, reason: 'it IS 1:1');
    expect(find.text('3 / 4'), findsOneWidget);
  });

  // 🗣️F-315 (유저 2026-10-08): 「준비안된상태면 … 로딩창같은거 해당패널중앙에
  // 위젯 띄우도록 … 준비안된장이 그냥 흰색장인채로 보인다던가」.
  testWidgets('🗣️a page on screen not drawn yet stands the loading widget in '
      'the middle — 🪦a white sheet — and drawn, it takes it down', (
    tester,
  ) async {
    final loading = find.byKey(const ValueKey<String>('media-viewer-loading'));
    final fake = FakePdfDocument(
      pageSizes: List<ui.Size>.filled(4, const ui.Size(595, 842)),
    )..holdRender(0);
    final opened = Completer<FakePdfDocument>();
    PdfRenderService.debugOpenerOverride = (_) => opened.future;
    await pumpViewer(tester);
    expect(loading, findsNothing, reason: 'nothing was asked for');

    slot.request.value = const MediaViewerRequest(
      path: 'C:/work/conte.pdf',
      kind: MediaAssetKind.pdf,
    );
    await tester.pump();
    expect(loading, findsOneWidget, reason: 'the file is opening');

    opened.complete(fake);
    for (var i = 0; i < 4; i += 1) {
      await tester.pump();
    }
    expect(
      fake.renderRequests.map((request) => request.$1),
      contains(0),
      reason: 'premise: the page is asked for, and held',
    );
    expect(loading, findsOneWidget);

    fake.releaseRender(0);
    await settleLoadedPages(tester);
    expect(loading, findsNothing);
  });

  // 🗣️I-83 (유저 2026-10-08): 「뷰어패널, 파일 닫기 버튼 추가」 — and where
  // (I-83-Q1, 10-09): 「알약의 「파일 열기」 옆」.
  testWidgets('🗣️the pill closes the file beside opening one — off while '
      'nothing is open, and pressed, the viewer is empty again', (
    tester,
  ) async {
    final fake = FakePdfDocument(
      pageSizes: List<ui.Size>.filled(2, const ui.Size(595, 842)),
    );
    final opened = Completer<FakePdfDocument>();
    PdfRenderService.debugOpenerOverride = (_) => opened.future;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaViewerTabHost(
            viewerId: 'media-viewer',
            session: session,
            request: slot.request,
            position: slot.position,
            onRequestPicked: slot.open,
            onRequestClosed: () => slot.open(null),
          ),
        ),
      ),
    );
    await tester.pump();
    final open = find.byKey(
      const ValueKey<String>('media-viewer-open-file-button'),
    );
    final close = find.byKey(
      const ValueKey<String>('media-viewer-close-file-button'),
    );
    bool live() => tester.widget<AppIconButtonFace>(close).onPressed != null;
    expect(close, findsOneWidget, reason: 'in its place, nothing open');
    expect(live(), isFalse);
    expect(
      tester.getTopLeft(close).dx,
      greaterThan(tester.getTopLeft(open).dx),
      reason: 'beside 「파일 열기」',
    );

    slot.open(
      const MediaViewerRequest(
        path: 'C:/work/conte.pdf',
        kind: MediaAssetKind.pdf,
      ),
    );
    await tester.pump();
    expect(live(), isTrue, reason: 'a file asked for closes while it opens');
    opened.complete(fake);
    await tester.pumpAndSettle();
    expect(live(), isTrue);

    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(slot.request.value, isNull);
    expect(find.text(AppText.strings.mediaViewerEmpty), findsOneWidget);
    expect(live(), isFalse, reason: 'nothing left to close');
  });

  testWidgets('a PDF request with NO renderer states the absence instead '
      'of a blank page', (tester) async {
    await pumpViewer(tester);
    slot.request.value = const MediaViewerRequest(
      path: 'C:/work/conte.pdf',
      kind: MediaAssetKind.pdf,
    );
    await tester.pumpAndSettle();
    expect(find.text(AppText.strings.mediaViewerNoPdfRenderer), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('media-viewer-page')),
      findsNothing,
    );
  });

  testWidgets('an audio request whose sound cannot be read says SO', (
    tester,
  ) async {
    await pumpViewer(tester);
    slot.request.value = const MediaViewerRequest(
      // A path with nothing behind it: the conform has nothing to build
      // from, so there is no waveform to draw.
      path: 'C:/work/foot.wav',
      kind: MediaAssetKind.audio,
    );
    await tester.pumpAndSettle();
    expect(
      find.text(AppText.strings.mediaViewerNoAudioDecoder),
      findsOneWidget,
      reason: '🪦this used to assert 「이 종류의 미디어는 아직 표시할 수 '
          '없습니다」 — the kind HAS a viewer now, so the only thing left to '
          'refuse is a file it could not read',
    );
  });

  testWidgets('two viewers mounted at once keep separate keys and separate '
      'documents', (tester) async {
    // The app mounts two of these (the floor's viewer and the sub viewer
    // beside the drawing). Before the keys carried a per-viewer prefix,
    // every `find.byKey` in this file matched BOTH — a test could not say
    // which viewer it meant, and this whole file would have started
    // failing with "found 2 widgets".
    final mainSlot = MediaViewerSlot();
    final subSlot = MediaViewerSlot();
    addTearDown(mainSlot.dispose);
    addTearDown(subSlot.dispose);

    // Two documents of DIFFERENT lengths, so the readouts cannot be
    // confused for one another.
    final mainPdf = FakePdfDocument(
      pageSizes: const [ui.Size(595, 842), ui.Size(595, 842)],
    );
    final subPdf = FakePdfDocument(
      pageSizes: const [
        ui.Size(595, 842),
        ui.Size(595, 842),
        ui.Size(595, 842),
      ],
    );
    PdfRenderService.debugOpenerOverride = (source) async =>
        source.wholeFilePath!.endsWith('sub.pdf') ? subPdf : mainPdf;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: hostIn(mainSlot, viewerId: 'media-viewer')),
              Expanded(child: hostIn(subSlot, viewerId: 'media-viewer-sub')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    // Each panel answers to its own key, and to ONLY its own.
    expect(
      find.byKey(const ValueKey<String>('media-viewer-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('media-viewer-sub-panel')),
      findsOneWidget,
    );

    mainSlot.request.value = const MediaViewerRequest(
      path: 'C:/work/main.pdf',
      kind: MediaAssetKind.pdf,
    );
    subSlot.request.value = const MediaViewerRequest(
      path: 'C:/work/sub.pdf',
      kind: MediaAssetKind.pdf,
    );
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget, reason: 'the main viewer');
    expect(find.text('1 / 3'), findsOneWidget, reason: 'the sub viewer');

    // Stepping ONE viewer moves that one only — the two share a widget
    // class and nothing else.
    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-sub-next-page-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget, reason: 'the main did not move');
  });

  testWidgets('유저 확정 ⑬: a browser row dragged over the viewer lights the '
      'accent frame while it hovers, and dropping it opens HERE', (
    tester,
  ) async {
    final dropped = <MediaAssetDragData>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Column(
            children: [
              const Draggable<MediaAssetDragData>(
                data: MediaAssetDragData(
                  path: 'C:/art/layout.pdf',
                  name: 'layout',
                ),
                feedback: SizedBox(width: 40, height: 20),
                child: ColoredBox(
                  color: Color(0xFF404040),
                  child: SizedBox(width: 80, height: 40),
                ),
              ),
              Expanded(
                child: MediaViewerTabHost(
                  viewerId: 'media-viewer',
                  session: session,
                  request: slot.request,
                  position: slot.position,
                  onAssetDropped: dropped.add,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final viewer = find.byKey(const ValueKey<String>('media-viewer-panel'));
    bool accentFrameShown() => tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .any(
          (box) =>
              box.decoration is BoxDecoration &&
              (box.decoration as BoxDecoration).border?.top.color ==
                  AppColors.accent &&
              (box.decoration as BoxDecoration).border?.top.width == 2,
        );
    expect(accentFrameShown(), isFalse, reason: 'idle: no frame');

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Draggable<MediaAssetDragData>)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(viewer));
    await tester.pump();
    expect(accentFrameShown(), isTrue, reason: 'hovering: the accent frame');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(accentFrameShown(), isFalse, reason: 'landed: the frame is gone');
    expect(dropped.map((data) => data.path), ['C:/art/layout.pdf']);
  });

  testWidgets('an image request decodes through the import codec and '
      'paints; a missing file reports the load failure', (tester) async {
    // Real IO ONLY inside runAsync — a createTemp awaited straight in the
    // test body deadlocks the fake-async zone.
    final tempDir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('anicel-viewer'),
    ))!;
    deleteAfterSessionEnds(tempDir);
    await pumpViewer(tester);

    final path = await tester.runAsync(
      () => writeSolidPng(
        tempDir,
        'ref.png',
        width: 16,
        height: 16,
        rgba: 0xEE0000FF,
      ),
    );

    slot.request.value = MediaViewerRequest(path: path!, kind: MediaAssetKind.image);
    expect(
      await settleAsync(
        tester,
        () =>
            tester.any(find.byKey(const ValueKey<String>('media-viewer-page'))),
      ),
      isTrue,
    );

    slot.request.value = MediaViewerRequest(
      path: '${tempDir.path}${Platform.pathSeparator}gone.png',
      kind: MediaAssetKind.image,
    );
    // ⚠️CONTAINS, not equals. The message carries the engine's own reason
    // under the localized sentence now, so an exact match asserts the
    // absence of a detail this test never cared about — see
    // `no_reader_is_not_cannot_read_test`.
    expect(
      await settleAsync(
        tester,
        () => tester.any(
          find.textContaining(AppText.strings.mediaViewerLoadFailed),
        ),
      ),
      isTrue,
    );
  });

  testWidgets('a document that turns its OWN pages gets a play button, and '
      'playing walks the frames at its rate', (tester) async {
    // 유저 2026-08-29: 「비디오 … 불러와서 재생가능하게」. The viewer asks
    // the DOCUMENT whether it plays, so this drives it through the same
    // fake a PDF uses — nothing in the viewer is about movies.
    final fake = FakePdfDocument(
      pageSizes: const [
        ui.Size(320, 240),
        ui.Size(320, 240),
        ui.Size(320, 240),
      ],
      framesPerSecond: 10,
    );
    PdfRenderService.debugOpenerOverride = (_) async => fake;
    await pumpViewer(tester);
    slot.request.value = const MediaViewerRequest(
      path: 'C:/work/clip.mp4',
      kind: MediaAssetKind.pdf,
    );
    await tester.pumpAndSettle();

    final play = find.byKey(
      const ValueKey<String>('media-viewer-transport-play'),
    );
    expect(play, findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.tap(play);
    await tester.pump();
    expect(_tooltipOf(tester, play), AppText.strings.menuPause);

    // 100ms a frame at 10fps: each tick turns one page.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);

    // ⛔It stops ITSELF at the end rather than leaving a timer spinning on
    // a page that cannot advance.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(
      _tooltipOf(tester, play),
      AppText.strings.menuPlay,
      reason: 'the button says PLAY again once it has stopped itself',
    );
  });

  testWidgets('a document that does NOT turn its own pages has no play '
      'button — 유저 확정 ⑥: no permanently disabled promise', (tester) async {
    final fake = FakePdfDocument(
      pageSizes: const [ui.Size(595, 842), ui.Size(595, 842)],
    );
    PdfRenderService.debugOpenerOverride = (_) async => fake;
    await pumpViewer(tester);
    slot.request.value = const MediaViewerRequest(
      path: 'C:/work/conte.pdf',
      kind: MediaAssetKind.pdf,
    );
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('media-viewer-transport-play')),
      findsNothing,
    );
  });
}

/// The tooltip an [AppIconButton] is showing — what its face, the box the
/// key names, holds (a `Tooltip` under the key until 2026-10-24, when the
/// face began summoning the one window the light faces share).
String? _tooltipOf(WidgetTester tester, Finder button) =>
    tester.widget<AppIconButtonFace>(button).tooltip;
