import '../core/floor_math.dart';

/// A tile grid coordinate. Coordinates may be NEGATIVE: the pasteboard
/// extends one canvas size beyond every canvas edge, so tiles left/above
/// the canvas origin live at negative coords. The canvas itself always
/// starts at tile (0, 0).
class TileCoord {
  TileCoord({required this.x, required this.y});

  factory TileCoord.fromPixel({
    required int pixelX,
    required int pixelY,
    required int tileSize,
  }) {
    _validatePositive(tileSize, 'tileSize');
    // Floor division, NOT `~/`: truncation would map pixel -1 to tile 0
    // instead of tile -1.
    return TileCoord(
      x: floorDiv(pixelX, tileSize),
      y: floorDiv(pixelY, tileSize),
    );
  }

  final int x;
  final int y;

  TileCoord copyWith({int? x, int? y}) {
    return TileCoord(x: x ?? this.x, y: y ?? this.y);
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory TileCoord.fromJson(Map<String, dynamic> json) {
    return TileCoord(x: json['x'] as int, y: json['y'] as int);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TileCoord && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'TileCoord(x: $x, y: $y)';
}

void _validatePositive(int value, String fieldName) {
  if (value <= 0) {
    throw ArgumentError.value(
      value,
      fieldName,
      'TileCoord.$fieldName must be greater than 0.',
    );
  }
}

/// The tile coordinates a pixel-space rectangle touches, inclusive at both
/// ends: every tile that overlaps [left]..[right) × [top]..[bottom).
///
/// 🚨ONE walk for the surface painter and the provisional ink pictures
/// (the audit's clone scan, 2026-09-03).
({int firstX, int lastX, int firstY, int lastY}) tileRangeCovering({
  required double left,
  required double top,
  required double right,
  required double bottom,
  required int tileSize,
}) => (
  firstX: floorDiv(left.floor(), tileSize),
  lastX: floorDiv(right.ceil() - 1, tileSize),
  firstY: floorDiv(top.floor(), tileSize),
  lastY: floorDiv(bottom.ceil() - 1, tileSize),
);
