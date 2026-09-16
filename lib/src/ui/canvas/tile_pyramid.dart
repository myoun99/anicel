import 'dart:ui' as ui;

import '../../core/collection_equality.dart';
import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/placed_tile.dart';
import '../../models/tile_coord.dart';
import 'bitmap_tile_image_cache.dart';
import 'deferred_image_disposal.dart';
import 'level_image.dart';

/// The active layer's pictures at the display's levels (render round 4c,
/// 안 1 「선명」, 2026-09-16): the level-k tile at (cx, cy) stands for the
/// 2^k × 2^k block of tiles at [cx·2^k, (cx+1)·2^k) × [cy·2^k, …), one
/// picture a tile's own size, made by halving the four level-(k−1)
/// pictures under it into their quadrants ([halvingPicture]) — so a level
/// buffer draws the active layer 1:1 from pictures that are exact box
/// means of the artwork, the way it draws the other layers from their
/// level images, instead of reducing tiles by nearest under the
/// recorder's scale.
///
/// 🚨★★★MADE IN THE FRAME, FROM PICTURES ALREADY ON THE GPU. A level tile
/// is `toImageSync` of a picture drawing four images — tens of
/// microseconds — so a commit's dirty parents are remade on the next paint
/// (the tiles under them are new objects, so the key misses) at the cost
/// the plan measured, not a cel-wide rebuild. A block with a tile that has
/// no picture yet (a decode still in flight, past the sync-upload ration)
/// is not made: the caller draws that block's tiles as it always did and
/// asks again next paint. The caller rations the making the way it rations
/// sync uploads ([mayMake]); a block the ration stops mid-way keeps the
/// level tiles it did make, so the next paint finishes it.
///
/// Keyed by the TILES under the block, by identity — structural sharing
/// makes an unchanged tile the same object and a changed one a new one —
/// so a level tile outlives the eviction of the pictures under it
/// ([TilePictureBudget]): zoomed out, the level tiles are the pictures the
/// screen needs and the tiles' own are not asked for. A level made over a
/// stand-in ([BitmapTileImageCache.putProvisional]) is marked and remade
/// once the tile's truth lands, or the stand-in would outlive its tile
/// one level up.
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

  /// Scopes are the painter's lineage (a cel), as the tile cache's stale
  /// fallback files them; the same number of them, for the same reason.
  static const int retainedScopeLimit = BitmapTileImageCache.retainedScopeLimit;

  /// How many paints of its scope a level tile outlives its last asking —
  /// a stroke's frames keep remaking one block's parents, and the three
  /// siblings under each parent are asked again every frame.
  static const int recentPaints = 16;

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

  /// The level-[level] picture of the asked surface's block at [coord]:
  /// the kept one while the tiles under it stand, else made now when every
  /// tile under it has a picture and the ask allows each making — or null,
  /// and the caller draws the block's tiles.
  ui.Image? imageFor(
    LevelTileAsk ask, {
    required int level,
    required TileCoord coord,
  }) {
    final surface = ask.surface;
    assert(surface.tileSize.isEven, 'a level tile halves the tile size');
    if (level <= 0) {
      final tile = surface.tileAt(coord);
      return tile == null ? null : ask.picture((coord: coord, tile: tile));
    }
    final scoped = _scope(ask.scope);
    final key = (level, coord);
    final tiles = _tilesUnder(surface, level, coord);
    final kept = scoped.tiles[key];
    if (kept != null && kept.stillStands(tiles, ask.cache)) {
      kept.lastAsked = scoped.paints;
      return kept.image;
    }
    final under = _sourcesUnder(ask, scoped, level: level, coord: coord);
    if (under == null || under.sources.isEmpty || !ask.mayMake()) {
      return null;
    }
    final image = _rasterised(halvingPicture(under.sources), surface.tileSize);
    kept?.release();
    scoped.tiles[key] = _LevelTile(
      image,
      tiles,
      overAStandIn: under.overAStandIn,
      lastAsked: scoped.paints,
    );
    _liveBytes += image.width * image.height * 4;
    return image;
  }

  /// The level-(level−1) pictures under the block at [coord], each at its
  /// quadrant, and whether any of them was made over a stand-in — or null
  /// when one of them cannot be had yet.
  ({List<LevelSource> sources, bool overAStandIn})? _sourcesUnder(
    LevelTileAsk ask,
    _ScopePyramid scoped, {
    required int level,
    required TileCoord coord,
  }) {
    final surface = ask.surface;
    final sources = <LevelSource>[];
    var overAStandIn = false;
    final half = surface.tileSize ~/ 2;
    for (final (dx, dy) in const [(0, 0), (1, 0), (0, 1), (1, 1)]) {
      final child = TileCoord(x: coord.x * 2 + dx, y: coord.y * 2 + dy);
      if (!_anyTileUnder(surface, level - 1, child)) {
        continue;
      }
      final image = imageFor(ask, level: level - 1, coord: child);
      if (image == null) {
        return null;
      }
      sources.add((
        image: image,
        at: ui.Offset((dx * half).toDouble(), (dy * half).toDouble()),
      ));
      overAStandIn = overAStandIn ||
          (level == 1
              ? ask.cache.imageFor(surface.tileAt(child)!) == null
              : scoped.tiles[(level - 1, child)]!.overAStandIn);
    }
    return (sources: sources, overAStandIn: overAStandIn);
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
  /// row: the 2^level × 2^level tiles the block stands for.
  static Iterable<TileCoord> tilesOfBlock(int level, TileCoord coord) sync* {
    final span = 1 << level;
    for (var y = 0; y < span; y += 1) {
      for (var x = 0; x < span; x += 1) {
        yield TileCoord(x: coord.x * span + x, y: coord.y * span + y);
      }
    }
  }

  /// The tiles under the level-[level] block at [coord], row by row, null
  /// where the surface has none — the block's identity.
  static List<BitmapTile?> _tilesUnder(
    BitmapSurface surface,
    int level,
    TileCoord coord,
  ) => [for (final at in tilesOfBlock(level, coord)) surface.tileAt(at)];

  static bool _anyTileUnder(BitmapSurface surface, int level, TileCoord coord) =>
      tilesOfBlock(level, coord).any((at) => surface.tileAt(at) != null);
}

/// What one paint hands the pyramid with every ask: the surface whose
/// blocks are asked, the scope they are filed under, the cache whose truth
/// tells a stand-in apart, and the paint's own two answers — a tile's
/// picture within its ration (`picture`; null when it has none yet) and
/// whether one more level tile may be made now (`mayMake`, asked once per
/// level tile about to be made).
typedef LevelTileAsk = ({
  BitmapSurface surface,
  Object? scope,
  BitmapTileImageCache cache,
  ui.Image? Function(PlacedTile placed) picture,
  bool Function() mayMake,
});

/// One scope's level tiles and its paint count.
class _ScopePyramid {
  int paints = 0;
  final Map<(int, TileCoord), _LevelTile> tiles = <(int, TileCoord), _LevelTile>{};
}

/// One level picture, the tiles it was made over, and the paint that last
/// asked for it.
class _LevelTile {
  _LevelTile(
    this.image,
    this.tiles, {
    required this.overAStandIn,
    required this.lastAsked,
  });

  final ui.Image image;
  final List<BitmapTile?> tiles;

  /// Whether a picture under it was a stand-in when it was made — then it
  /// is remade once the truth lands, or the off-by-one-stroke stays for
  /// the tile's life.
  final bool overAStandIn;

  int lastAsked;

  bool stillStands(List<BitmapTile?> now, BitmapTileImageCache cache) {
    if (!listsMatch(now, tiles, identical)) {
      return false;
    }
    if (overAStandIn) {
      for (final tile in tiles) {
        if (tile != null && cache.imageFor(tile) != null) {
          return false;
        }
      }
    }
    return true;
  }

  void release() {
    TilePyramid._liveBytes -= image.width * image.height * 4;
    DeferredImageDisposer.instance.retire(image);
  }
}
