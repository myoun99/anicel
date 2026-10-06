import 'dart:ui';

import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../models/camera_pose.dart';
import '../models/canvas_size.dart';
import '../models/canvas_viewport.dart';
import 'camera_projection_matrix.dart';
import 'layer_pose_matrix.dart';
import 'viewport_transform_matrix.dart';

export 'camera_projection_matrix.dart' show cameraProjectionMatrix;
export 'layer_pose_matrix.dart'
    show
        LayerPlacement,
        LayerPoseSample,
        canvasToArtwork,
        guideSpaceOf,
        layerPoseMatrix,
        placementMatrix,
        placementOf;

/// Applies a layer's [placement] to [canvas] before its image draws at the
/// origin — see [placementMatrix] for the mapping and [rasterScale].
///
/// EVERY composite route shares this one function — playback composites,
/// camera renders (export/thumbnails) and the editing canvas's layer
/// stack — so a transformed layer looks byte-identical everywhere
/// (three-route parity discipline).
void applyLayerPlacement(
  Canvas canvas,
  LayerPlacement placement, {
  double rasterScale = 1,
}) {
  canvas.transform(
    placementMatrix(placement, rasterScale: rasterScale).storage,
  );
}

/// Applies the camera projection to [canvas] so canvas-space drawing lands
/// in the camera's OUTPUT space — see [cameraProjectionMatrix]. The export
/// renderer and the playback painter both go through here, so the two
/// routes agree about the same frame by construction.
void applyCameraProjection(
  Canvas canvas,
  CameraPose pose,
  CanvasSize cameraFrameSize, {
  CanvasSize? outputSize,
}) {
  canvas.transform(
    cameraProjectionMatrix(
      pose,
      cameraFrameSize,
      outputSize: outputSize,
    ).storage,
  );
}

/// The SCREEN-space wrap matrix for a widget that already renders artwork
/// under [viewport]: `V · P · V⁻¹` — wrapping the interactive brush view in
/// `Transform(transform: ...)` with this matrix shows the active layer
/// PLACED exactly like every composite route, while Flutter's hit testing
/// routes pointers through the inverse, so strokes record in original
/// artwork coordinates (draw-through: drawing on what you see lands where
/// the composite shows it).
Matrix4 placementViewportWrapMatrix(
  LayerPlacement placement,
  CanvasViewport viewport,
) {
  return viewportTransformMatrix(viewport).multiplied(
    placementMatrix(placement),
  )..multiply(viewportInverseTransformMatrix(viewport));
}
