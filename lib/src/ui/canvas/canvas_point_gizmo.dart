import 'package:flutter/material.dart';

import '../../models/canvas_point.dart';
import '../../models/canvas_viewport.dart';
import '../input/finger_mode_devices.dart';
import '../theme/app_theme.dart';
import '../widgets/axis_bar_gesture.dart';
import 'canvas_viewport_offset.dart';

/// Which glyph a [CanvasPointGizmo] wears, and the radii that draw it.
///
/// The two handles are one drawing with two sets of radii — the numbers are
/// the formulas the two painters used to evaluate against their own fixed
/// box (`size.width` is pinned to [handleSize] by the Positioned that lays
/// the handle out), so a glyph is a row in this table rather than a class.
enum HandleGlyph {
  /// AE-style move handle: the ticks sit OUTSIDE the circle.
  crosshair(
    key: 'layer-position-gizmo',
    handleSize: 22,
    circleRadius: 9,
    tickInner: 5,
    tickOuter: 10,
  ),

  /// AE's anchor glyph: a small circle with the four quadrant ticks reaching
  /// THROUGH it, so it reads as a pivot rather than a move handle (which is
  /// what the position crosshair beside it means).
  anchor(
    key: 'layer-anchor-gizmo',
    handleSize: 24,
    circleRadius: 6,
    tickInner: 6,
    tickOuter: 11,
  );

  const HandleGlyph({
    required this.key,
    required this.handleSize,
    required this.circleRadius,
    required this.tickInner,
    required this.tickOuter,
  });

  /// The handle's widget key — what a test and the canvas both find it by.
  final String key;

  final double handleSize;
  final double circleRadius;

  /// Where each of the four ticks starts and ends, measured from the centre.
  final double tickInner;
  final double tickOuter;
}

/// The on-canvas point-drag gizmo: a handle at a point in canvas space whose
/// drag reports the dragged point per move ([onChanged]) and ONCE on
/// release ([onCommitted]), the screen delta mapped back through the
/// viewport.
///
/// 🚨F-195 (유저 2026-09-27 「캔버스에서 편집이든 … 실시간으로 화면에
/// 보이도록」): the handle does NOT draw its own drag. It used to ghost along
/// on an offset of its own while the picture it moves sat still until the
/// release. The host shows the dragged value as the canvas shows it and
/// hands it back as [point], so the handle and the picture move as one; the
/// drag keeps only what a gesture must — where it started and how far it
/// has gone.
///
/// Position wears [HandleGlyph.crosshair] at the active layer's posed
/// center. Dragging it moves the layer's Position and the release commits
/// ONE key at the playhead (AE semantics, one undo). Shown only while the
/// layer's Transform lanes are twirled open, so the handle never sits in
/// the way of ordinary drawing.
///
/// The ANCHOR POINT (R5 #10) wears [HandleGlyph.anchor] at the layer's
/// resolved anchor, dragged to place the point scale and rotation turn
/// about. Shown only while the standing lane declares
/// [CanvasManipulator.anchorPoint].
///
/// It does NOT compensate Position. The user's rule for #10 is that the
/// member you touch is the member that keys, and compensating would key
/// Position too; without it, dragging the anchor moves the artwork exactly
/// as scrubbing the Anchor Point value in the timeline does — the same
/// property, the same effect, reached two ways.
class CanvasPointGizmo extends StatefulWidget {
  const CanvasPointGizmo({
    super.key,
    required this.point,
    required this.viewport,
    required this.glyph,
    required this.onChanged,
    required this.onCommitted,
    required this.onCancelled,
  });

  /// The point the handle sits on, resolved at the playhead (the identity
  /// pose's centre or the canvas centre while the lane is unkeyed —
  /// dragging then creates the first key) — mid-drag, the dragged value as
  /// the host shows it.
  final CanvasPoint point;

  final CanvasViewport viewport;

  final HandleGlyph glyph;

  /// The dragged point in canvas coordinates, per move.
  final ValueChanged<CanvasPoint> onChanged;

  /// The dragged point in canvas coordinates, fired once on release.
  final ValueChanged<CanvasPoint> onCommitted;

  /// The drag went away without a release — what [onChanged] showed is to
  /// be dropped.
  final VoidCallback onCancelled;

  @override
  State<CanvasPointGizmo> createState() => _CanvasPointGizmoState();
}

class _CanvasPointGizmoState extends State<CanvasPointGizmo> {
  /// Where the drag started, in canvas space. Captured once: [point] is the
  /// dragged value mid-drag, and measuring against it would count every
  /// move twice.
  CanvasPoint? _origin;

  /// How far the pointer has gone, on screen.
  Offset _dragDelta = Offset.zero;

  Offset get _screenPoint =>
      widget.viewport.canvasToViewportOffset(widget.point);

  CanvasPoint get _dragged {
    final origin = _origin ?? widget.point;
    final canvasDelta = widget.viewport.viewportDeltaToCanvasDelta(
      dx: _dragDelta.dx,
      dy: _dragDelta.dy,
    );
    return CanvasPoint(
      x: origin.x + canvasDelta.x,
      y: origin.y + canvasDelta.y,
    );
  }

  void _startDrag() => setState(() {
    _origin = widget.point;
    _dragDelta = Offset.zero;
  });

  void _moveDrag(Offset delta) {
    _dragDelta += delta;
    widget.onChanged(_dragged);
  }

  void _endDrag() {
    final moved = _dragDelta != Offset.zero;
    final dragged = _dragged;
    setState(() {
      _origin = null;
      _dragDelta = Offset.zero;
    });
    if (moved) {
      widget.onCommitted(dragged);
    } else {
      widget.onCancelled();
    }
  }

  void _cancelDrag() {
    setState(() {
      _origin = null;
      _dragDelta = Offset.zero;
    });
    widget.onCancelled();
  }

  @override
  void dispose() {
    // A handle taken away mid-drag (the row changed under it) never sees
    // its release: what it was showing is dropped once the tree settles —
    // a notifier fired while the tree is being torn down would be too soon.
    if (_origin != null) {
      final cancel = widget.onCancelled;
      WidgetsBinding.instance.addPostFrameCallback((_) => cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _gizmoHandle(
    key: ValueKey<String>(widget.glyph.key),
    center: _screenPoint,
    handleSize: widget.glyph.handleSize,
    painter: _HandlePainter(
      glyph: widget.glyph,
      color: AppColors.accent,
      active: _origin != null,
    ),
    onDragStart: _startDrag,
    onDragDelta: _moveDrag,
    onDragEnd: _endDrag,
    onDragCancel: _cancelDrag,
  );
}

/// The one drag handle both gizmos are: a square hit target at [center]
/// that pans by delta and paints [painter] (the audit's clone scan,
/// 2026-09-03).
Widget _gizmoHandle({
  required Key key,
  required Offset center,
  required double handleSize,
  required CustomPainter painter,
  required VoidCallback onDragStart,
  required ValueChanged<Offset> onDragDelta,
  required VoidCallback onDragEnd,
  required VoidCallback onDragCancel,
}) {
  return Stack(
    children: [
      Positioned(
        left: center.dx - handleSize / 2,
        top: center.dy - handleSize / 2,
        width: handleSize,
        height: handleSize,
        // H24: the canvas under this takes the arena on the first movement,
        // so the handle takes it on the first movement too — deeper, so it
        // is asked first ([OwningPanGestureRecognizer]).
        child: FingerModeDevices.tool(
          builder: (context, devices) => RawGestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            gestures: <Type, GestureRecognizerFactory>{
              OwningPanGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    OwningPanGestureRecognizer
                  >(OwningPanGestureRecognizer.new, (recognizer) {
                    // Every build, not at construction: a finger's meaning
                    // is a setting ([FingerModeDevices]).
                    recognizer.supportedDevices = devices;
                    recognizer.onStart = (_) => onDragStart();
                    recognizer.onUpdate = (details) =>
                        onDragDelta(details.delta);
                    recognizer.onEnd = (_) => onDragEnd();
                    recognizer.onCancel = onDragCancel;
                  }),
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: CustomPaint(
                painter: painter,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _HandlePainter extends CustomPainter {
  const _HandlePainter({
    required this.glyph,
    required this.color,
    required this.active,
  });

  final HandleGlyph glyph;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = active ? 2 : 1.5
      ..color = color;
    canvas.drawCircle(center, glyph.circleRadius, stroke);
    for (final direction in const [
      Offset(1, 0),
      Offset(-1, 0),
      Offset(0, 1),
      Offset(0, -1),
    ]) {
      canvas.drawLine(
        center + direction * glyph.tickInner,
        center + direction * glyph.tickOuter,
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HandlePainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.color != color ||
      oldDelegate.active != active;
}
