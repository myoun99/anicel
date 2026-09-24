import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/transform_track.dart';
import 'guide_geometry.dart';

/// A layer's resolved GEOMETRIC transform at one frame: the shared pose
/// (position/scale/rotation) plus the optional anchor point (null = the
/// canvas center, the historical default). Animated opacity rides
/// separately — it multiplies paint alpha, not geometry.
typedef LayerPoseSample = ({TransformPose pose, CanvasPoint? anchorPoint});

/// Artwork space → posed canvas space: the artwork's ANCHOR POINT (canvas
/// center unless the anchor-point lane keys one) lands on `pose.center`,
/// scaled by `pose.zoom` and rotated clockwise by `pose.rotationDegrees`
/// about that point. The identity pose maps to the identity matrix by
/// construction. [rasterScale] adapts the same canvas-space pose to a
/// scaled raster (playback quality tiers).
///
/// 🚨It lives in SERVICES rather than beside the painter that applies it,
/// because the pose is not a drawing question: a colour replace has to
/// restate a canvas-space region in a posed layer's own pixels, and
/// `services` may not import `ui` (the CI-enforced dependency direction).
/// The painter next door still owns everything that needs a `Canvas`.
Matrix4 layerPoseMatrix(
  TransformPose pose,
  CanvasSize canvasSize, {
  CanvasPoint? anchorPoint,
  double rasterScale = 1,
}) {
  final anchorX = (anchorPoint?.x ?? canvasSize.width / 2) * rasterScale;
  final anchorY = (anchorPoint?.y ?? canvasSize.height / 2) * rasterScale;
  return Matrix4.translationValues(
      pose.center.x * rasterScale,
      pose.center.y * rasterScale,
      0,
    ).multiplied(Matrix4.rotationZ(pose.rotationDegrees * math.pi / 180))
    ..multiply(Matrix4.diagonal3Values(pose.zoom, pose.zoom, 1))
    ..multiply(Matrix4.translationValues(-anchorX, -anchorY, 0));
}

/// A posed layer's ARTWORK space → CANVAS space: [layerPoseMatrix]'s plane
/// part, as the affine a point-mapping caller wants.
GuideTransform artworkToCanvas(LayerPoseSample sample, CanvasSize canvasSize) =>
    _planeOf(
      layerPoseMatrix(
        sample.pose,
        canvasSize,
        anchorPoint: sample.anchorPoint,
      ),
    );

/// CANVAS space → a posed layer's ARTWORK space: the inverse of
/// [artworkToCanvas]. Null when the pose is singular — a zero zoom collapses
/// the layer, and [TransformPose] refuses one, so that is a backstop rather
/// than a path.
///
/// ⛔ONE INVERSE. The eyedropper's pick (R28 #7), a region restated in a
/// posed layer's pixels, the guides the pen draws against and the fill's
/// raster (I-36) each inverted the pose on their own; they ask this.
GuideTransform? canvasToArtwork(
  LayerPoseSample sample,
  CanvasSize canvasSize,
) {
  final matrix = layerPoseMatrix(
    sample.pose,
    canvasSize,
    anchorPoint: sample.anchorPoint,
  );
  if (matrix.invert() == 0) {
    return null;
  }
  return _planeOf(matrix);
}

GuideTransform _planeOf(Matrix4 matrix) {
  final m = matrix.storage;
  return GuideTransform(m[0], m[1], m[4], m[5], m[12], m[13]);
}
