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

  /// Row-major order: by row, then by column — the order the commit tail
  /// puts finished tiles in, so a materialization is deterministic
  /// whatever order the dabs touched them.
  static int compareRowMajor(TileCoord a, TileCoord b) {
    final rows = a.y.compareTo(b.y);
    return rows != 0 ? rows : a.x.compareTo(b.x);
  }

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

/// The tiles one axis of a pixel span touches, inclusive at both ends:
/// every tile that overlaps [start]..[endExclusive).
///
/// 🚨ONE law for every "which tiles does this rect touch" walk — the
/// commit kernels, the stamp blend, the lift sweeps, the settling holds,
/// the region-to-tiles conversions (round 8 of the audit, 2026-09-06).
/// Before this the same four lines were written out in eleven places;
/// now a rect is this law on each axis ([DirtyRegion.tileRange] for
/// integer rects, [tileRangeCovering] for continuous ones).
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
({int first, int last}) tileAxisSpan({
  required int start,
  required int endExclusive,
  required int tileSize,
}) => (
  first: floorDiv(start, tileSize),
  last: floorDiv(endExclusive - 1, tileSize),
);

/// [tileAxisSpan] on both axes of a continuous rectangle: the pixels it
/// covers are the floor/ceil lattice of its edges — the only thing this
/// adds.
///
/// 🚨ONE walk for the surface painter and the provisional ink pictures
/// (the audit's clone scan, 2026-09-03); [DirtyRegion.tileRange] is the
/// same law for rects that are already on the pixel grid.
TileRange tileRangeCovering({
  required double left,
  required double top,
  required double right,
  required double bottom,
  required int tileSize,
}) {
  final x = tileAxisSpan(
    start: left.floor(),
    endExclusive: right.ceil(),
    tileSize: tileSize,
  );
  final y = tileAxisSpan(
    start: top.floor(),
    endExclusive: bottom.ceil(),
    tileSize: tileSize,
  );
  return (firstX: x.first, lastX: x.last, firstY: y.first, lastY: y.last);
}

/// Every coordinate in [range], ROW-MAJOR (tile row outer, column inner)
/// — the order every tile walk in the tree uses, so a walk that only
/// needs the coordinates reads them from here instead of nesting its own
/// loops.
List<TileCoord> tileCoordsIn(TileRange range) => [
  for (var y = range.firstY; y <= range.lastY; y += 1)
    for (var x = range.firstX; x <= range.lastX; x += 1) TileCoord(x: x, y: y),
];
