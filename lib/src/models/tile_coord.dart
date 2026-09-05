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

/// The inclusive box of tile coordinates a rectangle touches.
typedef TileRange = ({int firstX, int lastX, int firstY, int lastY});

/// The tile coordinates an integer pixel rectangle touches, inclusive at
/// both ends: every tile that overlaps [left]..[rightExclusive) ×
/// [top]..[bottomExclusive).
///
/// 🚨ONE law for every "which tiles does this rect touch" walk — the
/// commit kernels, the stamp blend, the lift sweeps, the settling holds,
/// the region-to-tiles conversions (round 8 of the audit, 2026-09-06).
/// Before this the same four lines were written out in eleven places.
///
/// ⛔FLOORDIV, NOT `~/`. Pasteboard tiles sit at NEGATIVE coordinates and
/// truncation maps pixel -1 to tile 0, which reads the wrong tile at the
/// left and top walls. The walks that used to write this out had already
/// drifted on exactly that: one divided as doubles and floored, the other
/// called [floorDiv], and only one of them said why. A stamp can land in
/// the pasteboard, where the coordinates are negative and truncation
/// picks the wrong tile; stroke bounds reach NEGATIVE (pasteboard) space,
/// and a walk that lost the floorDiv would hold the wrong tiles at
/// exactly the edge where a stroke leaves the canvas.
TileRange tileRangeOf({
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

/// [tileRangeOf] for a continuous rectangle: the pixels it covers are the
/// floor/ceil lattice of its edges — the only thing this adds.
///
/// 🚨ONE walk for the surface painter and the provisional ink pictures
/// (the audit's clone scan, 2026-09-03); the integer twin above is the
/// same law for rects that are already on the pixel grid.
TileRange tileRangeCovering({
  required double left,
  required double top,
  required double right,
  required double bottom,
  required int tileSize,
}) => tileRangeOf(
  left: left.floor(),
  top: top.floor(),
  rightExclusive: right.ceil(),
  bottomExclusive: bottom.ceil(),
  tileSize: tileSize,
);

/// Every coordinate in [range], ROW-MAJOR (tile row outer, column inner)
/// — the order every tile walk in the tree uses, so a walk that only
/// needs the coordinates reads them from here instead of nesting its own
/// loops.
List<TileCoord> tileCoordsIn(TileRange range) => [
  for (var y = range.firstY; y <= range.lastY; y += 1)
    for (var x = range.firstX; x <= range.lastX; x += 1) TileCoord(x: x, y: y),
];
