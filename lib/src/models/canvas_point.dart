import 'dart:math' as math;

class CanvasPoint {
  CanvasPoint({required this.x, required this.y}) {
    _validateFiniteCoordinate(x, 'x');
    _validateFiniteCoordinate(y, 'y');
  }

  final double x;
  final double y;

  CanvasPoint copyWith({double? x, double? y}) {
    return CanvasPoint(x: x ?? this.x, y: y ?? this.y);
  }

  /// The Euclidean distance to [other].
  ///
  /// The vector arithmetic every point type owns (Offset.distance,
  /// SkPoint::Distance). The stabilizer's rope, the stamp drag and the dab
  /// interpolator each spelled it out (the audit's clone scan, 2026-09-06).
  double distanceTo(CanvasPoint other) {
    final dx = other.x - x;
    final dy = other.y - y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// The point [t] of the way from [a] to [b] — `a + (b − a) · t`, in that
  /// spelling: every caller's parity pin was written on it, and
  /// `a · (1 − t) + b · t` rounds differently.
  static CanvasPoint lerp(CanvasPoint a, CanvasPoint b, double t) =>
      CanvasPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t);

  /// [lerp] undone: where [value] falls along the line from [a] (0) to [b]
  /// (1) — its projection onto that line, 0 when the two are one point.
  static double inverseLerp(CanvasPoint a, CanvasPoint b, CanvasPoint value) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final length = dx * dx + dy * dy;
    return length == 0
        ? 0
        : ((value.x - a.x) * dx + (value.y - a.y) * dy) / length;
  }

  /// How far this point is from the segment [a]–[b] — the 後補正's measure
  /// of a wobble, and the measure of which point of a turn is its corner
  /// (F-418).
  double distanceToSegment(CanvasPoint a, CanvasPoint b) =>
      distanceTo(lerp(a, b, inverseLerp(a, b, this).clamp(0.0, 1.0)));

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory CanvasPoint.fromJson(Map<String, dynamic> json) {
    return CanvasPoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'CanvasPoint(x: $x, y: $y)';
}

void _validateFiniteCoordinate(double value, String fieldName) {
  if (!value.isFinite) {
    throw ArgumentError.value(
      value,
      fieldName,
      'CanvasPoint.$fieldName must be finite.',
    );
  }
}
