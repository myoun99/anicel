import '../core/collection_equality.dart';
import 'bitmap_tile.dart';
import 'canvas_size.dart';
import 'pasteboard_bounds.dart';
import 'tile_coord.dart';

class BitmapSurface {
  BitmapSurface({
    required this.canvasSize,
    this.tileSize = 256,
    Map<TileCoord, BitmapTile> tiles = const {},
  }) : _tiles = Map<TileCoord, BitmapTile>.unmodifiable(tiles) {
    _validateTileSize(tileSize);
    _validateCanvasSize(canvasSize);
    for (final entry in _tiles.entries) {
      _validateTileEntry(entry.key, entry.value, this);
    }
  }

  final CanvasSize canvasSize;
  final int tileSize;
  final Map<TileCoord, BitmapTile> _tiles;

  Map<TileCoord, BitmapTile> get tiles => Map.unmodifiable(_tiles);

  /// CANVAS-grid tile columns (tiles that cover the canvas rect from the
  /// origin). Pasteboard tiles live outside this grid — see
  /// [containsTileCoord] for the storable range.
  int get tileColumnCount => _ceilDiv(canvasSize.width, tileSize);

  int get tileRowCount => _ceilDiv(canvasSize.height, tileSize);

  int get tileCount => tileColumnCount * tileRowCount;

  /// Whether [coord] is storable: any tile intersecting the PASTEBOARD
  /// (canvas + one canvas size in every direction), negative coords
  /// included.
  bool containsTileCoord(TileCoord coord) {
    return coord.x >= canvasSize.pasteboardTileXMin(tileSize) &&
        coord.y >= canvasSize.pasteboardTileYMin(tileSize) &&
        coord.x < canvasSize.pasteboardTileXEndExclusive(tileSize) &&
        coord.y < canvasSize.pasteboardTileYEndExclusive(tileSize);
  }

  BitmapTile? tileAt(TileCoord coord) => _tiles[coord];

  /// Puts tiles — however few — in ONE map rebuild.
  ///
  /// ⛔THE BATCH IS THE ONLY PUT. A per-tile put copied the whole tile map
  /// per call, which is O(n²) across a full-canvas commit's n tiles (417ms
  /// of an 8000² fill was exactly this), so there is deliberately no
  /// one-tile form to reach for: `putTiles([tile])` is the n = 1 case and
  /// costs the same as the old single put did.
  ///
  /// ⛔THE STORABILITY LAW IS [_validateTileEntry]'s, and only its. This
  /// put re-typed the same two throws with the same two messages; the
  /// constructor every write goes through already applies them, so the
  /// copy was dead weight that could drift (a mutant that disabled the
  /// copy's bounds check survived every test, 2026-09-07).
  BitmapSurface putTiles(Iterable<BitmapTile> tilesToPut) {
    final updated = <TileCoord, BitmapTile>{..._tiles};
    for (final tile in tilesToPut) {
      updated[tile.coord] = tile;
    }
    return copyWith(tiles: updated);
  }

  /// The end of a copy-on-write pass: the surface with [rebuilt] put back,
  /// or THIS VERY SURFACE when the pass wrote nothing.
  ///
  /// Handing the same object back is the structural-sharing half of the
  /// rewrite — callers test it with `identical`, and every tile the pass
  /// did not touch keeps its identity either way.
  BitmapSurface withRebuiltTiles(Map<TileCoord, BitmapTile> rebuilt) =>
      rebuilt.isEmpty ? this : putTiles(rebuilt.values);

  BitmapSurface removeTile(TileCoord coord) {
    final nextTiles = Map<TileCoord, BitmapTile>.of(_tiles)..remove(coord);
    return copyWith(tiles: nextTiles);
  }

  BitmapSurface copyWith({
    CanvasSize? canvasSize,
    int? tileSize,
    Map<TileCoord, BitmapTile>? tiles,
  }) {
    return BitmapSurface(
      canvasSize: canvasSize ?? this.canvasSize,
      tileSize: tileSize ?? this.tileSize,
      tiles: tiles ?? _tiles,
    );
  }

  Map<String, dynamic> toJson() => {
    'canvasSize': canvasSize.toJson(),
    'tileSize': tileSize,
    'tiles': _tiles.values.map((tile) => tile.toJson()).toList(),
  };

  factory BitmapSurface.fromJson(Map<String, dynamic> json) {
    final tiles = <TileCoord, BitmapTile>{};
    for (final tileJson in json['tiles'] as List? ?? const []) {
      final tile = BitmapTile.fromJson(tileJson as Map<String, dynamic>);
      tiles[tile.coord] = tile;
    }
    return BitmapSurface(
      canvasSize: CanvasSize.fromJson(
        json['canvasSize'] as Map<String, dynamic>,
      ),
      tileSize: json['tileSize'] as int? ?? 256,
      tiles: tiles,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BitmapSurface &&
          other.canvasSize == canvasSize &&
          other.tileSize == tileSize &&
          mapEquals(other._tiles, _tiles);

  @override
  int get hashCode => Object.hash(
    canvasSize,
    tileSize,
    Object.hashAllUnordered(
      _tiles.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );

  @override
  String toString() =>
      'BitmapSurface(canvasSize: $canvasSize, tileSize: $tileSize, '
      'storedTileCount: ${_tiles.length})';
}

int _ceilDiv(int value, int divisor) => (value + divisor - 1) ~/ divisor;

void _validateTileSize(int tileSize) {
  if (tileSize <= 0) {
    throw ArgumentError.value(
      tileSize,
      'tileSize',
      'BitmapSurface.tileSize must be greater than 0.',
    );
  }
}

void _validateCanvasSize(CanvasSize canvasSize) {
  if (canvasSize.width <= 0) {
    throw ArgumentError.value(
      canvasSize.width,
      'canvasSize.width',
      'BitmapSurface.canvasSize.width must be greater than 0.',
    );
  }
  if (canvasSize.height <= 0) {
    throw ArgumentError.value(
      canvasSize.height,
      'canvasSize.height',
      'BitmapSurface.canvasSize.height must be greater than 0.',
    );
  }
}

void _validateTileEntry(TileCoord key, BitmapTile tile, BitmapSurface surface) {
  if (tile.coord != key) {
    throw ArgumentError.value(
      tile.coord,
      'tile.coord',
      'BitmapSurface tile coord must match its map key.',
    );
  }
  if (tile.size != surface.tileSize) {
    throw ArgumentError.value(
      tile.size,
      'tile.size',
      'BitmapSurface tile size must match surface tileSize.',
    );
  }
  if (!surface.containsTileCoord(key)) {
    throw ArgumentError.value(
      key,
      'tiles',
      'BitmapSurface tile coord must be inside surface tile bounds.',
    );
  }
}
