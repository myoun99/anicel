import '../models/camera_pose.dart';
import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/cut_camera.dart';
import '../models/transform_pose.dart';

/// The camera pose used when a cut has no keyframes: centered on the canvas,
/// zoom 1, no rotation.
CameraPose defaultCameraPoseFor(CanvasSize canvasSize) {
  return CameraPose(
    center: CanvasPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
  );
}

/// Resolves the camera pose at [frameIndex].
///
/// Resolution mechanics (exact keyframe, hold before-first/after-last,
/// linear lerp between) live on the shared TransformTrack; this adds only
/// the camera's empty-track default, [defaultCameraPoseFor].
CameraPose resolveCameraPoseAt({
  required CutCamera camera,
  required CanvasSize canvasSize,
  required int frameIndex,
}) => resolveCameraPoseAtTime(
  camera: camera,
  canvasSize: canvasSize,
  time: frameIndex.toDouble(),
);

/// [resolveCameraPoseAt] at a [time] between frames as well — the camera
/// row's header graph (I-89 ③).
CameraPose resolveCameraPoseAtTime({
  required CutCamera camera,
  required CanvasSize canvasSize,
  required double time,
}) {
  return camera.track
      .resolveAtTime(
        time: time,
        orElse: () => TransformPose.ofCamera(defaultCameraPoseFor(canvasSize)),
      )
      .toCameraPose();
}
