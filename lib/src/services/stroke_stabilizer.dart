import '../models/canvas_point.dart';

/// Pull-string stroke stabilization (P7): the pen drags a brush point on a
/// rope of fixed length — the brush moves only while the rope is taut, so
/// hand jitter shorter than the rope never reaches the stroke. The rope
/// length freezes at stroke start (screen px / zoom → canvas px), and
/// pen-up catches the brush up to the pen with a straight segment (the
/// caller feeds the final pen position through the normal move pipeline).
class StrokeStabilizer {
  StrokeStabilizer({required this.ropeLength, required CanvasPoint start})
    : _brush = start;

  /// Rope length in CANVAS pixels (0 = pass-through; callers skip
  /// constructing one then).
  final double ropeLength;

  CanvasPoint _brush;

  /// The current brush point.
  CanvasPoint get position => _brush;

  /// Feeds one pen sample; returns the (possibly unmoved) brush point.
  CanvasPoint follow(CanvasPoint pen) {
    final distance = _brush.distanceTo(pen);
    if (distance <= ropeLength || distance == 0) {
      return _brush;
    }
    return _brush = CanvasPoint.lerp(
      _brush,
      pen,
      (distance - ropeLength) / distance,
    );
  }
}
