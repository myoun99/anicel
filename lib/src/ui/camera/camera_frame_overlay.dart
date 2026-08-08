import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show DragStartBehavior, PanGestureRecognizer, PointerDeviceKind;
import 'package:flutter/material.dart';

import '../input/app_input_settings.dart' show AppInput;
import '../theme/app_theme.dart' show AppColors;
import '../../models/camera_pose.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';

/// The camera pose's center in viewport (screen) coordinates.
Offset cameraCenterInViewport({
  required CameraPose pose,
  required CanvasViewport viewport,
}) {
  final mapped = viewport.canvasToViewport(pose.center);
  return Offset(mapped.x, mapped.y);
}

/// The camera frame's corners in canvas coordinates:
/// top-left, top-right, bottom-right, bottom-left.
List<Offset> cameraFrameCornersInCanvas({
  required CameraPose pose,
  required CanvasSize cameraFrameSize,
}) {
  final halfWidth = cameraFrameSize.width / pose.zoom / 2;
  final halfHeight = cameraFrameSize.height / pose.zoom / 2;
  final radians = pose.rotationDegrees * math.pi / 180;
  final cos = math.cos(radians);
  final sin = math.sin(radians);

  Offset corner(double dx, double dy) {
    // Clockwise rotation in y-down screen space.
    return Offset(
      pose.center.x + dx * cos - dy * sin,
      pose.center.y + dx * sin + dy * cos,
    );
  }

  return [
    corner(-halfWidth, -halfHeight),
    corner(halfWidth, -halfHeight),
    corner(halfWidth, halfHeight),
    corner(-halfWidth, halfHeight),
  ];
}

/// The axis-aligned canvas-space bounds of the (possibly rotated) camera
/// frame — what the Fit button frames while the camera layer is active.
Rect cameraFrameBoundsInCanvas({
  required CameraPose pose,
  required CanvasSize cameraFrameSize,
}) {
  final corners = cameraFrameCornersInCanvas(
    pose: pose,
    cameraFrameSize: cameraFrameSize,
  );
  var left = corners.first.dx;
  var top = corners.first.dy;
  var right = corners.first.dx;
  var bottom = corners.first.dy;
  for (final corner in corners.skip(1)) {
    left = math.min(left, corner.dx);
    top = math.min(top, corner.dy);
    right = math.max(right, corner.dx);
    bottom = math.max(bottom, corner.dy);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

/// The camera frame's corners in viewport (screen) coordinates:
/// top-left, top-right, bottom-right, bottom-left.
List<Offset> cameraFrameCornersInViewport({
  required CameraPose pose,
  required CanvasSize cameraFrameSize,
  required CanvasViewport viewport,
}) {
  Offset toViewport(Offset corner) {
    final mapped = viewport.canvasToViewport(
      CanvasPoint(x: corner.dx, y: corner.dy),
    );
    return Offset(mapped.x, mapped.y);
  }

  return [
    for (final corner in cameraFrameCornersInCanvas(
      pose: pose,
      cameraFrameSize: cameraFrameSize,
    ))
      toViewport(corner),
  ];
}

/// The rotate lever's knob center in viewport coordinates: it sticks out of
/// the top edge's midpoint, away from the frame center, by
/// [CameraFrameOverlay.rotateLeverLength] screen pixels.
Offset cameraRotateKnobInViewport({
  required CameraPose pose,
  required CanvasSize cameraFrameSize,
  required CanvasViewport viewport,
}) {
  final corners = cameraFrameCornersInViewport(
    pose: pose,
    cameraFrameSize: cameraFrameSize,
    viewport: viewport,
  );
  final center = cameraCenterInViewport(pose: pose, viewport: viewport);
  final topMid = Offset(
    (corners[0].dx + corners[1].dx) / 2,
    (corners[0].dy + corners[1].dy) / 2,
  );
  final direction = topMid - center;
  final distance = direction.distance;
  final unit = distance == 0 ? const Offset(0, -1) : direction / distance;
  return topMid + unit * CameraFrameOverlay.rotateLeverLength;
}

/// The TVPaint-style camera view drawn over the canvas: everything outside
/// the camera frame is dimmed and the frame silhouette gets a blue outline.
///
/// When [interactive] (the camera layer is active) the frame shows its
/// manipulation handles: dragging a corner square scales the zoom around the
/// camera center, dragging the lever knob above the top edge rotates around
/// the center, and dragging anywhere else moves the camera. Every drag
/// previews live and commits ONE keyframe on release via [onPoseCommitted]
/// (one undo entry per drag). When not interactive the overlay ignores
/// pointers so canvas panning/drawing still works below it.
class CameraFrameOverlay extends StatefulWidget {
  const CameraFrameOverlay({
    super.key,
    required this.pose,
    required this.cameraFrameSize,
    required this.viewport,
    required this.dimOpacity,
    this.interactive = false,
    this.onPoseCommitted,
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

  /// Screen-space pointer slack around a handle before the drag falls back
  /// to moving the camera.
  static const double handleHitRadius = 12;

  /// How far the rotate knob sticks out of the top edge, in screen pixels.
  static const double rotateLeverLength = 24;

  static const double minZoom = 0.01;
  static const double maxZoom = 100;

  final CameraPose pose;

  /// The camera's output picture size; the view rect on canvas is this
  /// divided by the pose zoom.
  final CanvasSize cameraFrameSize;

  final CanvasViewport viewport;

  /// 0 = no dim, 1 = fully black outside the camera frame.
  final double dimOpacity;

  final bool interactive;
  final ValueChanged<CameraPose>? onPoseCommitted;

  @override
  State<CameraFrameOverlay> createState() => _CameraFrameOverlayState();
}

enum _CameraDragMode { move, zoom, rotate }

class _CameraFrameOverlayState extends State<CameraFrameOverlay> {
  CameraPose? _dragPose;
  _CameraDragMode _dragMode = _CameraDragMode.move;
  double _zoomStartDistance = 0;
  double _zoomStartZoom = 1;
  double _lastPointerAngle = 0;

  /// PEN-13: the TOUCH gate. Fingers manipulate the camera ONLY when the
  /// one-finger touch slot is Touch drawing (the camera drag is a pen-
  /// class edit, so it follows the drawing capability) — under a flip/
  /// navigate slot a finger on the camera layer belongs to the screen
  /// gestures alone. Pen/mouse always operate.
  ///
  /// The commitment rule mirrors the brush view (PEN-12 #4): a second
  /// finger landing while the touch drag is still SUB-SLOP converts the
  /// pair to a screen gesture (the camera pose snaps back untouched);
  /// once committed, extra fingers are ignored and the drag lives.
  final Set<int> _touchContacts = <int>{};
  bool _touchDrag = false;
  bool _touchDragAborted = false;
  double _touchDragDistance = 0;

  static const double _touchCommitSlop = 18;

  CameraPose get _displayPose => _dragPose ?? widget.pose;

  Offset get _centerInViewport =>
      cameraCenterInViewport(pose: _displayPose, viewport: widget.viewport);

  double _pointerAngleDegrees(Offset position) {
    final fromCenter = position - _centerInViewport;
    return math.atan2(fromCenter.dy, fromCenter.dx) * 180 / math.pi;
  }

  void _dragStart(DragStartDetails details) {
    if (details.kind == PointerDeviceKind.touch) {
      if (!AppInput.touchDraws || _touchContacts.length > 1) {
        _touchDragAborted = true;
        return;
      }
      _touchDrag = true;
      _touchDragAborted = false;
      _touchDragDistance = 0;
    } else {
      _touchDrag = false;
      _touchDragAborted = false;
    }
    final position = details.localPosition;
    final pose = widget.pose;

    final knob = cameraRotateKnobInViewport(
      pose: pose,
      cameraFrameSize: widget.cameraFrameSize,
      viewport: widget.viewport,
    );
    if ((position - knob).distance <= CameraFrameOverlay.handleHitRadius) {
      _dragMode = _CameraDragMode.rotate;
      _lastPointerAngle = _pointerAngleDegrees(position);
      return;
    }

    final corners = cameraFrameCornersInViewport(
      pose: pose,
      cameraFrameSize: widget.cameraFrameSize,
      viewport: widget.viewport,
    );
    for (final corner in corners) {
      if ((position - corner).distance <= CameraFrameOverlay.handleHitRadius) {
        _dragMode = _CameraDragMode.zoom;
        _zoomStartDistance = math.max(
          (position - _centerInViewport).distance,
          0.001,
        );
        _zoomStartZoom = pose.zoom;
        return;
      }
    }

    _dragMode = _CameraDragMode.move;
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (_touchDragAborted) {
      return;
    }
    if (_touchDrag) {
      _touchDragDistance += details.delta.distance;
    }
    final pose = _displayPose;
    switch (_dragMode) {
      case _CameraDragMode.move:
        final canvasDelta = widget.viewport.viewportDeltaToCanvasDelta(
          dx: details.delta.dx,
          dy: details.delta.dy,
        );
        setState(() {
          _dragPose = pose.copyWith(
            center: CanvasPoint(
              x: pose.center.x + canvasDelta.x,
              y: pose.center.y + canvasDelta.y,
            ),
          );
        });
      case _CameraDragMode.zoom:
        // The corner sits at a distance ∝ 1/zoom from the center, so
        // dragging it outward zooms out and inward zooms in.
        final distance = math.max(
          (details.localPosition - _centerInViewport).distance,
          0.001,
        );
        final zoom = (_zoomStartZoom * _zoomStartDistance / distance).clamp(
          CameraFrameOverlay.minZoom,
          CameraFrameOverlay.maxZoom,
        );
        setState(() => _dragPose = pose.copyWith(zoom: zoom));
      case _CameraDragMode.rotate:
        // Accumulate wrapped angular deltas so the rotation stays continuous
        // across the ±180° seam and supports full extra turns (0 → 360
        // keyframes are meaningful — poses lerp as-is).
        final angle = _pointerAngleDegrees(details.localPosition);
        var delta = angle - _lastPointerAngle;
        while (delta > 180) {
          delta -= 360;
        }
        while (delta < -180) {
          delta += 360;
        }
        _lastPointerAngle = angle;
        // A horizontally flipped VIEW mirrors on-screen angles: the same
        // pointer sweep must still rotate the pose the way the user sees
        // it turn.
        if (widget.viewport.flipHorizontal) {
          delta = -delta;
        }
        setState(() {
          _dragPose = pose.copyWith(
            rotationDegrees: pose.rotationDegrees + delta,
          );
        });
    }
  }

  void _dragEnd() {
    final dragPose = _dragPose;
    final aborted = _touchDragAborted;
    _touchDrag = false;
    _touchDragAborted = false;
    _touchDragDistance = 0;
    setState(() => _dragPose = null);
    if (!aborted && dragPose != null && dragPose != widget.pose) {
      widget.onPoseCommitted?.call(dragPose);
    }
  }

  /// A second finger landing during a SUB-SLOP touch drag: the pair is a
  /// screen gesture — the camera pose snaps back untouched.
  void _handleExtraTouchDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      return;
    }
    _touchContacts.add(event.pointer);
    if (_touchContacts.length >= 2 &&
        _touchDrag &&
        !_touchDragAborted &&
        _touchDragDistance < _touchCommitSlop) {
      _touchDragAborted = true;
      setState(() => _dragPose = null);
    }
  }

  void _handleTouchGone(int pointer) {
    _touchContacts.remove(pointer);
  }

  @override
  Widget build(BuildContext context) {
    final paint = CustomPaint(
      key: const ValueKey<String>('camera-frame-overlay'),
      painter: CameraFramePainter(
        pose: _displayPose,
        cameraFrameSize: widget.cameraFrameSize,
        viewport: widget.viewport,
        dimOpacity: widget.dimOpacity,
        outlineColor: CameraFrameOverlay.outlineColor,
        showHandles: widget.interactive,
      ),
      // A bare CustomPaint sizes to zero under loose constraints; the overlay
      // must always cover (and hit-test across) the whole viewport.
      child: const SizedBox.expand(),
    );

    if (!widget.interactive) {
      return IgnorePointer(child: paint);
    }

    return Listener(
      // PEN-13: raw contact tracking for the touch gate (the pan
      // callbacks alone can't see the finger count).
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleExtraTouchDown,
      onPointerUp: (event) => _handleTouchGone(event.pointer),
      onPointerCancel: (event) => _handleTouchGone(event.pointer),
      child: RawGestureDetector(
        key: const ValueKey<String>('camera-frame-overlay-gesture'),
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          _CameraPanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<_CameraPanGestureRecognizer>(
                () => _CameraPanGestureRecognizer(debugOwner: this),
                (recognizer) {
                  // A LATE touch never joins the pan (the default
                  // latest-pointer strategy would hand the drag to the
                  // idle newcomer, freezing the camera mid-drag) — the
                  // finger that started the drag keeps driving it.
                  recognizer.extraTouchRejected = (event) =>
                      event.kind == PointerDeviceKind.touch &&
                      _touchContacts.isNotEmpty;
                  recognizer.gestureSettings =
                      MediaQuery.maybeGestureSettingsOf(context);
                  // Handles are small: report the true pointer-down
                  // position (not the post-touch-slop accept position) so
                  // corner/knob hit tests don't miss the pressed handle.
                  recognizer.dragStartBehavior = DragStartBehavior.down;
                  recognizer.onStart = _dragStart;
                  recognizer.onUpdate = _dragUpdate;
                  recognizer.onEnd = (_) => _dragEnd();
                  recognizer.onCancel = _dragEnd;
                },
              ),
        },
        child: paint,
      ),
    );
  }
}

class CameraFramePainter extends CustomPainter {
  const CameraFramePainter({
    required this.pose,
    required this.cameraFrameSize,
    required this.viewport,
    required this.dimOpacity,
    required this.outlineColor,
    this.showHandles = false,
  });

  final CameraPose pose;
  final CanvasSize cameraFrameSize;
  final CanvasViewport viewport;
  final double dimOpacity;
  final Color outlineColor;

  /// Corner zoom squares + the rotate lever; drawn only while the camera
  /// layer is being manipulated.
  final bool showHandles;

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

    if (showHandles) {
      // The grips come down with the frame: filled 8px squares and a 2px
      // lever read as a different weight of drawing beside a hairline.
      // OUTLINED squares, so a corner reads as a place to grab rather than
      // as a blob sitting on the artwork.
      for (final corner in corners) {
        canvas.drawRect(
          Rect.fromCenter(center: corner, width: 6, height: 6),
          line,
        );
      }

      final topMid = Offset(
        (corners[0].dx + corners[1].dx) / 2,
        (corners[0].dy + corners[1].dy) / 2,
      );
      final knob = cameraRotateKnobInViewport(
        pose: pose,
        cameraFrameSize: cameraFrameSize,
        viewport: viewport,
      );
      canvas.drawLine(topMid, knob, line);
      // The knob stays FILLED: it is the one handle that is not on a
      // corner, so the frame's own geometry does not point at it.
      canvas.drawCircle(knob, 3.5, Paint()..color = outlineColor);
    }
  }

  @override
  bool shouldRepaint(covariant CameraFramePainter oldDelegate) =>
      oldDelegate.pose != pose ||
      oldDelegate.cameraFrameSize != cameraFrameSize ||
      oldDelegate.viewport != viewport ||
      oldDelegate.dimOpacity != dimOpacity ||
      oldDelegate.outlineColor != outlineColor ||
      oldDelegate.showHandles != showHandles;
}

/// PEN-13: the camera pan that never hands its drag to a late finger —
/// [extraTouchRejected] filters newcomers at the arena door, so the
/// finger that started the drag keeps driving it (committed drags
/// survive palm rests; the overlay's Listener handles the sub-slop
/// abort separately).
class _CameraPanGestureRecognizer extends PanGestureRecognizer {
  _CameraPanGestureRecognizer({super.debugOwner});

  bool Function(PointerDownEvent event)? extraTouchRejected;

  @override
  bool isPointerAllowed(PointerEvent event) {
    if (event is PointerDownEvent &&
        (extraTouchRejected?.call(event) ?? false)) {
      return false;
    }
    return super.isPointerAllowed(event);
  }
}
