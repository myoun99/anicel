import 'package:flutter/material.dart';

import '../../models/canvas_point.dart';
import '../../models/canvas_viewport.dart';
import '../../models/transform_track.dart';
import '../input/app_input_settings.dart';
import '../theme/app_theme.dart';

/// The on-canvas Position drag gizmo: a crosshair handle at the active
/// layer's posed center. Dragging it moves the layer's Position — the
/// handle ghosts along during the drag and the release commits ONE key at
/// the playhead (AE semantics, one undo). Shown only while the layer's
/// Transform lanes are twirled open, so the handle never sits in the way
/// of ordinary drawing.
class LayerPositionGizmo extends StatefulWidget {
  const LayerPositionGizmo({
    super.key,
    required this.pose,
    required this.viewport,
    required this.onPositionCommitted,
  });

  /// The layer's resolved pose at the playhead (identity pose while the
  /// track is empty — dragging then creates the first Position key).
  final TransformPose pose;

  final CanvasViewport viewport;

  /// The dragged Position in canvas coordinates, fired once on release.
  final ValueChanged<CanvasPoint> onPositionCommitted;

  @override
  State<LayerPositionGizmo> createState() => _LayerPositionGizmoState();
}

class _LayerPositionGizmoState extends State<LayerPositionGizmo> {
  Offset _dragDelta = Offset.zero;
  bool _dragging = false;

  static const double _handleSize = 22;

  Offset get _screenCenter {
    final mapped = widget.viewport.canvasToViewport(widget.pose.center);
    return Offset(mapped.x, mapped.y);
  }

  void _endDrag() {
    final canvasDelta = widget.viewport.viewportDeltaToCanvasDelta(
      dx: _dragDelta.dx,
      dy: _dragDelta.dy,
    );
    final committed = CanvasPoint(
      x: widget.pose.center.x + canvasDelta.x,
      y: widget.pose.center.y + canvasDelta.y,
    );
    final moved = _dragDelta != Offset.zero;
    setState(() {
      _dragging = false;
      _dragDelta = Offset.zero;
    });
    if (moved) {
      widget.onPositionCommitted(committed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = _screenCenter + _dragDelta;
    return Stack(
      children: [
        Positioned(
          left: center.dx - _handleSize / 2,
          top: center.dy - _handleSize / 2,
          width: _handleSize,
          height: _handleSize,
          child: GestureDetector(
            key: const ValueKey<String>('layer-position-gizmo'),
            behavior: HitTestBehavior.opaque,
            // TS9's law, at the door a GestureDetector has: a finger only
            // moves this while the one-finger slot says draw. Stated as
            // supported DEVICES rather than checked in the handler, because
            // by `onPanStart` the recognizer has already won the arena and
            // returning would leave the gizmo dead and the flip undone.
            supportedDevices: AppInput.toolPointerDevices,
            onPanStart: (_) => setState(() => _dragging = true),
            onPanUpdate: (details) =>
                setState(() => _dragDelta += details.delta),
            onPanEnd: (_) => _endDrag(),
            onPanCancel: () => setState(() {
              _dragging = false;
              _dragDelta = Offset.zero;
            }),
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: CustomPaint(
                painter: _GizmoHandlePainter(
                  color: AppColors.accent,
                  active: _dragging,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The on-canvas ANCHOR POINT gizmo (R5 #10): AE's anchor glyph at the
/// layer's resolved anchor, dragged to place the point scale and rotation
/// turn about. Shown only while the standing lane declares
/// [CanvasManipulator.anchorPoint].
///
/// It does NOT compensate Position. The user's rule for #10 is that the
/// member you touch is the member that keys, and compensating would key
/// Position too; without it, dragging the anchor moves the artwork exactly
/// as scrubbing the Anchor Point value in the timeline does — the same
/// property, the same effect, reached two ways.
class LayerAnchorGizmo extends StatefulWidget {
  const LayerAnchorGizmo({
    super.key,
    required this.anchorPoint,
    required this.viewport,
    required this.onAnchorCommitted,
  });

  /// The layer's resolved anchor at the playhead (the canvas centre while
  /// the lane is unkeyed — dragging then creates the first key).
  final CanvasPoint anchorPoint;

  final CanvasViewport viewport;

  /// The dragged anchor in canvas coordinates, fired once on release.
  final ValueChanged<CanvasPoint> onAnchorCommitted;

  @override
  State<LayerAnchorGizmo> createState() => _LayerAnchorGizmoState();
}

class _LayerAnchorGizmoState extends State<LayerAnchorGizmo> {
  Offset _dragDelta = Offset.zero;
  bool _dragging = false;

  static const double _handleSize = 24;

  Offset get _screenAnchor {
    final mapped = widget.viewport.canvasToViewport(widget.anchorPoint);
    return Offset(mapped.x, mapped.y);
  }

  void _endDrag() {
    final canvasDelta = widget.viewport.viewportDeltaToCanvasDelta(
      dx: _dragDelta.dx,
      dy: _dragDelta.dy,
    );
    final committed = CanvasPoint(
      x: widget.anchorPoint.x + canvasDelta.x,
      y: widget.anchorPoint.y + canvasDelta.y,
    );
    final moved = _dragDelta != Offset.zero;
    setState(() {
      _dragging = false;
      _dragDelta = Offset.zero;
    });
    if (moved) {
      widget.onAnchorCommitted(committed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = _screenAnchor + _dragDelta;
    return Stack(
      children: [
        Positioned(
          left: center.dx - _handleSize / 2,
          top: center.dy - _handleSize / 2,
          width: _handleSize,
          height: _handleSize,
          child: GestureDetector(
            key: const ValueKey<String>('layer-anchor-gizmo'),
            behavior: HitTestBehavior.opaque,
            supportedDevices: AppInput.toolPointerDevices,
            onPanStart: (_) => setState(() => _dragging = true),
            onPanUpdate: (details) =>
                setState(() => _dragDelta += details.delta),
            onPanEnd: (_) => _endDrag(),
            onPanCancel: () => setState(() {
              _dragging = false;
              _dragDelta = Offset.zero;
            }),
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: CustomPaint(
                painter: _AnchorHandlePainter(
                  color: AppColors.accent,
                  active: _dragging,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// AE's anchor glyph: a small circle with the four quadrant ticks reaching
/// THROUGH it, so it reads as a pivot rather than a move handle (which is
/// what the position crosshair beside it means).
class _AnchorHandlePainter extends CustomPainter {
  const _AnchorHandlePainter({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = active ? 2 : 1.5
      ..color = color;
    final radius = size.width / 4;
    canvas.drawCircle(center, radius, stroke);
    for (final direction in const [
      Offset(1, 0),
      Offset(-1, 0),
      Offset(0, 1),
      Offset(0, -1),
    ]) {
      canvas.drawLine(
        center + direction * radius,
        center + direction * (size.width / 2 - 1),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnchorHandlePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.active != active;
}

class _GizmoHandlePainter extends CustomPainter {
  const _GizmoHandlePainter({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = active ? 2 : 1.5
      ..color = color;
    canvas.drawCircle(center, size.width / 2 - 2, stroke);
    // Crosshair ticks (AE-style move handle).
    for (final direction in const [
      Offset(1, 0),
      Offset(-1, 0),
      Offset(0, 1),
      Offset(0, -1),
    ]) {
      canvas.drawLine(
        center + direction * (size.width / 2 - 6),
        center + direction * (size.width / 2 - 1),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GizmoHandlePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.active != active;
}
