import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors, buildAppTheme;
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/fake_pdf_document.dart';
import '../../helpers/solid_png_fixture.dart';

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
  Widget hostIn(MediaViewerSlot slot, {required String viewerId}) =>
      ValueListenableBuilder<int>(
        valueListenable: slot.position,
        builder: (context, position, _) => MediaViewerTabHost(
          viewerId: viewerId,
          session: session,
          request: slot.request,
          position: position,
          onPositionChanged: (next) => slot.position.value = next,
        ),
      );

  Future<void> pumpViewer(
    WidgetTester tester, {
    String viewerId = 'media-viewer',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: hostIn(slot, viewerId: viewerId)),
      ),
    );
    await tester.pump();
  }

  /// Real IO completes inside runAsync, but the await continuations are
  /// fake-zone microtasks only pump() drains — interleave the two until
  /// [ready] (the import-dialog test's loop).
  Future<void> settleAsync(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 40 && !ready(); i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(ready(), isTrue);
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

  testWidgets('a PDF request pages through the fake document: readout, '
      'next/previous stepping, lazy per-page renders', (tester) async {
    final fake = FakePdfDocument(
      pageSizes: const [ui.Size(595, 842), ui.Size(595, 842)],
    );
    PdfRenderService.debugOpenerOverride = (path) async => fake;
    await pumpViewer(tester);

    slot.request.value = const MediaViewerRequest(
      path: 'C:/work/conte.pdf',
      kind: MediaAssetKind.pdf,
      name: 'conte',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('media-viewer-page')),
      findsOneWidget,
    );
    expect(find.text('1 / 2'), findsOneWidget);
    expect(
      fake.renderRequests.map((request) => request.$1),
      [0],
      reason: 'only the visible page rendered (§6-m lazy)',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-next-page-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(fake.renderRequests.map((request) => request.$1), [0, 1]);
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
    PdfRenderService.debugOpenerOverride = (path) async =>
        path.endsWith('sub.pdf') ? subPdf : mainPdf;

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
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } on Object {
        // Windows keeps handles briefly.
      }
    });
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
    await settleAsync(
      tester,
      () => tester.any(find.byKey(const ValueKey<String>('media-viewer-page'))),
    );

    slot.request.value = MediaViewerRequest(
      path: '${tempDir.path}${Platform.pathSeparator}gone.png',
      kind: MediaAssetKind.image,
    );
    // ⚠️CONTAINS, not equals. The message carries the engine's own reason
    // under the localized sentence now, so an exact match asserts the
    // absence of a detail this test never cared about — see
    // `no_reader_is_not_cannot_read_test`.
    await settleAsync(
      tester,
      () => tester.any(
        find.textContaining(AppText.strings.mediaViewerLoadFailed),
      ),
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
    PdfRenderService.debugOpenerOverride = (path) async => fake;
    await pumpViewer(tester);
    slot.request.value = const MediaViewerRequest(
      path: 'C:/work/clip.mp4',
      kind: MediaAssetKind.pdf,
      name: 'clip',
    );
    await tester.pumpAndSettle();

    final play = find.byKey(
      const ValueKey<String>('media-viewer-play-button'),
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
    PdfRenderService.debugOpenerOverride = (path) async => fake;
    await pumpViewer(tester);
    slot.request.value = const MediaViewerRequest(
      path: 'C:/work/conte.pdf',
      kind: MediaAssetKind.pdf,
    );
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('media-viewer-play-button')),
      findsNothing,
    );
  });
}

/// The tooltip an [AppIconButton] is showing — its face renders the Tooltip
/// inside the box the key names, so the message hangs under the button's own
/// key (it rendered through a Material `IconButton` until 2026-09-10; same place).
String? _tooltipOf(WidgetTester tester, Finder button) => tester
    .widget<Tooltip>(
      find.descendant(of: button, matching: find.byType(Tooltip)),
    )
    .message;
