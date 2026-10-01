import 'package:flutter/material.dart';

import '../../core/point_bounds.dart';
import '../theme/app_theme.dart' show AppColors;
import '../../models/camera_pose.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/transform_track.dart' show TransformPose;
import '../../services/camera_frame_corners.dart'
    show cameraFrameCornersInCanvas;
import '../repaint_props.dart';
import '../canvas/canvas_viewport_offset.dart';
import '../canvas/row_transform_box.dart';

/// The camera pose's center in viewport (screen) coordinates.
Offset cameraCenterInViewport({
  required CameraPose pose,
  required CanvasViewport viewport,
}) {
  return viewport.canvasToViewportOffset(pose.center);
}

/// The axis-aligned canvas-space bounds of the (possibly rotated) camera
/// frame — what the Fit button frames while the camera layer is active.
Rect cameraFrameBoundsInCanvas({
  required CameraPose pose,
  required CanvasSize cameraFrameSize,
}) {
  return pointsBounds(
    cameraFrameCornersInCanvas(pose: pose, cameraFrameSize: cameraFrameSize),
  );
}

/// The camera frame's corners in viewport (screen) coordinates:
/// top-left, top-right, bottom-right, bottom-left.
List<Offset> cameraFrameCornersInViewport({
  required CameraPose pose,
  required CanvasSize cameraFrameSize,
  required CanvasViewport viewport,
}) {
  Offset toViewport(Offset corner) => viewport.canvasToViewportOffset(
    CanvasPoint(x: corner.dx, y: corner.dy),
  );

  return [
    for (final corner in cameraFrameCornersInCanvas(
      pose: pose,
      cameraFrameSize: cameraFrameSize,
    ))
      toViewport(corner),
  ];
}

/// The TVPaint-style camera view drawn over the canvas: everything outside
/// the camera frame is dimmed and the frame silhouette gets an outline.
///
/// It only DRAWS. On the camera row the frame is grabbed through the box
/// every row's transform wears (F-222 ③, `RowTransformBox`): the inside
/// moves the camera, a corner zooms it and outside on stage turns it, each
/// about its centre. ↩️The frame used to take the hand itself — a corner
/// for the zoom, a lever knob above the top edge for the turn, anywhere
/// else for the move — and the lever went with the transform tool's (유저
/// 2026-09-22 「회전 꼭짓점은 잔재 싹 삭제」), when every box became one law.
///
/// 🚨F-195: the frame does NOT draw a drag of its own. The host shows the
/// dragged pose as the camera track the display reads, and hands it back
/// as [pose].
class CameraFrameOverlay extends StatelessWidget {
  const CameraFrameOverlay({
    super.key,
    required this.pose,
    required this.cameraFrameSize,
    required this.viewport,
    required this.dimOpacity,
  });

  /// The app's accent, like every other thing on screen that says "this is
  /// the one you are working on" (user, 2026-08-08). It was a hardcoded
  /// cyan — the one piece of chrome with a colour of its own, and it went
  /// on being cyan when the user changed the accent.
  ///
  /// LIVE, not const: the accent is a setting ([AppColors.accent]).
  static Color get outlineColor => AppColors.accent;

  /// The frame's stroke. A HAIRLINE: this outline sits over artwork all day
  /// and its job is to say where the frame is, not to be seen (user:
  /// '더 얇고 세련되게, 최대한 심플하게').
  static const double outlineWidth = 1;

  /// Half the centre cross's arm. Small enough to read as a pivot mark
  /// rather than as a second piece of geometry.
  static const double centerCrossArm = 4;

  static const double minZoom = 0.01;
  static const double maxZoom = 100;

  final CameraPose pose;

  /// The camera's output picture size; the view rect on canvas is this
  /// divided by the pose zoom.
  final CanvasSize cameraFrameSize;

  final CanvasViewport viewport;

  /// 0 = no dim, 1 = fully black outside the camera frame.
  final double dimOpacity;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      key: const ValueKey<String>('camera-frame-overlay'),
      painter: CameraFramePainter(
        pose: pose,
        cameraFrameSize: cameraFrameSize,
        viewport: viewport,
        dimOpacity: dimOpacity,
        outlineColor: CameraFrameOverlay.outlineColor,
      ),
      // A bare CustomPaint sizes to zero under loose constraints; the frame
      // must always cover the whole viewport.
      child: const SizedBox.expand(),
    ),
  );
}

/// The camera row's box (F-222 ③): the frame IS the box — the inside moves
/// the camera, a corner zooms it, outside on stage turns it, each about its
/// centre ([RowTransformBox]). No cross: the camera turns and zooms about
/// its own centre, which nothing places (유저 2026-10-01: 「카메라도 그래서
/// 십자가 못움직이고 중심기준 회전이 맞을거같으니 십자가 필요없으니」).
///
/// [zoom] lands the CAMERA's zoom. The frame's size is the output's over
/// the zoom, so the box's own scale is the zoom's inverse — the corner
/// dragged outward zooms out.
class CameraFrameBox extends StatelessWidget {
  const CameraFrameBox({
    super.key,
    required this.pose,
    required this.cameraFrameSize,
    required this.canvasSize,
    required this.viewport,
    required this.claimsCanvas,
    required this.onCancelled,
    this.move,
    this.zoom,
    this.turn,
  });

  final CameraPose pose;
  final CanvasSize cameraFrameSize;

  /// The cut's canvas — the stage the turn keeps to.
  final CanvasSize canvasSize;
  final CanvasViewport viewport;
  final bool claimsCanvas;
  final VoidCallback onCancelled;
  final RowBoxLanding<CanvasPoint>? move;
  final RowBoxLanding<double>? zoom;
  final RowBoxLanding<double>? turn;

  static double _zoomOf(double frameScale) => (1 / frameScale).clamp(
    CameraFrameOverlay.minZoom,
    CameraFrameOverlay.maxZoom,
  );

  @override
  Widget build(BuildContext context) {
    final zoom = this.zoom;
    return RowTransformBox(
      corners: [
        for (final corner in cameraFrameCornersInCanvas(
          pose: pose,
          cameraFrameSize: cameraFrameSize,
        ))
          CanvasPoint(x: corner.dx, y: corner.dy),
      ],
      pose: TransformPose(
        center: pose.center,
        zoom: 1 / pose.zoom,
        rotationDegrees: pose.rotationDegrees,
      ),
      canvasSize: canvasSize,
      viewport: viewport,
      claimsCanvas: claimsCanvas,
      // The frame's own hairline is the outline ([CameraFrameOverlay]).
      outlined: false,
      onCancelled: onCancelled,
      move: move,
      scale: zoom == null
          ? null
          : (
              changed: (frameScale) => zoom.changed(_zoomOf(frameScale)),
              committed: (frameScale) => zoom.committed(_zoomOf(frameScale)),
            ),
      turn: turn,
    );
  }
}

class CameraFramePainter extends CustomPainter with RepaintOnProps {
  const CameraFramePainter({
    required this.pose,
    required this.cameraFrameSize,
    required this.viewport,
    required this.dimOpacity,
    required this.outlineColor,
  });

  final CameraPose pose;
  final CanvasSize cameraFrameSize;
  final CanvasViewport viewport;
  final double dimOpacity;
  final Color outlineColor;

  /// The camera frame's corners in viewport (screen) coordinates:
  /// top-left, top-right, bottom-right, bottom-left.
  List<Offset> frameCornersInViewport() => cameraFrameCornersInViewport(
    pose: pose,
    cameraFrameSize: cameraFrameSize,
    viewport: viewport,
  );

  @override
  void paint(Canvas canvas, Size size) {
    // CustomPaint does not clip: the frame silhouette must never escape the
    // canvas viewport into neighboring panels.
    canvas.clipRect(Offset.zero & size);
    final corners = frameCornersInViewport();
    final framePath = Path()..addPolygon(corners, true);

    if (dimOpacity > 0) {
      final dimPath = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addPath(framePath, Offset.zero);
      canvas.drawPath(
        dimPath,
        Paint()..color = Colors.black.withValues(alpha: dimOpacity),
      );
    }

    // ONE hairline, and that is the whole silhouette (user, 2026-08-08).
    // It used to be a 2px cyan box — heavy over artwork, and the only
    // chrome in the app wearing a colour of its own.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = CameraFrameOverlay.outlineWidth
      ..color = outlineColor;
    canvas.drawPath(framePath, line);

    // A small cross on the pivot — the second and last mark.
    const arm = CameraFrameOverlay.centerCrossArm;
    final center = cameraCenterInViewport(pose: pose, viewport: viewport);
    canvas.drawLine(
      center - const Offset(arm, 0),
      center + const Offset(arm, 0),
      line,
    );
    canvas.drawLine(
      center - const Offset(0, arm),
      center + const Offset(0, arm),
      line,
    );
  }

  @override
  Object get props =>
      (pose, cameraFrameSize, viewport, dimOpacity, outlineColor);
}
