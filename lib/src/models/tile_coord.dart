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
/// ends: every tile that overlaps [left]..[rightExclusive) ×
/// [top]..[bottomExclusive).
///
/// 🚨ONE walk for the surface painter and the provisional ink pictures
/// (the audit's clone scan, 2026-09-03) — and, since 2026-09-06, the ONE
/// range law under `tilesCovering` and `DirtyRegion.toTileCoords` too.
///
/// ⛔FLOORDIV, NOT `~/`. Pasteboard tiles sit at NEGATIVE coordinates and
/// truncation maps pixel -1 to tile 0, which reads the wrong tile at the
/// left and top walls. The walks that used to write this out had already
/// drifted on exactly that: one divided as doubles and floored, the other
/// called [floorDiv], and only one of them said why.
({int firstX, int lastX, int firstY, int lastY}) tileRangeCoveringPixels({
  required int left,
  required int top,
  required int rightExclusive,
  required int bottomExclusive,
  required int tileSize,
}) => (
  firstX: floorDiv(left, tileSize),
  lastX: floorDiv(rightExclusive - 1, tileSize),
  firstY: floorDiv(top, tileSize),
  lastY: floorDiv(bottomExclusive - 1, tileSize),
);
