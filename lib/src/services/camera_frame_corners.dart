import 'dart:ui' show Offset, Rect;

import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../core/point_bounds.dart';
import '../models/camera_pose.dart';
import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import 'camera_projection_matrix.dart';

/// The camera frame's corners in canvas coordinates:
/// top-left, top-right, bottom-right, bottom-left.
///
/// The output frame's four corners pulled BACK through the one camera
/// projection ([cameraProjectionMatrix] inverted — the closure
/// guidesInArtworkSpace uses for the layer pose), so the overlay's frame is
/// exactly the region the export renderer and the playback painter show.
List<Offset> cameraFrameCornersInCanvas({
  required CameraPose pose,
  required CanvasSize cameraFrameSize,
}) {
  final inverse = cameraProjectionMatrix(pose, cameraFrameSize)..invert();
  final width = cameraFrameSize.width.toDouble();
  final height = cameraFrameSize.height.toDouble();
  Offset corner(double x, double y) {
    final mapped = inverse.transform3(Vector3(x, y, 0));
    return Offset(mapped.x, mapped.y);
  }

  return [
    corner(0, 0),
    corner(width, 0),
    corner(width, height),
    corner(0, height),
  ];
}

/// The camera's frame at each of its [keys] from frame [from] up to
/// [toExclusive], in frame order — its four corners on the canvas
/// ([cameraFrameCornersInCanvas]). What a camera's path is drawn from.
List<({int frameIndex, List<Offset> corners})> cameraKeyFrames(
  Map<int, CameraPose> keys,
  CanvasSize cameraFrameSize, {
  int from = 0,
  int? toExclusive,
}) {
  final frames = [
    for (final key in keys.entries)
      if (key.key >= from && (toExclusive == null || key.key < toExclusive))
        key,
  ]..sort((a, b) => a.key.compareTo(b.key));
  return [
    for (final key in frames)
      (
        frameIndex: key.key,
        corners: cameraFrameCornersInCanvas(
          pose: key.value,
          cameraFrameSize: cameraFrameSize,
        ),
      ),
  ];
}

/// The trail each corner of the camera's frame draws across [frames], from
/// the first to the last — four polylines, top-left first.
///
/// How a camera's travel reads (유저 2026-09-30, after Storyboard Pro:
/// 「키마다 궤도? 를 그려둬서 어떻게 진행되는지 알게해줘. 그냥 단순하게
/// 선으로」 · 「궤도는 중앙이아니라 각 꼭짓점 4개 전부야」): a simple line
/// per corner, key to key — one through the centre shows no turn and no
/// push-in.
List<List<Offset>> cameraCornerTrails(List<List<Offset>> frames) => [
  for (var corner = 0; corner < 4; corner += 1)
    [for (final frame in frames) frame[corner]],
];

/// The canvas region [frames] cover together — the bounds of every corner
/// of every one ([pointsBounds]).
Rect cameraFramesBounds(Iterable<List<Offset>> frames) =>
    pointsBounds([for (final frame in frames) ...frame]);

/// What a render looks through: a camera [pose] over a frame of
/// [frameSize] canvas pixels at zoom 1 — the camera's own, or one standing
/// over a region of the canvas ([cameraViewOver]).
typedef CameraView = ({CameraPose pose, CanvasSize frameSize});

/// A camera that shows exactly [region] of the canvas: square to it over
/// its centre, its frame the region's size. [region] is in whole canvas
/// pixels — a render has no half pixels to give.
CameraView cameraViewOver(Rect region) => (
  pose: CameraPose(
    center: CanvasPoint(x: region.center.dx, y: region.center.dy),
  ),
  frameSize: CanvasSize(
    width: region.width.round(),
    height: region.height.round(),
  ),
);

/// What a panel's picture shows: the canvas [region] its cell's moving
/// camera sweeps, square to it ([cameraViewOver]) — else [camera], the
/// camera at the picture's frame. The picture is rendered through it and
/// the pen draws through it, so the two cannot see different canvases.
CameraView pictureView(CameraView camera, Rect? region) =>
    region == null ? camera : cameraViewOver(region);
