import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_state.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_edit_session_state.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/canvas/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/layer_pose_paint.dart';

/// The draw-through wrap (R3 ⑩): wrapping the interactive view in
/// `Transform(layerPoseViewportWrapMatrix(...))` shows the active layer
/// POSED while pointer input inverse-maps through the same matrix, so
/// strokes land in ORIGINAL artwork coordinates.
const _anchorKey = ValueKey<String>('draw-through-anchor');
const _canvasSize = CanvasSize(width: 8, height: 8);

BrushEditSessionState _sessionState() {
  return BrushEditSessionState(
    canvasState: CanvasSurfaceState(
      currentSurface: BitmapSurface(canvasSize: _canvasSize, tileSize: 2),
    ),
    materializationHistoryState: BrushBitmapMaterializationHistoryState(),
  );
}

Future<void> _pumpPosedView(
  WidgetTester tester, {
  required TransformPose pose,
  required ValueChanged<List<BrushDab>> onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          // The UNTRANSFORMED anchor box marks the artwork origin on
          // screen; the Transform inside poses the interactive view the
          // same way BrushCanvasPanel wraps it.
          child: SizedBox(
            key: _anchorKey,
            width: _canvasSize.width.toDouble(),
            height: _canvasSize.height.toDouble(),
            child: Transform(
              transform: layerPoseViewportWrapMatrix(
                pose,
                _canvasSize,
                CanvasViewport(),
              ),
              child: InteractiveBrushEditCanvasView(
                sessionState: _sessionState(),
                layerId: const LayerId('layer-a'),
                frameId: const FrameId('frame-a'),
                inputSettings: BrushEditCanvasInputSettings(),
                onSourceStrokeCommitted: (strokeData) =>
                    onResult(strokeData.sourceDabs),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _tapAtScreen(WidgetTester tester, Offset screenPoint) async {
  final origin = tester.getTopLeft(find.byKey(_anchorKey));
  final gesture = await tester.startGesture(origin + screenPoint, pointer: 1);
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

void main() {
  group('draw-through through a posed interactive view', () {
    testWidgets('a translated pose inverse-maps taps to original artwork '
        'coordinates', (tester) async {
      final results = <List<BrushDab>>[];
      // Canvas center (4,4) moves to (6,5): everything shifts +2,+1.
      await _pumpPosedView(
        tester,
        pose: TransformPose(center: CanvasPoint(x: 6, y: 5)),
        onResult: results.add,
      );

      await _tapAtScreen(tester, const Offset(5, 4));

      expect(results, hasLength(1));
      final dab = results.single.single;
      expect(dab.center.x, closeTo(3, 0.01));
      expect(dab.center.y, closeTo(3, 0.01));
    });

    testWidgets('a zoomed + rotated pose still round-trips exactly '
        '(drawing on what you see lands where the composite shows it)', (
      tester,
    ) async {
      final results = <List<BrushDab>>[];
      // 90° clockwise about the canvas center at zoom 1: artwork (2,2)
      // shows at (6,2).
      await _pumpPosedView(
        tester,
        pose: TransformPose(
          center: CanvasPoint(x: 4, y: 4),
          rotationDegrees: 90,
        ),
        onResult: results.add,
      );

      await _tapAtScreen(tester, const Offset(6, 2));

      expect(results, hasLength(1));
      final dab = results.single.single;
      expect(dab.center.x, closeTo(2, 0.01));
      expect(dab.center.y, closeTo(2, 0.01));
    });

    testWidgets('taps outside the POSED artwork never start a stroke '
        '(hit testing follows the shown footprint)', (tester) async {
      final results = <List<BrushDab>>[];
      // Shrink to half size about the center: the artwork occupies
      // (2,2)-(6,6) on screen.
      await _pumpPosedView(
        tester,
        pose: TransformPose(center: CanvasPoint(x: 4, y: 4), zoom: 0.5),
        onResult: results.add,
      );

      await _tapAtScreen(tester, const Offset(1, 1));

      expect(results, isEmpty);
    });
  });
}
