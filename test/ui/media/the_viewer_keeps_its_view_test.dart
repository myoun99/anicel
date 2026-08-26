import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/viewport_point.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';

/// F-39 — 유저 2026-08-27: 「뷰어패널이나 캔버스베이스패널? 확대나 팬 상태같은게
/// 저장안되는거같음. 뭐냐면 확대해두고 패널 닫고 다시열면 초기화되있음. 다시
/// 확인하니 **뷰어패널만** 이런데, **타임시트패널등은 무사**하단거 보면 통일화를
/// 제대로 안한거같으니 제대로 통일」.
///
/// The user already split the axis: the same view survives elsewhere. So the
/// law about where a panel's view lives is written and kept somewhere, and
/// the viewer is the one outside it.
void main() {
  late EditorSessionManager session;
  late MediaViewerSlot slot;
  late Directory dir;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    slot = MediaViewerSlot();
    dir = Directory.systemTemp.createTempSync('anicel-viewer-view');
  });

  tearDown(() {
    PdfRenderService.debugResetForTests();
    slot.dispose();
    session.dispose();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget host() => MaterialApp(
    home: Scaffold(
      body: MediaViewerTabHost(
        viewerId: 'media-viewer',
        session: session,
        request: slot.request,
        position: slot.position.value,
        onPositionChanged: (next) => slot.position.value = next,
        // The workspace owns these — the whole point of the slot.
        viewportController: slot.viewport,
        framedFor: slot.framedFor,
      ),
    ),
  );

  /// A real 16×16 PNG on disk, so the viewer has a document with a size of
  /// its own. ⚠️Without one `docSize` falls to its 640×480 placeholder and
  /// nothing ever asks to be framed — the test would pass on a bug.
  Future<String> writeImage(WidgetTester tester) async {
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
      final file = File('${dir.path}${Platform.pathSeparator}ref.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      return file.path;
    });
    return path!;
  }

  /// What the host is currently asking the canvas panel to frame — the
  /// host's own output, and the thing this round changes.
  CanvasAutoFrameRequest? autoFrameNow(WidgetTester tester) => tester
      .widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel))
      .autoFrame;

  /// Pumps until the viewer has actually shown a page, which is when the
  /// frame request it makes has gone out.
  /// The canvas size the host is handing the panel. 640×480 is the
  /// PLACEHOLDER it uses before a document has loaded, so this is how the
  /// harness knows the load actually finished — the page key is on a
  /// container that exists either way, which is what made the first version
  /// of these tests measure an empty viewer and pass with the fix deleted.
  Size panelCanvas(WidgetTester tester) {
    final panel = tester.widget<BrushCanvasPanel>(
      find.byType(BrushCanvasPanel),
    );
    return Size(
      panel.canvasSize.width.toDouble(),
      panel.canvasSize.height.toDouble(),
    );
  }

  Future<void> settleLoaded(WidgetTester tester) async {
    for (var i = 0; i < 60; i += 1) {
      // ⚠️A REAL delay inside runAsync: decoding a PNG is genuine async I/O
      // and a zero-duration microtask drain never lets it finish.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      if (panelCanvas(tester) != const Size(640, 480)) {
        return;
      }
    }
    // 🚨A LOOP THAT GIVES UP QUIETLY IS AN INSTRUMENT THAT LIES. Without
    // this the document simply never loaded and every assertion below was
    // measuring an empty viewer — which is how the first version of these
    // tests stayed green with the fix deleted.
    fail('the viewer never showed a page — the document did not load');
  }

  testWidgets('reopening a viewer on the SAME document leaves the view alone',
      (tester) async {
    final path = await writeImage(tester);
    slot.request.value = MediaViewerRequest(
      path: path,
      kind: MediaAssetKind.image,
    );
    await tester.pumpWidget(host());
    await settleLoaded(tester);
    await tester.pump(const Duration(milliseconds: 32));
    expect(
      autoFrameNow(tester),
      isNotNull,
      reason: 'a document opened for the first time IS framed — that is what '
          'the reframe exists for, and the fixture has to see it happen or '
          'the reopen assertion is measuring an empty viewer',
    );

    // The user zooms in and reads at that scale.
    final zoomed = CanvasViewport().zoomedAround(
      nextZoom: 3.5,
      anchor: ViewportPoint(x: 120, y: 80),
    );
    slot.viewport.value = zoomed;
    await tester.pump();

    // Close the panel — the host unmounts entirely, which is what a docked
    // panel does when its tab goes away, and it takes the State that used to
    // remember "already framed" with it.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();

    // Reopen it. The document loads again, and THAT is what used to be read
    // as "a new document, frame it".
    await tester.pumpWidget(host());
    await settleLoaded(tester);
    await tester.pump(const Duration(milliseconds: 32));

    // 🚨THE REQUEST, not the viewport. What the fix changes is whether the
    // host ASKS to be framed; whether the panel then reaches the stored
    // view depends on real layout, and a widget test's panel does not
    // reframe at all — measured. Asserting the viewport would have gone
    // green with the fix deleted, which is exactly what it did the first
    // time this was written.
    expect(
      autoFrameNow(tester),
      isNull,
      reason: '유저: 「다시 열었을때 이전 배율 그대로 있었다가, fit으로 '
          '초기화되」 — reopening is not a new document, so nothing asks',
    );
    expect(
      slot.viewport.value,
      zoomed,
      reason: 'and the view the user set is still the one stored',
    );
  });

  testWidgets('a DIFFERENT document still gets framed — that is what the '
      'reframe is for', (tester) async {
    final first = await writeImage(tester);
    slot.request.value = MediaViewerRequest(
      path: first,
      kind: MediaAssetKind.image,
    );
    await tester.pumpWidget(host());
    await settleLoaded(tester);
    await tester.pump(const Duration(milliseconds: 32));

    // A deep zoom, the case the reframe exists for: without it a small next
    // document would land entirely off-screen and the panel would look blank.
    slot.viewport.value = CanvasViewport().zoomedAround(
      nextZoom: 12,
      anchor: ViewportPoint(x: 900, y: 900),
    );
    await tester.pump();

    final second = await tester.runAsync(() async {
      final file = File('${dir.path}${Platform.pathSeparator}other.png');
      await file.writeAsBytes(await File(first).readAsBytes());
      return file.path;
    });
    slot.request.value = MediaViewerRequest(
      path: second!,
      kind: MediaAssetKind.image,
    );
    // ⚠️`settleLoaded` cannot be used here: a page is ALREADY on screen from
    // the first document, so it would return before the second even
    // decoded. Pump until the record actually moves, or give up loudly.
    for (var i = 0; i < 80 && slot.framedFor.value != second; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }

    expect(
      slot.framedFor.value,
      second,
      reason: '⛔the memory is the DOCUMENT, so a new one is framed and its '
          'own reopen is then left alone',
    );
  });
}
