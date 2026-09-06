import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../models/camera_pose.dart';
import '../models/canvas_size.dart';

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
