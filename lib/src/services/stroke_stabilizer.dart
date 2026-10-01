import '../models/canvas_point.dart';

/// Pull-string stroke stabilization (P7): the pen drags a brush point on a
/// rope of fixed length — the brush moves only while the rope is taut, so
/// hand jitter shorter than the rope never reaches the stroke. The rope
/// length freezes at stroke start (screen px / zoom → canvas px).
///
/// 🗣️The line ends where the BRUSH is, not where the pen lifted (유저
/// 2026-09-28, H45-Q1 「따라잡지 않는다」). ↩️Pen-up used to close the gap
/// with a straight segment to the pen, which drew a tail in the last
/// direction of travel however precisely the pen had stopped.
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
