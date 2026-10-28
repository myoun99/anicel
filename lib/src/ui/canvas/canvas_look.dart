import '../../models/camera_pose.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cut.dart';
import '../../services/camera_projection_matrix.dart';
import '../../services/viewport_transform_matrix.dart';

/// The camera a run is seen through on the canvas: its pose at each frame
/// of a cut, and the frame it projects into.
typedef CanvasCamera = ({
  CameraPose Function(Cut cut, int frameIndex) poseOf,
  CanvasSize frameSize,
});

/// How the editing canvas shows a cut's frame: through the panel's view,
/// with the camera's projection at that frame under it while a run plays on
/// the canvas through the camera (playback-plays-the-screen-material).
///
/// ↩️It said as well the level a frame's rows were drawn at, which the
/// warmer made them at (`qualityAt`, told the session as
/// `RenderCaches.canvasLook`) — until a frame became one picture, made at
/// the canvas's resolution whatever it is seen through
/// (one-picture-per-frame, D7-2-Q2 「항상 원본 한장으로」).
class CanvasLook {
  const CanvasLook({this.camera});

  /// The camera a run playing on the canvas is seen through — null while
  /// the canvas stands, is scrubbed, or plays without the camera view.
  final CanvasCamera? camera;

  /// The view [cut]'s frame [frameIndex] is drawn through on a canvas the
  /// panel shows through [panelView]: [panelView] itself, or the camera's
  /// projection at that frame under it.
  CanvasViewport frameViewThrough(
    CanvasViewport panelView,
    Cut cut,
    int frameIndex,
  ) => switch (camera) {
    null => panelView,
    final camera => viewportAfter(
      panelView,
      cameraProjectionMatrix(camera.poseOf(cut, frameIndex), camera.frameSize),
    ),
  };
}
