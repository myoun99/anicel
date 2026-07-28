import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// R28 #7: the eyedropper against the REAL session, not a stub resolver.
///
/// The unit suite for [sampleCompositeColor] passes surfaces in directly,
/// so it could never catch a resolver that hands back nothing — which is
/// exactly the failure the user saw ("그림이 있는 레이어인데도 뭐든
/// #EDEDED"): every miss falls through to the paper color, silently.
void main() {
  testWidgets('R28 #7: a drawn cel samples its ink through the production '
      'resolver, at the frame the playhead is on', (tester) async {
    await tester.runAsync(() async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);

      final layer = session.requireActiveCut.layers.firstWhere(
        (candidate) => candidate.kind == LayerKind.animation,
      );
      session.selectLayer(layer.id);
      session.selectFrameIndex(0);
      session.createDrawingAtCurrentFrame();

      final frame = session.selectedFrame!;
      final frameKey = session.brushFrameKeyForCut(
        session.requireActiveCut,
        layer.id,
        frame.id,
      );
      final canvasSize = session.requireActiveCut.canvasSize;
      final centerX = canvasSize.width / 2;
      final centerY = canvasSize.height / 2;

      BrushFrameEditingCoordinator(
        initialFrameKey: frameKey,
        frameStore: session.brushFrameStore,
        sessionStore: BrushFrameEditSessionStore(canvasSize: canvasSize),
        historyPolicy: const BrushHistoryPolicy(
          userUndoLimit: 8,
          deferredBakeRatio: 0,
        ),
      ).commitSourceStroke(
        sourceDabs: [
          for (var index = 0; index < 20; index += 1)
            BrushDab(
              center: CanvasPoint(x: centerX - 100 + index * 10, y: centerY),
              color: 0xFF000000,
              size: 40,
              opacity: 1,
              flow: 1,
              hardness: 1,
              tipShape: BrushTipShape.round,
              pressure: 1,
              sequence: index,
            ),
        ],
      );

      int sampleAt(double x, double y) => sampleCompositeColor(
        cut: session.requireActiveCut,
        frameIndex: session.currentFrameIndex,
        surfaceResolver: session.brushSurfaceForLayerFrame,
        point: CanvasPoint(x: x, y: y),
        fxBypassedLayerIds: session.fxBypassedLayerIds,
        paperColor: session.projectBackground.argb,
      );

      // Dead center of the stroke: opaque black ink.
      expect(
        sampleAt(centerX, centerY),
        0xFF000000,
        reason: 'R28 #7: the production resolver must see the drawn cel — '
            'a null surface silently reads as paper',
      );

      // Far from the stroke: the paper, as before.
      expect(sampleAt(20, 20), session.projectBackground.argb);
    });
  });
}
