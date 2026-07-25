import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../models/canvas_viewport.dart';

/// The brush cursor's on-screen footprint: the tip ellipse's two HALF-axis
/// vectors, already in viewport pixels.
///
/// They are vectors rather than a width/height/angle triple because the
/// viewport can be rotated and flipped: mapping the axes through the same
/// transform the canvas uses is exact for every combination, where deriving
/// a screen angle from the tip angle means getting three sign conventions
/// right at once.
class BrushCursorShape {
  const BrushCursorShape({required this.majorAxis, required this.minorAxis});

  /// Half-axis vector along the tip's long direction, in viewport pixels.
  final Offset majorAxis;

  /// Half-axis vector across it. Perpendicular to [majorAxis] — the viewport
  /// only ever rotates, flips and uniformly scales, all of which preserve
  /// right angles.
  final Offset minorAxis;

  /// Rotation of the ellipse on screen, radians clockwise from +x.
  double get rotation => math.atan2(majorAxis.dy, majorAxis.dx);

  double get majorRadius => majorAxis.distance;
  double get minorRadius => minorAxis.distance;
}

/// Below this on-screen LONG diameter the outline stops being readable — a
/// 2px brush at 100% would be a smudge two pixels wide — and the cursor
/// falls back to a crosshair.
const double minimumBrushCursorDiameter = 7.0;

/// The cursor outline for a tip of [size] canvas pixels, or `null` when it
/// would be too small to read (draw [minimumBrushCursorDiameter]'s crosshair
/// instead).
///
/// [size] is the BASE brush size: pen pressure changes what a stroke lays
/// down moment to moment, and a cursor that breathed with it would be
/// impossible to aim with. Photoshop and Clip Studio both show the base.
BrushCursorShape? brushCursorShape({
  required CanvasViewport viewport,
  required double size,
  required double roundness,
  required double angleDegrees,
}) {
  if (!size.isFinite || size <= 0) {
    return null;
  }
  final radius = size / 2;
  final radians = angleDegrees * math.pi / 180;
  final cos = math.cos(radians);
  final sin = math.sin(radians);
  // Tip space (P15): u runs along the major axis, v across it, and a
  // POSITIVE angle points the major axis visually up-right in y-down
  // coordinates — hence the negated dy.
  final major = viewport.canvasDeltaToViewportDelta(
    dx: radius * cos,
    dy: -radius * sin,
  );
  final minorRadius = radius * roundness.clamp(0.0, 1.0);
  final minor = viewport.canvasDeltaToViewportDelta(
    dx: minorRadius * sin,
    dy: minorRadius * cos,
  );

  final shape = BrushCursorShape(
    majorAxis: Offset(major.x, major.y),
    minorAxis: Offset(minor.x, minor.y),
  );
  if (shape.majorRadius * 2 < minimumBrushCursorDiameter) {
    return null;
  }
  return shape;
}
