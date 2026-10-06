import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../core/turn_trig.dart';
import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/transform_track.dart';
import 'guide_geometry.dart';

/// ONE row's — or one folder's — own GEOMETRIC transform at a frame: the
/// pose its lanes resolve to (position/scale/rotation) plus the optional
/// anchor point (null = the canvas center, the historical default).
/// Animated opacity rides separately — it multiplies paint alpha, not
/// geometry.
///
/// ⛔Not where a row LIES on the canvas: that is this under every folder
/// above it, which is a [LayerPlacement].
typedef LayerPoseSample = ({TransformPose pose, CanvasPoint? anchorPoint});

/// WHERE A ROW'S ARTWORK LIES ON THE CANVAS at one frame — its own pose
/// under the pose of every folder above it — as ONE plane affine, artwork →
/// canvas. Where one is optional, null is the unplaced row: the identity,
/// and the overwhelmingly common case.
///
/// 🗣️F-256-Q1 (유저 2026-10-06): 「가른다 — AE 처럼 Scale X · Y」. ↩️It was a
/// pose ([LayerPoseSample]): the folder chain was folded into 「one pose」
/// by multiplying zooms and adding turns, which is exact while every pose
/// is a similarity and has nothing to say once a scale is an axis's — a
/// folder stretched along one axis over a row that is turned SHEARS the
/// row, and no centre · scale · scale · turn is a shear. An affine is closed
/// under the product, so the fold is the product and nothing downstream has
/// to know how many folders there were.
///
/// ⛔Not the pose's numbers: nobody asks a placement for 「its scale」 or
/// 「its turn」 — it has neither. What is edited is a row's OWN pose, in its
/// parent's placement.
typedef LayerPlacement = GuideTransform;

/// Artwork space → posed canvas space: the artwork's ANCHOR POINT (canvas
/// center unless the anchor-point lane keys one) lands on `pose.center`,
/// scaled along its own axes by `pose.scaleX` · `pose.scaleY` and rotated
/// clockwise by `pose.rotationDegrees` about that point (scale first, then
/// the turn — AE's order). The identity pose maps to the identity matrix
/// by construction, and a quarter turn is exact ([turnSin] — the table the
/// transform box turns by).
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
}) {
  final anchorX = anchorPoint?.x ?? canvasSize.width / 2;
  final anchorY = anchorPoint?.y ?? canvasSize.height / 2;
  final cos = turnCos(pose.rotationDegrees);
  final sin = turnSin(pose.rotationDegrees);
  final turn = Matrix4.identity()
    ..setEntry(0, 0, cos)
    ..setEntry(1, 0, sin)
    ..setEntry(0, 1, -sin)
    ..setEntry(1, 1, cos);
  return Matrix4.translationValues(pose.center.x, pose.center.y, 0)
      .multiplied(turn)
    ..multiply(Matrix4.diagonal3Values(pose.scaleX, pose.scaleY, 1))
    ..multiply(Matrix4.translationValues(-anchorX, -anchorY, 0));
}

/// [sample] as the placement it is on its own — [layerPoseMatrix]'s plane
/// part. A row under no posed folder lies exactly here.
LayerPlacement placementOf(LayerPoseSample sample, CanvasSize canvasSize) =>
    _planeOf(
      layerPoseMatrix(
        sample.pose,
        canvasSize,
        anchorPoint: sample.anchorPoint,
      ),
    );

/// [placement] as the matrix a `Canvas` takes. [rasterScale] restates the
/// same canvas-space placement in a scaled raster (the playback quality
/// tiers): the raster's pixels are the canvas's times it, so what the
/// placement does to a direction stays and where it sends the origin
/// scales.
Matrix4 placementMatrix(LayerPlacement placement, {double rasterScale = 1}) =>
    Matrix4.identity()
      ..setEntry(0, 0, placement.a)
      ..setEntry(1, 0, placement.b)
      ..setEntry(0, 1, placement.c)
      ..setEntry(1, 1, placement.d)
      ..setEntry(0, 3, placement.tx * rasterScale)
      ..setEntry(1, 3, placement.ty * rasterScale);

/// CANVAS space → a placed row's ARTWORK space: [placement] run backwards.
/// Null when the placement is singular — a zero scale collapses the layer,
/// and [TransformPose] refuses one on either axis, so that is a backstop
/// rather than a path.
///
/// ⛔ONE INVERSE. The eyedropper's pick (R28 #7), a region restated in a
/// posed layer's pixels, the guides the pen draws against and the fill's
/// raster (I-36) each inverted the pose on their own; they ask this.
GuideTransform? canvasToArtwork(LayerPlacement placement) {
  final matrix = placementMatrix(placement);
  if (matrix.invert() == 0) {
    return null;
  }
  return _planeOf(matrix);
}

GuideTransform _planeOf(Matrix4 matrix) {
  final m = matrix.storage;
  return GuideTransform(m[0], m[1], m[4], m[5], m[12], m[13]);
}
