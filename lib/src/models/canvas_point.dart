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
