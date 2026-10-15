import 'package:flutter/foundation.dart' show immutable;

import '../../models/camera_pose.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cut.dart';
import '../../models/playback_quality.dart';
import '../../services/camera_projection_matrix.dart';
import '../../services/viewport_transform_matrix.dart';
import 'canvas_layer_stack_view.dart' show rowQualityThrough;

/// The camera a run is seen through on the canvas: its pose at each frame
/// of a cut, and the frame it projects into.
typedef CanvasCamera = ({
  CameraPose Function(Cut cut, int frameIndex) poseOf,
  CanvasSize frameSize,
});

/// How the editing canvas shows a cut's frame, as far as what the frame is
/// made of goes: the view its rows are drawn through, and so the level
/// their images are asked at ([rowQualityThrough]) — the panel's view, with
/// the camera's projection at that frame under it while a run plays on the
/// canvas through the camera (playback-plays-the-screen-material).
///
/// One answer for the two that ask: the canvas draws a frame through
/// [frameViewThrough], and the warmer makes that frame's rows at
/// [qualityAt], which reads the same view. ↩️The canvas used to say the one
/// level it drew at (`RenderCaches.canvasQuality`) — one level for every
/// frame, which a camera zooming across a level's edge in the middle of a
/// cut does not have.
///
/// 🚨THE PAN IS DROPPED ([CanvasLook.new]). A level is read off a view's
/// scale, which a pan never enters — not even through the camera's matrix,
/// whose turn and scale take nothing from the translation, to the bit — and
/// every look that differs starts the warmer over: a pan during a run would
/// have started it over on every move.
@immutable
class CanvasLook {
  CanvasLook({
    required CanvasViewport view,
    required this.devicePixelRatio,
    this.camera,
  }) : view = view.copyWith(panX: 0, panY: 0);

  /// The panel's view, its pan dropped.
  final CanvasViewport view;

  /// The ratio the canvas composes at ([EffectiveDevicePixelRatio]).
  final double devicePixelRatio;

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

  /// The level [cut]'s frame [frameIndex] is drawn at: what the warmer
  /// makes its rows at, and what the canvas asks them at when it gets there.
  PlaybackQuality qualityAt(Cut cut, int frameIndex) => rowQualityThrough(
    frameViewThrough(view, cut, frameIndex),
    devicePixelRatio,
  );

  @override
  bool operator ==(Object other) =>
      other is CanvasLook &&
      other.view == view &&
      other.devicePixelRatio == devicePixelRatio &&
      other.camera?.frameSize == camera?.frameSize &&
      other.camera?.poseOf == camera?.poseOf;

  @override
  int get hashCode =>
      Object.hash(view, devicePixelRatio, camera?.frameSize, camera?.poseOf);
}
