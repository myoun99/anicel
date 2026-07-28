import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';

/// Content-stress probe for the storyboard thumbnail pipeline: real stroke
/// content + camera key + layer transform through the REAL renderer.
void main() {
  testWidgets('thumbnail-size camera render succeeds with drawn content, '
      'camera keys and a layer transform', (tester) async {
    await tester.runAsync(() async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final cut = session.requireActiveCut;
      final layer = cut.layers.firstWhere(
        (candidate) => candidate.kind == LayerKind.animation,
      );

      // Expose a drawn frame at frame 0 through the session's normal flow.
      session.selectLayer(layer.id);
      session.selectFrameIndex(0);
      session.createDrawingAtCurrentFrame();
      final frame = session.selectedFrame!;
      final frameKey = session.brushFrameKeyForCut(
        session.requireActiveCut,
        layer.id,
        frame.id,
      );
      // Dabs around the CANVAS CENTER — the default canvas is much larger
      // than a video frame, and the camera views its center region.
      final canvasSize = session.requireActiveCut.canvasSize;
      final centerX = canvasSize.width / 2;
      final centerY = canvasSize.height / 2;
      BrushFrameEditingCoordinator(
        initialFrameKey: frameKey,
        frameStore: session.brushFrameStore,
        sessionStore: BrushFrameEditSessionStore(
          canvasSize: session.requireActiveCut.canvasSize,
        ),
        historyPolicy: const BrushHistoryPolicy(
          userUndoLimit: 8,
          deferredBakeRatio: 0,
        ),
      ).commitSourceStroke(
        sourceDabs: [
          for (var index = 0; index < 40; index += 1)
            BrushDab(
              center: CanvasPoint(x: centerX - 400 + index * 20, y: centerY),
              color: 0xFF000000,
              size: 60,
              opacity: 1,
              flow: 1,
              hardness: 1,
              tipShape: BrushTipShape.round,
              pressure: 1,
              sequence: index,
            ),
        ],
      );

      // Camera key + a layer transform (small shift + animated opacity) at
      // frame 0 — the merged R3 surface area. Position keys are ABSOLUTE
      // canvas points (identity = canvas center).
      session.setCameraKeyframeAtCurrentFrame(session.cameraPoseAtCurrentFrame);
      session.updateLayerTransformTrack(
        layer.id,
        TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>().withKey(
            0,
            CanvasPoint(x: centerX + 30, y: centerY + 20),
          ),
          opacity: PropertyTrack<double>().withKey(0, 0.7),
        ),
      );

      final image = await ExportFrameRenderer(session: session).renderComposite(
        ExportFrameTask(cut: session.requireActiveCut, frameIndex: 0),
        ExportSizeMode.camera,
        outputSize: const CanvasSize(width: 128, height: 72),
      );
      expect(image.width, 128);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      expect(bytes, isNotNull);

      // The ARTWORK must actually land in the thumbnail — count dark
      // pixels (the black stroke against the white paper).
      var darkPixels = 0;
      for (var offset = 0; offset < bytes!.lengthInBytes; offset += 4) {
        final r = bytes.getUint8(offset);
        final g = bytes.getUint8(offset + 1);
        final b = bytes.getUint8(offset + 2);
        if (r < 100 && g < 100 && b < 100) {
          darkPixels += 1;
        }
      }
      expect(
        darkPixels,
        greaterThan(4),
        reason: 'the stroke must be visible in the camera-view thumbnail',
      );
    });
  });
}
