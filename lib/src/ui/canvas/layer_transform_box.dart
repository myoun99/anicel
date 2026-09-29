import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/transform_track.dart';
import '../input/finger_mode_devices.dart';
import '../theme/app_theme.dart';
import '../../services/layer_pose_paint.dart';
import '../repaint_props.dart';
import '../timeline/memo_token.dart';
import '../widgets/axis_bar_gesture.dart';
import 'canvas_viewport_offset.dart';

/// Which member of the Transform group a box drag drives (R5 #10, the
/// user's rule: "그 관련된 동작을 하면 관련된 멤버가 키찍고 값 바꾸도록").
enum LayerBoxGrab { scale, rotation }

/// The on-canvas transform box: the layer's PICTURE bounds, posed, with a
/// corner handle at each end and a rotate handle above the top edge.
///
/// The picture, not the canvas — the user chose that on the mockup ("레이어
/// 그림의 바운드에 걸리는게 알기쉬울거같기도하고? 그렇게하자"), and it is the
/// rule the selection tool's implicit whole-picture box already follows.
///
/// The box turns and scales about the ANCHOR, because that is what the pose
/// does. So the anchor's screen position — `pose.center`, by construction —
/// is the pivot every measurement below is taken from.
///
/// Only CORNERS scale, and they scale uniformly: a layer pose carries one
/// `zoom`, so there is no non-uniform box to drag. Offering edge handles
/// would be offering a stretch the model cannot represent.
class LayerTransformBox extends StatefulWidget {
  const LayerTransformBox({
    super.key,
    required this.bounds,
    required this.pose,
    required this.anchorPoint,
    required this.canvasSize,
    required this.viewport,
    required this.onScaleChanged,
    required this.onScaleCommitted,
    required this.onRotationChanged,
    required this.onRotationCommitted,
    required this.onCancelled,
  });

  /// The layer's tight ink bounds in ARTWORK coordinates.
  final Rect bounds;

  /// The layer's resolved pose at the playhead — mid-drag, the dragged value
  /// as the host shows it (F-195).
  final TransformPose pose;

  /// The resolved anchor point (artwork coordinates); the pose turns about
  /// it and lands it on [TransformPose.center].
  final CanvasPoint anchorPoint;

  final CanvasSize canvasSize;
  final CanvasViewport viewport;

  /// The dragged zoom (1.0 = 100%), per move and then once on release.
  final ValueChanged<double> onScaleChanged;
  final ValueChanged<double> onScaleCommitted;

  /// The dragged rotation in clockwise degrees, per move and then once on
  /// release.
  final ValueChanged<double> onRotationChanged;
  final ValueChanged<double> onRotationCommitted;

  /// A grab went away without a release — what the per-move callbacks
  /// showed is to be dropped.
  final VoidCallback onCancelled;

  @override
  State<LayerTransformBox> createState() => _LayerTransformBoxState();
}

class _LayerTransformBoxState extends State<LayerTransformBox> {
  /// The grab in flight, or null, and the value it has reached — held as
  /// the FULL value rather than a delta, so the release commits exactly
  /// what the last move showed.
  ///
  /// 🚨F-195: the box does NOT draw it. It drew its live zoom and turn over
  /// a picture that sat still until the release; the host shows the grabbed
  /// value as the canvas shows it and hands it back as [LayerTransformBox.
  /// pose], so the outline and the picture move as one.
  LayerBoxGrab? _grab;
  double? _grabbed;

  /// The value the grab started from, and where the pivot was then with
  /// the pointer's angle / distance from it. Captured once: [LayerTransformBox.
  /// pose] is the grabbed value mid-drag, and measuring against it would
  /// count every move twice.
  double _start = 0;
  Offset _pivot = Offset.zero;
  double _grabAngle = 0;
  double _grabDistance = 1;

  static const double _handleSize = 10;
  static const double _rotateReach = 26;

  /// An artwork point in SCREEN coordinates, through the pose and then the
  /// viewport — the same matrix every composite route uses, so the box
  /// frames what is actually on screen.
  Offset _screen(Offset artwork, TransformPose pose) {
    final matrix = layerPoseMatrix(
      pose,
      widget.canvasSize,
      anchorPoint: widget.anchorPoint,
    ).storage;
    final posed = CanvasPoint(
      x: matrix[0] * artwork.dx + matrix[4] * artwork.dy + matrix[12],
      y: matrix[1] * artwork.dx + matrix[5] * artwork.dy + matrix[13],
    );
    return widget.viewport.canvasToViewportOffset(posed);
  }

  Offset get _pivotScreen =>
      widget.viewport.canvasToViewportOffset(widget.pose.center);

  List<Offset> _corners(TransformPose pose) {
    final b = widget.bounds;
    return [
      _screen(b.topLeft, pose),
      _screen(b.topRight, pose),
      _screen(b.bottomRight, pose),
      _screen(b.bottomLeft, pose),
    ];
  }

  /// The rotate handle's screen position: straight out from the top edge's
  /// midpoint, along the box's own up direction, so it stays "above the
  /// box" however far the box has already turned.
  Offset _rotateHandle(TransformPose pose) {
    final corners = _corners(pose);
    final topMid = (corners[0] + corners[1]) / 2;
    final bottomMid = (corners[3] + corners[2]) / 2;
    final up = topMid - bottomMid;
    final length = up.distance;
    if (length < 0.001) {
      return topMid - const Offset(0, _rotateReach);
    }
    return topMid + up / length * _rotateReach;
  }

  void _beginGrab(LayerBoxGrab grab, Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    final local = box == null ? globalPosition : box.globalToLocal(globalPosition);
    _pivot = _pivotScreen;
    final away = local - _pivot;
    _grabAngle = math.atan2(away.dy, away.dx);
    // Never zero: a grab exactly on the pivot would make every ratio
    // infinite, and the box would jump to nothing on the first move.
    _grabDistance = math.max(away.distance, 0.001);
    _start = switch (grab) {
      LayerBoxGrab.scale => widget.pose.zoom,
      LayerBoxGrab.rotation => widget.pose.rotationDegrees,
    };
    _grab = grab;
    _grabbed = null;
  }

  void _updateGrab(Offset globalPosition) {
    final grab = _grab;
    if (grab == null) {
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    final local = box == null ? globalPosition : box.globalToLocal(globalPosition);
    final away = local - _pivot;
    switch (grab) {
      case LayerBoxGrab.scale:
        // Distance from the pivot scales linearly with zoom, so the
        // ratio IS the zoom change — no need to unproject the corner.
        final ratio = math.max(away.distance, 0.001) / _grabDistance;
        final zoom = math.max(_start * ratio, 0.001);
        _grabbed = zoom;
        widget.onScaleChanged(zoom);
      case LayerBoxGrab.rotation:
        final swept = math.atan2(away.dy, away.dx) - _grabAngle;
        final rotation = _start + swept * 180 / math.pi;
        _grabbed = rotation;
        widget.onRotationChanged(rotation);
    }
  }

  void _endGrab() {
    final grab = _grab;
    final grabbed = _grabbed;
    _grab = null;
    _grabbed = null;
    // ONE member per drag — the one the handle names (R5 #10).
    if (grab == null || grabbed == null || grabbed == _start) {
      widget.onCancelled();
      return;
    }
    switch (grab) {
      case LayerBoxGrab.scale:
        widget.onScaleCommitted(grabbed);
      case LayerBoxGrab.rotation:
        widget.onRotationCommitted(grabbed);
    }
  }

  void _cancelGrab() {
    _grab = null;
    _grabbed = null;
    widget.onCancelled();
  }

  @override
  void dispose() {
    // A box taken away mid-grab never sees its release: what it was showing
    // is dropped once the tree settles — a notifier fired while the tree is
    // being torn down would be too soon.
    if (_grab != null) {
      final cancel = widget.onCancelled;
      WidgetsBinding.instance.addPostFrameCallback((_) => cancel());
    }
    super.dispose();
  }

  Widget _handle({
    required String keyValue,
    required Offset center,
    required LayerBoxGrab grab,
    required MouseCursor cursor,
    required double size,
    required bool round,
  }) {
    return Positioned(
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      width: size,
      height: size,
      // H24: the canvas under this takes the arena on the first movement, so
      // the handle takes it on the first movement too — deeper, so it is
      // asked first ([OwningPanGestureRecognizer]).
      child: FingerModeDevices.tool(
        builder: (context, devices) => RawGestureDetector(
          key: ValueKey<String>(keyValue),
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            OwningPanGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  OwningPanGestureRecognizer
                >(OwningPanGestureRecognizer.new, (recognizer) {
                  // TS9: a finger drives this only while the one-finger
                  // slot draws — stated as devices so the recognizer stays
                  // out of the arena and the flip below can take the touch
                  // ([AppInput.toolPointerDevices]). Every build, not at
                  // construction: a finger's meaning is a setting
                  // ([FingerModeDevices]).
                  recognizer.supportedDevices = devices;
                  recognizer.onStart = (details) =>
                      _beginGrab(grab, details.globalPosition);
                  recognizer.onUpdate = (details) =>
                      _updateGrab(details.globalPosition);
                  recognizer.onEnd = (_) => _endGrab();
                  recognizer.onCancel = _cancelGrab;
                }),
          },
          child: MouseRegion(
            cursor: cursor,
            child: Center(
              child: Container(
                width: size - 3,
                height: size - 3,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: round ? BoxShape.circle : BoxShape.rectangle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pose = widget.pose;
    final corners = _corners(pose);
    final rotate = _rotateHandle(pose);
    return Stack(
      children: [
        // The outline is painted, not laid out: a rotated box is not a
        // rectangle in this Stack's coordinates.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _TransformBoxPainter(
                corners: corners,
                rotateHandle: rotate,
                color: AppColors.accent,
              ),
            ),
          ),
        ),
        for (var index = 0; index < corners.length; index += 1)
          _handle(
            keyValue: 'layer-transform-box-corner-$index',
            center: corners[index],
            grab: LayerBoxGrab.scale,
            cursor: SystemMouseCursors.resizeUpLeftDownRight,
            size: _handleSize + 8,
            round: false,
          ),
        _handle(
          keyValue: 'layer-transform-box-rotate',
          center: rotate,
          grab: LayerBoxGrab.rotation,
          cursor: SystemMouseCursors.grab,
          size: _handleSize + 8,
          round: true,
        ),
      ],
    );
  }
}

class _TransformBoxPainter extends CustomPainter with RepaintOnProps {
  const _TransformBoxPainter({
    required this.corners,
    required this.rotateHandle,
    required this.color,
  });

  final List<Offset> corners;
  final Offset rotateHandle;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) {
      return;
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withValues(alpha: 0.85);
    canvas.drawPath(
      Path()
        ..moveTo(corners[0].dx, corners[0].dy)
        ..lineTo(corners[1].dx, corners[1].dy)
        ..lineTo(corners[2].dx, corners[2].dy)
        ..lineTo(corners[3].dx, corners[3].dy)
        ..close(),
      stroke,
    );
    // The stem to the rotate handle, so the circle reads as belonging to
    // the box rather than floating beside it.
    canvas.drawLine((corners[0] + corners[1]) / 2, rotateHandle, stroke);
  }

  @override
  Object get props => (color, rotateHandle, ByList(corners));
}
