import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'brush_cursor_geometry.dart';
import '../repaint_props.dart';
import 'tool_cursor_look.dart';

/// The brush/eraser cursor: an outline of the tip footprint following the
/// pointer, Clip-Studio style — size, roundness and angle, and nothing else.
///
/// Deliberately NOT Photoshop's exact-alpha silhouette. Our sampled tips
/// (Splatter, Sponge, anything imported) would trace as a heap of contours
/// that says less than an ellipse does, every imported tip would need its
/// outline extracted and cached, and once scatter is on the exact outline
/// would be a lie — the dabs land somewhere else on purpose.
///
/// Paints the outline (or the small-brush crosshair) in two tones so it
/// stays visible over black ink and white paper alike, at the CENTRE of
/// whatever box it is given: the pointer's position is the box's position,
/// which is what lets one picture of it be moved rather than repainted
/// (the sprite's whole point — see [ToolCursorLook]).
class BrushCursorPainter extends CustomPainter with RepaintOnProps {
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
  Object get props => (shape?.majorAxis, shape?.minorAxis);
}

/// Room around the outline for the halo stroke and the crosshair arms.
const double _brushCursorPad = 6;

/// The brush cursor's look for [shape]: the outline painter in a box that
/// certainly holds it, the pointer at the box's centre.
///
/// The ellipse can be rotated to any angle, so the box that certainly
/// holds it is the one built from the LONGER half-axis in both directions.
/// Cheap, and never clips.
ToolCursorLook brushCursorLook(BrushCursorShape? shape) {
  final reach = shape == null
      ? BrushCursorPainter.crosshairArm
      : math.max(shape.majorRadius, shape.minorRadius);
  final extent = 2 * (reach + _brushCursorPad);
  return ToolCursorLook(
    key: ('brush', shape?.majorAxis, shape?.minorAxis),
    painter: BrushCursorPainter(shape: shape),
    extent: Size(extent, extent),
    hotspot: Offset(extent / 2, extent / 2),
  );
}
