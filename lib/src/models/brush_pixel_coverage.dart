/// One covered pixel of a dab. Coordinates may be NEGATIVE — pasteboard
/// painting reaches left/above the canvas origin.
class BrushPixelCoverage {
  BrushPixelCoverage({
    required this.x,
    required this.y,
    required this.coverage,
    this.ceiling = 1.0,
  }) {
    _validateCoverage(coverage);
    _validateCoverage(ceiling);
  }

  final int x;
  final int y;
  final double coverage;

  /// How high, as a share of the dab's opacity, the stroke may come here:
  /// what of [coverage] is the tip's edge, which does not pile
  /// (`edgeCeiling`). 1 where all of it piles.
  final double ceiling;

  BrushPixelCoverage copyWith({
    int? x,
    int? y,
    double? coverage,
    double? ceiling,
  }) {
    return BrushPixelCoverage(
      x: x ?? this.x,
      y: y ?? this.y,
      coverage: coverage ?? this.coverage,
      ceiling: ceiling ?? this.ceiling,
    );
  }

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'coverage': coverage,
    if (ceiling != 1.0) 'ceiling': ceiling,
  };

  factory BrushPixelCoverage.fromJson(Map<String, dynamic> json) {
    return BrushPixelCoverage(
      x: json['x'] as int,
      y: json['y'] as int,
      coverage: (json['coverage'] as num).toDouble(),
      ceiling: (json['ceiling'] as num?)?.toDouble() ?? 1.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushPixelCoverage &&
          other.x == x &&
          other.y == y &&
          other.coverage == coverage &&
          other.ceiling == ceiling;

  @override
  int get hashCode => Object.hash(x, y, coverage, ceiling);

  @override
  String toString() =>
      'BrushPixelCoverage(x: $x, y: $y, coverage: $coverage, '
      'ceiling: $ceiling)';
}

void _validateCoverage(double value) {
  if (!value.isFinite || value < 0.0 || value > 1.0) {
    throw ArgumentError.value(
      value,
      'coverage',
      'BrushPixelCoverage.coverage must be finite and between 0.0 and 1.0 inclusive.',
    );
  }
}
