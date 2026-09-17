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
/// tile, a held pre-stroke tile, a committed picture, a stand-in — and a
/// level tile remembers what each coordinate under it was made from
/// ([LevelTileAsk.keyAt]: the tile object for a committed truth, the
/// picture object for anything standing at the coordinate instead). It is
/// remade exactly when one of those would draw differently at level 0, and
/// not otherwise: a truth key survives the eviction of its picture, so a
/// zoomed-out screen keeps its level tiles while the pictures under them
/// are let go ([TilePictureBudget]); a stroke frame remakes the blocks the
/// stroke touched; pen-up hands the very images the user was looking at to
/// the committed tiles, so the remade level tile is the same bytes.
///
/// 🚨★★★MADE IN THE FRAME, FROM PICTURES ALREADY ON THE GPU. A level tile
/// is `toImageSync` of a picture drawing four images — tens of
/// microseconds. A block with a coordinate that has bytes but no picture
/// yet (a decode still in flight, past the sync-upload ration) is not
/// made: the caller draws that block's coordinates as level 0 does and
/// asks again next paint. The caller rations the making the way it rations
/// sync uploads ([LevelTileAsk.mayMake]); a block the ration stops mid-way
/// keeps the level tiles it did make, so the next paint finishes it.
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
  /// from, else made now when every coordinate under it has its picture
  /// and the ask allows each making — or null, and the caller draws the
  /// block's coordinates as level 0 does (a block that shows nothing at all
  /// is null too, and drawing its coordinates draws nothing).
  ui.Image? imageFor(
    LevelTileAsk ask, {
    required int level,
    required TileCoord coord,
  }) => _answer(ask, level: level, coord: coord).image;

  _LevelAnswer _answer(
    LevelTileAsk ask, {
    required int level,
    required TileCoord coord,
  }) {
    assert(ask.tileSize.isEven, 'a level tile halves the tile size');
    if (level <= 0) {
      if (ask.keyAt(coord) == null) {
        return const _LevelAnswer.nothing();
      }
      return _LevelAnswer(ask.pictureAt(coord));
    }
    final scoped = _scope(ask.scope);
    final slot = (level, coord);
    final madeFrom = _keysUnder(ask, level, coord);
    if (madeFrom.every((key) => key == null)) {
      return const _LevelAnswer.nothing();
    }
    final kept = scoped.tiles[slot];
    if (kept != null && listsMatch(madeFrom, kept.madeFrom, identical)) {
      kept.lastAsked = scoped.paints;
      return _LevelAnswer(kept.image);
    }
    final sources = _sourcesUnder(ask, level: level, coord: coord);
    if (sources == null || !ask.mayMake()) {
      return const _LevelAnswer.pending();
    }
    final image = _rasterised(halvingPicture(sources), ask.tileSize);
    kept?.release();
    scoped.tiles[slot] = _LevelTile(
      image,
      // Read AFTER the sources: making them may have uploaded a truth the
      // key-only read could not see, and the tile is made from that.
      _keysUnder(ask, level, coord),
      lastAsked: scoped.paints,
    );
    _liveBytes += image.width * image.height * 4;
    return _LevelAnswer(image);
  }

  /// The level-(level−1) pictures under the block at [coord], each at its
  /// quadrant, skipping quadrants that show nothing — or null when one of
  /// them cannot be had yet.
  List<LevelSource>? _sourcesUnder(
    LevelTileAsk ask, {
    required int level,
    required TileCoord coord,
  }) {
    final sources = <LevelSource>[];
    final half = ask.tileSize ~/ 2;
    for (final (dx, dy) in const [(0, 0), (1, 0), (0, 1), (1, 1)]) {
      final child = TileCoord(x: coord.x * 2 + dx, y: coord.y * 2 + dy);
      final under = _answer(ask, level: level - 1, coord: child);
      if (under.nothing) {
        continue;
      }
      final image = under.image;
      if (image == null) {
        return null;
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
/// shows nothing; the tile object for a committed truth, the picture
/// object for anything standing at the coordinate instead; asked without
/// making anything) and as the picture itself (`pictureAt`: null where the
/// coordinate has bytes but no picture yet; may upload or compose within
/// the paint's rations) — and whether one more level tile may be made now
/// (`mayMake`, asked once per level tile about to be made).
typedef LevelTileAsk = ({
  int tileSize,
  Object? scope,
  Object? Function(TileCoord coord) keyAt,
  ui.Image? Function(TileCoord coord) pictureAt,
  bool Function() mayMake,
});

/// One answer of the pyramid: a picture, nothing to show at all, or a
/// picture that cannot be had yet.
class _LevelAnswer {
  const _LevelAnswer(this.image) : nothing = false;

  const _LevelAnswer.nothing() : image = null, nothing = true;

  const _LevelAnswer.pending() : image = null, nothing = false;

  final ui.Image? image;
  final bool nothing;
}

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
