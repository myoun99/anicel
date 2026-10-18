import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';

import '../../helpers/device_viewport.dart';
import '../../helpers/fake_pdf_document.dart';

/// 🗣️F-380 (유저 2026-10-17): 「뷰어패널에서 잘라내기쓸때 개미행렬 라이브가
/// 안보임. 법 통일해서 보이도록」.
///
/// Every outline the cut draws is SEEN on the viewer while it is drawn, as
/// it is on the canvas: read off the screen, a patch of the outline's own
/// edge before it was begun and while it is being drawn. Measured
/// 2026-10-18 before the fix: the drag-drawn three were seen, and a polygon
/// tapped out showed nothing — its vertices are kept on a selection
/// channel, and the viewer had none.
void main() {
  const path = 'C:/work/reference.pdf';

  late EditorSessionManager session;
  late MediaViewerSlot slot;
  late CutPieceSlot held;
  late CanvasSelectionCommands selection;
  late ValueNotifier<BrushToolState> tool;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    slot = MediaViewerSlot();
    held = CutPieceSlot();
    selection = CanvasSelectionCommands();
    tool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final document = FakePdfDocument(pageSizes: const [ui.Size(1200, 900)]);
    PdfRenderService.debugOpenerOverride = (_) async => document;
  });

  tearDown(() {
    PdfRenderService.debugResetForTests();
    tool.dispose();
    slot.dispose();
    session.dispose();
  });

  /// The viewer as the workspace builds it — handed a channel, as the
  /// window hands each viewer its own — with the cut armed on [shape], at
  /// a third of the page's size.
  Future<void> pumpViewer(WidgetTester tester, CanvasShapeKind shape) async {
    // One device pixel to a logical one: the screen is read at the points
    // the hand is put at.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    tool.value = BrushToolState.defaults.copyWith(
      tool: CanvasTool.cut,
      cutShape: shape,
    );
    slot.framedFor.value = path;
    slot.viewport.value = CanvasViewport(zoom: 0.34, panX: 40, panY: 40);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaViewerTabHost(
            viewerId: 'media-viewer',
            session: session,
            request: slot.request,
            position: slot.position,
            viewportController: slot.viewport,
            framedFor: slot.framedFor,
            selection: selection,
            brushTool: tool,
            cutPieceSlot: held,
          ),
        ),
      ),
    );
    slot.open(const MediaViewerRequest(path: path, kind: MediaAssetKind.pdf));
    await tester.pumpAndSettle();
  }

  /// Where page point ([x], [y]) is on screen.
  Offset onScreen(WidgetTester tester, double x, double y) {
    final panel = tester.widget<BrushCanvasPanel>(
      find.byType(BrushCanvasPanel),
    );
    final local = renderOf(
      tester,
      panel.publishedViewport,
    ).canvasToViewport(CanvasPoint(x: x, y: y));
    return tester.getTopLeft(
          find.byKey(const ValueKey<String>('brush-canvas-editor-viewport')),
        ) +
        Offset(local.x, local.y);
  }

  /// The screen's pixels in a small square about [at].
  Future<List<int>> screenAround(WidgetTester tester, Offset at) async {
    final screen = tester.layers.first as OffsetLayer;
    final bytes = await tester.runAsync(() async {
      final image = await screen.toImage(
        Rect.fromCenter(center: at, width: 9, height: 9),
      );
      try {
        return (await image.toByteData())!;
      } finally {
        image.dispose();
      }
    });
    return bytes!.buffer.asUint8List();
  }

  // Each outline from the page's (300, 200), and a point on an edge of it.
  for (final (shape, edge) in [
    (CanvasShapeKind.rect, const Offset(450, 200)),
    (CanvasShapeKind.ellipse, const Offset(450, 200)),
    // Through the middle of the drag: its first leg.
    (CanvasShapeKind.lasso, const Offset(375, 275)),
    // Tapped along the top and down the right: its first leg.
    (CanvasShapeKind.polygon, const Offset(450, 200)),
  ]) {
    testWidgets('a $shape cut is seen on the viewer as it is drawn', (
      tester,
    ) async {
      await pumpViewer(tester, shape);
      final from = onScreen(tester, 300, 200);
      final to = onScreen(tester, 600, 500);
      final at = onScreen(tester, edge.dx, edge.dy);
      final before = await screenAround(tester, at);

      if (shape == CanvasShapeKind.polygon) {
        for (final vertex in [from, Offset(to.dx, from.dy), to]) {
          await tester.tapAt(vertex, kind: PointerDeviceKind.mouse);
          await tester.pump();
        }
      } else {
        final gesture = await tester.startGesture(
          from,
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(gesture.up);
        await tester.pump();
        await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
        await tester.pump();
        await gesture.moveTo(to);
        await tester.pump();
      }

      expect(
        await screenAround(tester, at),
        isNot(before),
        reason: 'the outline is drawn where it goes, while it is drawn',
      );
    });
  }

  testWidgets('a polygon tapped out on the viewer closes on its first vertex '
      '— and cuts what it encloses', (tester) async {
    await pumpViewer(tester, CanvasShapeKind.polygon);
    final vertices = [
      onScreen(tester, 300, 200),
      onScreen(tester, 600, 200),
      onScreen(tester, 600, 500),
    ];
    for (final vertex in [...vertices, vertices.first]) {
      await tester.tapAt(vertex, kind: PointerDeviceKind.mouse);
      await tester.pump();
    }
    // The read and the hold land on the microtasks after the close.
    await tester.pump();

    expect(held.piece, isNotNull, reason: 'the cut reached the held piece');
    expect(selection.hasOpenPolygon, isFalse, reason: 'it closed');
  });
}
