import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import 'brush_cursor_geometry.dart';

/// The brush/eraser cursor: an outline of the tip footprint following the
/// pointer, Clip-Studio style — size, roundness and angle, and nothing else.
///
/// Deliberately NOT Photoshop's exact-alpha silhouette. Our sampled tips
/// (Splatter, Sponge, anything imported) would trace as a heap of contours
/// that says less than an ellipse does, every imported tip would need its
/// outline extracted and cached, and once scatter is on the exact outline
/// would be a lie — the dabs land somewhere else on purpose.
class BrushCursorOverlay extends StatelessWidget {
  const BrushCursorOverlay({
    super.key,
    required this.position,
    required this.viewport,
    required this.size,
    required this.roundness,
    required this.angleDegrees,
  });

  /// Pointer position in viewport (panel-local) coordinates.
  final Offset position;

  final CanvasViewport viewport;
  final double size;
  final double roundness;
  final double angleDegrees;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        // Its own layer: the outline repaints on every pointer move, and
        // the canvas underneath must not be dragged into that.
        child: RepaintBoundary(
          child: CustomPaint(
            key: const ValueKey<String>('brush-cursor-overlay'),
            painter: BrushCursorPainter(
              position: position,
              shape: brushCursorShape(
                viewport: viewport,
                size: size,
                roundness: roundness,
                angleDegrees: angleDegrees,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the outline (or the small-brush crosshair) in two tones so it
/// stays visible over black ink and white paper alike.
class BrushCursorPainter extends CustomPainter {
  const BrushCursorPainter({required this.position, required this.shape});

  final Offset position;

  /// `null` means the footprint is too small to read; a crosshair stands in.
  final BrushCursorShape? shape;

  /// Half-length of the crosshair's arms.
  static const double _crosshairArm = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0x66000000);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xF2FFFFFF);

    final outline = shape;
    if (outline == null) {
      _paintCrosshair(canvas, halo);
      _paintCrosshair(canvas, line);
      return;
    }
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(outline.rotation);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: outline.majorRadius * 2,
      height: outline.minorRadius * 2,
    );
    canvas.drawOval(rect, halo);
    canvas.drawOval(rect, line);
    canvas.restore();
  }

  void _paintCrosshair(Canvas canvas, Paint paint) {
    canvas.drawLine(
      position - const Offset(_crosshairArm, 0),
      position + const Offset(_crosshairArm, 0),
      paint,
    );
    canvas.drawLine(
      position - const Offset(0, _crosshairArm),
      position + const Offset(0, _crosshairArm),
      paint,
    );
  }

  @override
  bool shouldRepaint(BrushCursorPainter oldDelegate) {
    return oldDelegate.position != position ||
        oldDelegate.shape?.majorAxis != shape?.majorAxis ||
        oldDelegate.shape?.minorAxis != shape?.minorAxis;
  }
}
