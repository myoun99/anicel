import 'dart:ui';

import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../models/camera_pose.dart';
import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/canvas_viewport.dart';
import '../models/drawing_guide.dart';
import '../models/transform_track.dart';
import 'camera_projection_matrix.dart';
import 'guide_geometry.dart';
import 'layer_pose_matrix.dart';
import 'viewport_transform_matrix.dart';

export 'camera_projection_matrix.dart' show cameraProjectionMatrix;
export 'layer_pose_matrix.dart' show LayerPoseSample, layerPoseMatrix;

/// Applies a layer's transform pose to [canvas] before its image draws at
/// the origin — see [layerPoseMatrix] for the mapping.
///
/// EVERY composite route shares this one function — playback composites,
/// camera renders (export/thumbnails) and the editing canvas's layer
/// stack — so a transformed layer looks byte-identical everywhere
/// (three-route parity discipline).
void applyLayerPoseTransform(
  Canvas canvas,
  TransformPose pose,
  CanvasSize canvasSize, {
  CanvasPoint? anchorPoint,
  double rasterScale = 1,
}) {
  canvas.transform(
    layerPoseMatrix(
      pose,
      canvasSize,
      anchorPoint: anchorPoint,
      rasterScale: rasterScale,
    ).storage,
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

/// The composition (outer ∘ inner) of two pose samples as ONE sample
/// anchored on the canvas center. Poses are similarities (translate ·
/// rotate · uniform scale), so the product is exactly representable:
/// zooms multiply, rotations add, and the composed center is wherever the
/// combined map sends the canvas center. Lets the CUT-level pose (the
/// storyboard V-row fx, R9-B) stack over a layer's own pose in the editing
/// canvas's SINGLE draw-through wrap — one Transform, one hit-test inverse.
LayerPoseSample composeLayerPoseSamples(
  LayerPoseSample outer,
  LayerPoseSample inner,
  CanvasSize canvasSize,
) {
  final matrix =
      layerPoseMatrix(
        outer.pose,
        canvasSize,
        anchorPoint: outer.anchorPoint,
      )..multiply(
        layerPoseMatrix(inner.pose, canvasSize, anchorPoint: inner.anchorPoint),
      );
  final s = matrix.storage;
  final cx = canvasSize.width / 2;
  final cy = canvasSize.height / 2;
  return (
    pose: TransformPose(
      center: CanvasPoint(
        x: s[0] * cx + s[4] * cy + s[12],
        y: s[1] * cx + s[5] * cy + s[13],
      ),
      zoom: outer.pose.zoom * inner.pose.zoom,
      rotationDegrees: outer.pose.rotationDegrees + inner.pose.rotationDegrees,
    ),
    anchorPoint: null,
  );
}

/// The SCREEN-space wrap matrix for a widget that already renders artwork
/// under [viewport]: `V · P · V⁻¹` — wrapping the interactive brush view in
/// `Transform(transform: ...)` with this matrix shows the active layer
/// POSED exactly like every composite route, while Flutter's hit testing
/// routes pointers through the inverse, so strokes record in original
/// artwork coordinates (draw-through: drawing on what you see lands where
/// the composite shows it).
Matrix4 layerPoseViewportWrapMatrix(
  TransformPose pose,
  CanvasSize canvasSize,
  CanvasViewport viewport, {
  CanvasPoint? anchorPoint,
}) {
  return viewportTransformMatrix(viewport).multiplied(
    layerPoseMatrix(pose, canvasSize, anchorPoint: anchorPoint),
  )..multiply(viewportInverseTransformMatrix(viewport));
}

/// [guides] moved out of CANVAS space and into the ARTWORK space of a layer
/// posed by [sample].
///
/// The counterpart of [layerPoseViewportWrapMatrix]: that one puts the
/// artwork on screen through the pose, and Flutter's hit testing brings
/// pointers back the other way, so a stroke on a posed layer records in the
/// layer's own coordinates. Guides live in canvas space, so they have to
/// make the same trip or the axis will sit where the pen is not.
///
/// Built from [layerPoseMatrix] rather than from the pose's numbers so
/// there is one piece of pose math in the app, not two that can drift.
/// Returns [guides] unchanged for a null or singular pose — a zero zoom
/// collapses the layer to nothing, and there is no artwork space to speak
/// of then.
CutGuides guidesInArtworkSpace(
  CutGuides guides,
  LayerPoseSample? sample,
  CanvasSize canvasSize,
) {
  if (sample == null || guides.isEmpty) return guides;
  final matrix = layerPoseMatrix(
    sample.pose,
    canvasSize,
    anchorPoint: sample.anchorPoint,
  );
  if (matrix.invert() == 0) return guides;
  final inverse = matrix.storage;
  return mapGuides(
    guides,
    GuideTransform(
      inverse[0],
      inverse[1],
      inverse[4],
      inverse[5],
      inverse[12],
      inverse[13],
    ),
  );
}
