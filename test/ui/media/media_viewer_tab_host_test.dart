import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/fake_pdf_document.dart';

/// The media viewer panel (R4, §6-h): images and PDF pages inside the
/// canvas shell, page stepping, and the two honest refusals (no PDF
/// renderer / no viewer for the kind). The PDF renderer is INJECTED —
/// flutter_tester never touches the FFI plugin.
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

  testWidgets('an audio request states the kind has no viewer', (tester) async {
    await pumpViewer(tester);
    slot.request.value = const MediaViewerRequest(
      path: 'C:/work/foot.wav',
      kind: MediaAssetKind.audio,
    );
    await tester.pumpAndSettle();
    expect(find.text(AppText.strings.mediaViewerCannotDisplay), findsOneWidget);
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

    final path = await tester.runAsync(() async {
      final pixels = Uint8List(16 * 16 * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i] = 0xEE;
        pixels[i + 3] = 0xFF;
      }
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels,
        16,
        16,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final image = await completer.future;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('${tempDir.path}${Platform.pathSeparator}ref.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      return file.path;
    });

    slot.request.value = MediaViewerRequest(path: path!, kind: MediaAssetKind.image);
    await settleAsync(
      tester,
      () => tester.any(find.byKey(const ValueKey<String>('media-viewer-page'))),
    );

    slot.request.value = MediaViewerRequest(
      path: '${tempDir.path}${Platform.pathSeparator}gone.png',
      kind: MediaAssetKind.image,
    );
    await settleAsync(
      tester,
      () => tester.any(find.text(AppText.strings.mediaViewerLoadFailed)),
    );
  });
}
