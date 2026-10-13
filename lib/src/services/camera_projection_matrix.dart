import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../models/camera_pose.dart';
import '../models/canvas_size.dart';
import 'layer_pose_matrix.dart' show LayerPlacement;

/// Canvas space → the camera's OUTPUT space: output center = pose center,
/// one output pixel covers `1 / (pose.zoom · outputSize/cameraFrameSize)`
/// canvas pixels.
///
/// The camera is rotated clockwise over the canvas, so the world appears
/// rotated the opposite way through it.
///
/// ONE piece of camera math in the app, not two that can drift (the
/// layerPoseMatrix precedent): the export renderer and the playback
/// painter each concatenated these four steps by hand, and the overlay's
/// frame corners carried a third cos/sin of their own (the audit's clone
/// scan, 2026-09-06). [outputSize] is the preview/export raster size; null
/// renders at the camera frame's own size (scale 1).
Matrix4 cameraProjectionMatrix(
  CameraPose pose,
  CanvasSize cameraFrameSize, {
  CanvasSize? outputSize,
}) {
  final output = outputSize ?? cameraFrameSize;
  final previewScale = output.width / cameraFrameSize.width;
  final scale = previewScale * pose.zoom;
  return Matrix4.translationValues(output.width / 2, output.height / 2, 0)
    ..multiply(Matrix4.diagonal3Values(scale, scale, 1))
    ..multiply(Matrix4.rotationZ(-pose.rotationDegrees * math.pi / 180))
    ..multiply(Matrix4.translationValues(-pose.center.x, -pose.center.y, 0));
}

/// Whether [cameraProjectionMatrix] moves every canvas pixel onto an output
/// pixel whole — a translation by whole pixels, and nothing else — so a
/// render through it lays an image down texel for texel.
bool cameraMovesPixelsWhole(
  CameraPose pose,
  CanvasSize cameraFrameSize, {
  CanvasSize? outputSize,
}) {
  final m = cameraProjectionMatrix(
    pose,
    cameraFrameSize,
    outputSize: outputSize,
  ).storage;
  bool whole(double value) => value == value.roundToDouble();
  return m[0] == 1 &&
      m[1] == 0 &&
      m[4] == 0 &&
      m[5] == 1 &&
      whole(m[12]) &&
      whole(m[13]);
}

/// The camera's SHOT → canvas: where a point of the frame the camera shows
/// lies on the canvas — [cameraProjectionMatrix] run backwards, as the
/// placement a row's artwork takes ([LayerPlacement]).
///
/// 🗣️I-67-Q1 (유저 2026-10-10: 「이름표를 카메라 화면 기준으로 읽는다」): what
/// stands in the shot rather than on the canvas — an SE row's name tag —
/// is drawn through it, so the camera's moves, zoom and turn leave it
/// where it stands on screen.
LayerPlacement shotPlacement(CameraPose pose, CanvasSize cameraFrameSize) {
  final back = cameraProjectionMatrix(pose, cameraFrameSize)..invert();
  return LayerPlacement(
    back.entry(0, 0),
    back.entry(1, 0),
    back.entry(0, 1),
    back.entry(1, 1),
    back.entry(0, 3),
    back.entry(1, 3),
  );
}
