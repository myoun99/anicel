import 'dart:math' as math;

/// The unit vector along ([dx], [dy]), or null when there is no direction
/// (both zero, or not finite).
///
/// Scale by the larger term before squaring: a vanishing point a few
/// million canvas units away would otherwise overflow on its way to a
/// unit vector.
///
/// 🚨ONE law for the guide model's ray direction and the guide
/// transform's mapped direction (the audit's clone scan, 2026-09-03).
({double dx, double dy})? unitDirection(double dx, double dy) {
  final scale = math.max(dx.abs(), dy.abs());
  if (scale == 0 || !scale.isFinite) return null;
  final sx = dx / scale;
  final sy = dy / scale;
  final length = math.sqrt(sx * sx + sy * sy);
  if (length == 0 || !length.isFinite) return null;
  return (dx: sx / length, dy: sy / length);
}
