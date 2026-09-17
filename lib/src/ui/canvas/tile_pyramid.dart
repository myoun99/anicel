import 'dart:ui' as ui;

import '../../core/collection_equality.dart';
import '../../models/tile_coord.dart';
import 'deferred_image_disposal.dart';
import 'level_image.dart';

/// The active layer's pictures at the display's levels (render round 4c,
/// 안 1 「선명」, 2026-09-16): the level-k tile at (cx, cy) stands for the
/// 2^k × 2^k block of coordinates at [cx·2^k, (cx+1)·2^k) × [cy·2^k, …),
/// one picture a tile's own size, made by halving the four level-(k−1)
/// pictures under it into their quadrants ([halvingPicture]) — so a level
/// buffer draws the active layer 1:1 from pictures that are exact box
/// means of what level 0 draws, the way it draws the other layers from
/// their level images, instead of reducing tiles by nearest under the
/// recorder's scale.
///
/// 🚨★★★MADE FROM WHAT THE COORDINATES SHOW, AND KEYED BY IT (유저 절대규칙
/// 2026-09-17, 「보이는 중이랑 결과랑 절대로 다르면 안 되」). The leaf of the
/// pyramid is the surface pass's one answer to 「what does this coordinate
/// show right now」 ([LevelTileAsk.pictureAt]) — the live stroke's result
/// tile where the overlay replaces the coordinate, else the committed
/// tile's own picture — and a level tile remembers what each coordinate
/// under it was made from ([LevelTileAsk.keyAt]: the tile object for a
/// committed tile, the overlay's picture object for a live result tile).
/// It is remade exactly when one of those would draw differently at level
/// 0, and not otherwise: a tile key survives the eviction of its picture,
/// so a zoomed-out screen keeps its level tiles while the pictures under
/// them are let go ([TilePictureBudget]); a stroke frame remakes the blocks
/// the stroke touched; pen-up hands the very images the user was looking
/// at to the committed tiles, so the remade level tile is the same bytes.
///
/// 🚨★★★MADE IN THE FRAME THAT SHOWS IT — EVERY ONE THE FRAME SHOWS. A
/// level tile is `toImageSync` of a picture drawing four images — tens of
/// microseconds — and the pictures it halves are made inside the same
/// paint ([LevelTileAsk.pictureAt]), so a block that shows anything always
/// has its level tile by the end of the paint that asked.
///
/// 🪦A RATION STOOD HERE (4c, 2026-09-16 → 2026-09-17: `mayMake`, 32 level
/// tiles a paint). A block it stopped was drawn as level 0 draws its
/// coordinates — nearest under the recorder's scale — and was to "ask
/// again next paint"; but nothing asks a painter to paint again, so on a
/// cel of more than 32 inked blocks (a painted 4K page at 50% is 40) the
/// blocks past the ration STAYED nearest beside box-mean neighbours until
/// something else repainted — measured: 180 of 1080 sampled pixels, still
/// so a second later. 유저
/// 절대규칙 「보이는 중이랑 결과랑 절대로 다르면 안 되」: a paint makes everything
/// it shows, the way it makes every tile picture it shows. What the ration
/// bought was under two milliseconds a paint against the pictures' own
/// cost in the same cold paint, which nothing rations either.
///
/// 🚨★★★BOUNDED BY THE SCREEN, NOT BY A BUDGET. A level tile lives while
/// a recent paint of its scope asked for it ([recentPaints]): the shown
/// level is the screen's size at most 4× over, and the levels under it —
/// made on the way and asked again by the next dirty remake — go with
/// their last asking. Nothing here keeps a cel's whole pyramid, and a
/// scope nobody paints keeps only what its last paints showed
/// ([retainedScopeLimit] scopes, least recently painted first).
///
/// ⛔Levels are IMAGES only (안 1): nothing here keeps reduced pixels. The
/// bytes are counted for the census ([liveBytes]).
class TilePyramid {
  TilePyramid();

  static final TilePyramid instance = TilePyramid();

  /// Scopes are the painter's lineage (a cel) — eight of them, the recently
  /// edited cels, least recently painted first.
  static const int retainedScopeLimit = 8;

  /// How many paints of its scope a level tile outlives its last asking —
  /// a stroke's frames keep remaking one block's parents, and the three
  /// siblings under each parent are asked again every frame.
  static const int recentPaints = 16;

  /// The scope of a painter whose surface is nobody's cel — the selection
  /// float. Its level tiles live here, shared by every float, for as long
  /// as a float is painted; a float has no pictures filed anywhere else.
  static final Object noLineage = Object();

  final Map<Object?, _ScopePyramid> _byScope = <Object?, _ScopePyramid>{};

  /// Bytes of every level picture alive, for the memory census.
  static int get liveBytes => _liveBytes;
  static int _liveBytes = 0;

  /// One paint of [scope] begins: what this paint asks for is kept, what
  /// [recentPaints] paints have not asked for is let go at [paintEnded].
  void paintBegan(Object? scope) {
    _scope(scope).paints += 1;
  }

  /// One paint of [scope] ended: the level tiles no recent paint asked
  /// for are let go.
  void paintEnded(Object? scope) {
    final scoped = _byScope[scope];
    if (scoped == null) {
      return;
    }
    scoped.tiles.removeWhere((_, tile) {
      final stale = scoped.paints - tile.lastAsked > recentPaints;
      if (stale) {
        tile.release();
      }
      return stale;
    });
  }

  /// The level-[level] picture of the block at [coord]: the kept one while
  /// every coordinate under it still shows what the kept one was made
  /// from, else made now — or null where the block shows nothing at all.
  ui.Image? imageFor(
    LevelTileAsk ask, {
    required int level,
    required TileCoord coord,
  }) {
    assert(ask.tileSize.isEven, 'a level tile halves the tile size');
    if (level <= 0) {
      return ask.keyAt(coord) == null ? null : ask.pictureAt(coord);
    }
    final scoped = _scope(ask.scope);
    final slot = (level, coord);
    final madeFrom = _keysUnder(ask, level, coord);
    if (madeFrom.every((key) => key == null)) {
      return null;
    }
    final kept = scoped.tiles[slot];
    if (kept != null && listsMatch(madeFrom, kept.madeFrom, identical)) {
      kept.lastAsked = scoped.paints;
      return kept.image;
    }
    final image = _rasterised(
      halvingPicture(_sourcesUnder(ask, level: level, coord: coord)),
      ask.tileSize,
    );
    kept?.release();
    scoped.tiles[slot] = _LevelTile(image, madeFrom, lastAsked: scoped.paints);
    _liveBytes += image.width * image.height * 4;
    return image;
  }

  /// The level-(level−1) pictures under the block at [coord], each at its
  /// quadrant, skipping quadrants that show nothing.
  List<LevelSource> _sourcesUnder(
    LevelTileAsk ask, {
    required int level,
    required TileCoord coord,
  }) {
    final sources = <LevelSource>[];
    final half = ask.tileSize ~/ 2;
    for (final (dx, dy) in const [(0, 0), (1, 0), (0, 1), (1, 1)]) {
      final child = TileCoord(x: coord.x * 2 + dx, y: coord.y * 2 + dy);
      final image = imageFor(ask, level: level - 1, coord: child);
      if (image == null) {
        continue;
      }
      sources.add((
        image: image,
        at: ui.Offset((dx * half).toDouble(), (dy * half).toDouble()),
      ));
    }
    return sources;
  }

  /// [recorded] as a [size] × [size] image, made in the frame, the picture
  /// let go either way.
  static ui.Image _rasterised(ui.Picture recorded, int size) {
    try {
      return recorded.toImageSync(size, size);
    } finally {
      recorded.dispose();
    }
  }

  /// Lets every level picture of [scope] go.
  void drop(Object? scope) {
    final scoped = _byScope.remove(scope);
    if (scoped == null) {
      return;
    }
    for (final tile in scoped.tiles.values) {
      tile.release();
    }
  }

  /// [scope]'s pyramid, [scope] made the most recently used; scopes
  /// beyond [retainedScopeLimit] are dropped, least recently used first.
  _ScopePyramid _scope(Object? scope) {
    final scoped = _byScope.remove(scope) ?? _ScopePyramid();
    _byScope[scope] = scoped;
    while (_byScope.length > retainedScopeLimit) {
      drop(_byScope.keys.first);
    }
    return scoped;
  }

  /// The tile coordinates under the level-[level] block at [coord], row by
  /// row: the 2^level × 2^level coordinates the block stands for.
  static Iterable<TileCoord> tilesOfBlock(int level, TileCoord coord) sync* {
    final span = 1 << level;
    for (var y = 0; y < span; y += 1) {
      for (var x = 0; x < span; x += 1) {
        yield TileCoord(x: coord.x * span + x, y: coord.y * span + y);
      }
    }
  }

  /// What every coordinate under the level-[level] block at [coord] shows,
  /// row by row, by key ([LevelTileAsk.keyAt]) — the block's identity.
  static List<Object?> _keysUnder(LevelTileAsk ask, int level, TileCoord coord) =>
      [for (final at in tilesOfBlock(level, coord)) ask.keyAt(at)];
}

/// What one paint hands the pyramid with every ask: the grid's tile size,
/// the scope the level tiles are filed under, the paint's one answer to
/// what a coordinate shows — as a key (`keyAt`: null where the coordinate
/// shows nothing; the tile object for a committed tile, the overlay's
/// picture object for a live result tile; asked without making anything)
/// and as the picture itself (`pictureAt`: asked only where `keyAt` is not
/// null, and makes the tile's picture if it has none).
typedef LevelTileAsk = ({
  int tileSize,
  Object? scope,
  Object? Function(TileCoord coord) keyAt,
  ui.Image? Function(TileCoord coord) pictureAt,
});

/// One scope's level tiles and its paint count.
class _ScopePyramid {
  int paints = 0;
  final Map<(int, TileCoord), _LevelTile> tiles = <(int, TileCoord), _LevelTile>{};
}

/// One level picture, what the coordinates under it showed when it was
/// made, and the paint that last asked for it.
class _LevelTile {
  _LevelTile(this.image, this.madeFrom, {required this.lastAsked});

  final ui.Image image;
  final List<Object?> madeFrom;
  int lastAsked;

  void release() {
    TilePyramid._liveBytes -= image.width * image.height * 4;
    DeferredImageDisposer.instance.retire(image);
  }
}
