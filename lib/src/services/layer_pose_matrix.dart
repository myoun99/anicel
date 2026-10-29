import 'dart:ui' show Offset, Rect, Size;

import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../core/point_bounds.dart';
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

/// Where [pose] lays a picture of [picture]'s size: its own pixels → the
/// canvas. The picture turns and scales about its own centre — the anchor a
/// pose of a picture has (I-68: 「변형도구랑 같은거」).
LayerPlacement picturePlacement(TransformPose pose, CanvasSize picture) =>
    placementOf((pose: pose, anchorPoint: null), picture);

/// The move that takes a picture laid at [from] to where [to] stands it —
/// in the canvas space its cel is drawn in: what a reference fx shows the
/// cels by, at a frame its keys stand the file elsewhere (F-374) and while a
/// value is in flight (I-68). Null when [from] collapsed the picture (a zero
/// scale), which no move brings back.
///
/// The picture's own size cancels out of the move; [picture] only names
/// the space the two poses share.
LayerPlacement? pictureMoved({
  required TransformPose from,
  required TransformPose to,
  required CanvasSize picture,
}) {
  final back = canvasToArtwork(picturePlacement(from, picture));
  return back == null ? null : picturePlacement(to, picture).compose(back);
}

/// [rect]'s four corners where [placement] carries them — top-left,
/// top-right, bottom-right, bottom-left: the order a box wears them.
///
/// ⛔ONE spelling of them. A picture rasterized onto a cel, a reference
/// row's box, a row's ink where the canvas shows it and a photo's box on a
/// sheet (I-97) each listed the four on their own.
List<CanvasPoint> placedCorners(LayerPlacement placement, Rect rect) => [
  for (final corner in [
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ])
    placement.apply(CanvasPoint(x: corner.dx, y: corner.dy)),
];

/// The canvas rect [placement] lays a [picture]-sized picture's pixels over
/// — its four corners' bounds, so a turned picture is covered whole.
Rect placedBounds(LayerPlacement placement, CanvasSize picture) =>
    placedRectBounds(
      placement,
      Offset.zero & Size(picture.width.toDouble(), picture.height.toDouble()),
    );

/// The canvas rect [placement] lays [rect] over — its four corners' bounds
/// ([placedCorners]), so a turned rect is covered whole.
///
/// ⛔ONE spelling of them. A picture laid, a row's ink where the canvas
/// shows it and a raster block taken back into a picture each folded the
/// four on their own.
Rect placedRectBounds(LayerPlacement placement, Rect rect) => pointsBounds([
  for (final corner in placedCorners(placement, rect))
    Offset(corner.x, corner.y),
]);

/// [placement] as the matrix a `Canvas` takes. [rasterScale] restates the
/// same canvas-space placement in a scaled raster (a level of the display's
/// pyramid, say): the raster's pixels are the canvas's times it, so what the
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
/// Null when the placement has COLLAPSED its row — a scale of zero on an
/// axis, the frame a flip passes through ([TransformPose.scaleX]): the row
/// shows nothing, and no point of the canvas is a point of its artwork.
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

/// The space a stroke on a row placed by [placement] is drawn in, for
/// everything a guide measures ([GuideSpace]): the canvas for an unplaced
/// row — and for one whose placement has no way back, since a collapsed
/// layer has no artwork to draw in.
GuideSpace guideSpaceOf(LayerPlacement? placement) {
  if (placement == null) {
    return GuideSpace.canvas;
  }
  final back = canvasToArtwork(placement);
  return back == null
      ? GuideSpace.canvas
      : GuideSpace(toCanvas: placement, toStroke: back);
}

GuideTransform _planeOf(Matrix4 matrix) {
  final m = matrix.storage;
  return GuideTransform(m[0], m[1], m[4], m[5], m[12], m[13]);
}
