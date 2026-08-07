import 'dart:math' as math;

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
///
/// 🚀★It is a SMALL LAYER THAT MOVES, not a panel-sized one that repaints
/// (유저, R3 #13: 브러시툴이나 지우개툴선택된상황에서 커서가 매우느림). It used
/// to be a `Positioned.fill` CustomPaint whose painter took the pointer
/// position, so every hover event re-rastered a repaint boundary the size of
/// the whole canvas to move an ellipse a few pixels. The box is the
/// footprint now and the POSITION is layout: while the tip's shape does not
/// change, moving it re-offsets the cached layer and paints nothing at all.
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

  /// Room around the outline for the halo stroke and the crosshair arms.
  static const double _pad = 6;

  @override
  Widget build(BuildContext context) {
    final shape = brushCursorShape(
      viewport: viewport,
      size: size,
      roundness: roundness,
      angleDegrees: angleDegrees,
    );
    // The ellipse can be rotated to any angle, so the box that certainly
    // holds it is the one built from the LONGER half-axis in both
    // directions. Cheap, and never clips.
    final reach = shape == null
        ? BrushCursorPainter.crosshairArm
        : math.max(shape.majorRadius, shape.minorRadius);
    final extent = 2 * (reach + _pad);
    return Positioned(
      left: position.dx - extent / 2,
      top: position.dy - extent / 2,
      width: extent,
      height: extent,
      child: IgnorePointer(
        // Its own layer, so moving it is a transform rather than a repaint.
        child: RepaintBoundary(
          child: CustomPaint(
            key: const ValueKey<String>('brush-cursor-overlay'),
            painter: BrushCursorPainter(shape: shape),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// Paints the outline (or the small-brush crosshair) in two tones so it
/// stays visible over black ink and white paper alike.
///
/// It paints at the CENTRE of whatever box it is given — the pointer's
/// position is the box's position now, which is what keeps this painter
/// from having to repaint on every move.
class BrushCursorPainter extends CustomPainter {
  const BrushCursorPainter({required this.shape});

  /// `null` means the footprint is too small to read; a crosshair stands in.
  final BrushCursorShape? shape;

  /// Half-length of the crosshair's arms.
  static const double crosshairArm = 5.0;

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

    final centre = Offset(size.width / 2, size.height / 2);
    final outline = shape;
    if (outline == null) {
      _paintCrosshair(canvas, centre, halo);
      _paintCrosshair(canvas, centre, line);
      return;
    }
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
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

  void _paintCrosshair(Canvas canvas, Offset centre, Paint paint) {
    canvas.drawLine(
      centre - const Offset(crosshairArm, 0),
      centre + const Offset(crosshairArm, 0),
      paint,
    );
    canvas.drawLine(
      centre - const Offset(0, crosshairArm),
      centre + const Offset(0, crosshairArm),
      paint,
    );
  }

  @override
  bool shouldRepaint(BrushCursorPainter oldDelegate) =>
      oldDelegate.shape?.majorAxis != shape?.majorAxis ||
      oldDelegate.shape?.minorAxis != shape?.minorAxis;
}
