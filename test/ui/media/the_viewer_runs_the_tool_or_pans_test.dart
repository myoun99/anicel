import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/services/persistence/app_memory_settings.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';

import '../../helpers/fake_pdf_document.dart';
import '../../helpers/device_viewport.dart';

/// F-80 (유저 2026-09-16): 「잘라내기는 작동하게하고싶어서 선택한 도구마다
/// 다르게하자. 작동가능한거면 해당 도구 작동시키고, 불가능하면 팬」.
///
/// The viewer has nothing to draw on, so the CUT is the one tool that can
/// act here (I-14). Before this round a press with any other tool did
/// NOTHING: the viewer swapped in an inert tool state and the press fell on
/// the floor. The surface answers one question now
/// ([BrushCanvasPanel.runsTheSelectedTool]) and a press it cannot act on
/// moves the page instead.
void main() {
  const path = 'C:/work/reference.pdf';
  const pageSize = ui.Size(1200, 900);

  late EditorSessionManager session;
  late MediaViewerSlot slot;
  late CutPieceSlot held;
  late ValueNotifier<BrushToolState> tool;
  late FakePdfDocument document;

  BrushToolState cutTool() => BrushToolState.defaults.copyWith(
    tool: CanvasTool.cut,
    cutShape: CanvasShapeKind.rect,
  );

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    AppMemory.settings.value = AppMemorySettings(
      allowanceBytes: session.deviceCacheBudgets.total,
    );
    slot = MediaViewerSlot();
    held = CutPieceSlot();
    tool = ValueNotifier<BrushToolState>(cutTool());
    document = FakePdfDocument(pageSizes: const [pageSize]);
    PdfRenderService.debugOpenerOverride = (_) async => document;
  });

  tearDown(() {
    PdfRenderService.debugResetForTests();
    AppMemory.settings.value = const AppMemorySettings();
    tool.dispose();
    slot.dispose();
    session.dispose();
  });

  Future<void> pumpViewer(WidgetTester tester) async {
    slot.framedFor.value = path;
    slot.viewport.value = CanvasViewport(zoom: 0.34, panX: 40, panY: 40);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: slot.position,
            builder: (context, position, _) => MediaViewerTabHost(
              viewerId: 'media-viewer',
              session: session,
              request: slot.request,
              position: position,
              onPositionChanged: (next) => slot.position.value = next,
              viewportController: slot.viewport,
              framedFor: slot.framedFor,
              brushTool: tool,
              cutPieceSlot: held,
            ),
          ),
        ),
      ),
    );
    slot.open(const MediaViewerRequest(path: path, kind: MediaAssetKind.pdf));
    await tester.pumpAndSettle();
  }

  Offset onScreen(WidgetTester tester, double x, double y) {
    final panel = tester.widget<BrushCanvasPanel>(
      find.byType(BrushCanvasPanel),
    );
    final view = renderOf(tester, panel.publishedViewport);
    final local = view.canvasToViewport(CanvasPoint(x: x, y: y));
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey<String>('brush-canvas-editor-viewport')),
    );
    return origin + Offset(local.x, local.y);
  }

  Future<void> mouseDrag(WidgetTester tester) async {
    final from = onScreen(tester, 300, 200);
    final to = onScreen(tester, 600, 500);
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the CUT can act here, so a press runs it and the page stays '
      'put', (tester) async {
    await pumpViewer(tester);
    final before = slot.viewport.value!;

    await mouseDrag(tester);

    expect(held.isEmpty, isFalse, reason: 'the armed cut took the press');
    expect(
      slot.viewport.value!.panX,
      before.panX,
      reason: 'and nothing panned',
    );
    expect(slot.viewport.value!.panY, before.panY);
  });

  for (final other in const [
    CanvasTool.brush,
    CanvasTool.eraser,
    CanvasTool.fill,
    CanvasTool.select,
  ]) {
    testWidgets('a ${other.name} cannot act here, so the press PANS', (
      tester,
    ) async {
      tool.value = BrushToolState.defaults.copyWith(tool: other);
      await pumpViewer(tester);
      final before = slot.viewport.value!;

      await mouseDrag(tester);

      expect(
        slot.viewport.value!.panX,
        greaterThan(before.panX + 50),
        reason: 'the press moved the page instead of falling on the floor',
      );
      expect(held.isEmpty, isTrue, reason: 'and cut nothing');
      expect(document.regionReads, isEmpty);
    });
  }
}
