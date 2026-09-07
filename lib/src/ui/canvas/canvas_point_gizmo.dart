import 'package:flutter/material.dart';

import '../../models/canvas_point.dart';
import '../../models/canvas_viewport.dart';
import '../../models/app_input_settings.dart';
import '../theme/app_theme.dart';

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

/// The on-canvas point-drag gizmo: a handle at a point in canvas space that
/// ghosts along with the drag and fires [onCommitted] ONCE on release, with
/// the screen delta mapped back through the viewport.
///
/// Position wears [HandleGlyph.crosshair] at the active layer's posed
/// center. Dragging it moves the layer's Position — the handle ghosts along
/// during the drag and the release commits ONE key at the playhead (AE
/// semantics, one undo). Shown only while the layer's Transform lanes are
/// twirled open, so the handle never sits in the way of ordinary drawing.
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
    required this.onCommitted,
  });

  /// The point the handle sits on, resolved at the playhead (the identity
  /// pose's centre or the canvas centre while the lane is unkeyed —
  /// dragging then creates the first key).
  final CanvasPoint point;

  final CanvasViewport viewport;

  final HandleGlyph glyph;

  /// The dragged point in canvas coordinates, fired once on release.
  final ValueChanged<CanvasPoint> onCommitted;

  @override
  State<CanvasPointGizmo> createState() => _CanvasPointGizmoState();
}

class _CanvasPointGizmoState extends State<CanvasPointGizmo> {
  Offset _dragDelta = Offset.zero;
  bool _dragging = false;

  Offset get _screenPoint {
    final mapped = widget.viewport.canvasToViewport(widget.point);
    return Offset(mapped.x, mapped.y);
  }

  void _endDrag() {
    final canvasDelta = widget.viewport.viewportDeltaToCanvasDelta(
      dx: _dragDelta.dx,
      dy: _dragDelta.dy,
    );
    final committed = CanvasPoint(
      x: widget.point.x + canvasDelta.x,
      y: widget.point.y + canvasDelta.y,
    );
    final moved = _dragDelta != Offset.zero;
    setState(() {
      _dragging = false;
      _dragDelta = Offset.zero;
    });
    if (moved) {
      widget.onCommitted(committed);
    }
  }

  @override
  Widget build(BuildContext context) => _gizmoHandle(
    key: ValueKey<String>(widget.glyph.key),
    center: _screenPoint + _dragDelta,
    handleSize: widget.glyph.handleSize,
    painter: _HandlePainter(
      glyph: widget.glyph,
      color: AppColors.accent,
      active: _dragging,
    ),
    onDragStart: () => setState(() => _dragging = true),
    onDragDelta: (delta) => setState(() => _dragDelta += delta),
    onDragEnd: _endDrag,
    onDragCancel: () => setState(() {
      _dragging = false;
      _dragDelta = Offset.zero;
    }),
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
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          supportedDevices: AppInput.toolPointerDevices,
          onPanStart: (_) => onDragStart(),
          onPanUpdate: (details) => onDragDelta(details.delta),
          onPanEnd: (_) => onDragEnd(),
          onPanCancel: onDragCancel,
          child: MouseRegion(
            cursor: SystemMouseCursors.move,
            child: CustomPaint(
              painter: painter,
              child: const SizedBox.expand(),
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
