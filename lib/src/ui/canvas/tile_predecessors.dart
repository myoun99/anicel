import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/brush_frame_cache_invalidation.dart';
import '../../models/tile_coord.dart';

/// What stood at a tile's coordinate before the commit that made it —
/// [tile] null when the coordinate held nothing.
///
/// A class rather than a bare nullable: an [Expando] cannot tell "no
/// predecessor recorded" from "the predecessor is nothing", and the two
/// are different answers — the second composes from transparent.
class TilePredecessor {
  const TilePredecessor(this.tile);

  final BitmapTile? tile;
}

/// 🚨★★★WHICH TILE STOOD AT EACH NEW TILE'S COORDINATE BEFORE IT — by
/// tile identity, per tile, not by coordinate per lineage (F-68 root fix,
/// 2026-09-11).
///
/// This is the truthful version of the tile image cache's coordinate
/// fallback. That one answers "what was last DECODED here", a previous
/// generation chosen by timing: right for an edit that ADDS ink (the stroke
/// shows a frame late), wrong for one that REMOVES it (the erased artwork
/// shows a frame late — F-68 ①②③, every one of them). A predecessor is
/// chosen by the commit that replaced it, so the painter can compose the
/// new tile's picture as *predecessor's picture + the byte difference*,
/// exact whichever direction the edit went (`composePredecessorStandIn`).
///
/// Bounded: an entry is dropped the moment the tile's own picture lands
/// (the cache does that where truth arrives) or its stand-in is composed,
/// so a predecessor is retained for exactly the frames it is needed. A tile
/// whose coordinate held NOTHING before records that too — an empty
/// predecessor is an answer ("compose from transparent"), not the absence
/// of one. A stale entry for a tile that got its picture some other way is
/// never read (the painter asks only when the tile has none) and dies with
/// the tile.
///
/// ⚠️A singleton beside `BitmapTileImageCache.instance` rather than a field
/// on it: the store is keyed by tile identity and holds nothing per cache,
/// and the cache class sits on the long-class ratchet's ceiling — a field
/// and its doc there was the line that tipped it (2026-09-11).
class TilePredecessors {
  TilePredecessors();

  static final TilePredecessors instance = TilePredecessors();

  final Expando<TilePredecessor> _byTile = Expando<TilePredecessor>(
    'bitmapTilePredecessors',
  );

  /// The same records the other way round: the tiles that named a tile as
  /// what stood before them. WEAKLY — having once replaced a tile must not
  /// keep a tile alive — and read only by [lends], which sweeps out what
  /// died or was dropped since.
  final Expando<List<WeakReference<BitmapTile>>> _successors =
      Expando<List<WeakReference<BitmapTile>>>('bitmapTileSuccessors');

  /// Records, for every coordinate whose tile object differs between
  /// [before] and [after], that the tile in [after] succeeded the tile in
  /// [before] (null where [before] held nothing).
  ///
  /// [coords] narrows the walk to the caller's coordinates (a float's own
  /// tiles); without it every coordinate of both surfaces is compared,
  /// which structural sharing makes an identity check per coordinate.
  /// Unchanged coordinates never reach [note]: without [coords] the diff
  /// skips them, and with it every tile is new.
  void noteBetween(
    BitmapSurface before,
    BitmapSurface after, {
    Iterable<TileCoord>? coords,
  }) {
    if (before.tileSize != after.tileSize) {
      // A coordinate means the same square in both only on one grid.
      return;
    }
    for (final coord in coords ?? tileCoordsChangedBetween(before, after)) {
      final tile = after.tileAt(coord);
      if (tile != null) {
        note(tile, before.tileAt(coord));
      }
    }
  }

  /// [before] stood where [tile] now stands. The first answer sticks: a
  /// tile whose predecessor was already recorded keeps the earlier one —
  /// it is the one the picture on screen was composed from.
  void note(BitmapTile tile, BitmapTile? before) {
    if (_byTile[tile] != null) {
      return;
    }
    _byTile[tile] = TilePredecessor(before);
    if (before != null) {
      (_successors[before] ??= []).add(WeakReference(tile));
    }
  }

  /// What stood at [tile]'s coordinate before it, if a commit said so and
  /// nothing has dropped it since.
  TilePredecessor? of(BitmapTile tile) => _byTile[tile];

  /// Whether a tile still alive may compose its stand-in from [tile]'s
  /// picture: it names [tile] as what stood before it, nothing has dropped
  /// that, and [hasPicture] says it has no picture of its own to draw.
  ///
  /// 🚨While one does, [tile]'s picture is owed to the screen even though
  /// nothing shows [tile] itself — the painter reaches it THROUGH the
  /// successor. So a picture is not let go while this says so
  /// (undo-held-tile-pictures, stage 2).
  ///
  /// ⚠️A successor WITH a picture borrows nothing — the painter asks for a
  /// predecessor only when the tile has none — and its record can stand for
  /// as long as the tile lives, because only a landing picture drops one.
  /// Counted, such records kept pictures the stage let go of in the pins.
  bool lends(
    BitmapTile tile, {
    required bool Function(BitmapTile successor) hasPicture,
  }) {
    final successors = _successors[tile];
    if (successors == null) {
      return false;
    }
    successors.removeWhere((successor) {
      final alive = successor.target;
      return alive == null || !identical(_byTile[alive]?.tile, tile);
    });
    if (successors.isEmpty) {
      _successors[tile] = null;
      return false;
    }
    return successors.any((successor) {
      final alive = successor.target;
      return alive != null && !hasPicture(alive);
    });
  }

  /// Forgets [tile]'s predecessor — the stand-in was composed, or truth
  /// landed; either way nothing is left to compose from.
  void drop(BitmapTile tile) {
    _byTile[tile] = null;
  }
}

/// Hands the store each changed tile's predecessor from a brush-frame
/// invalidation that carries both surfaces; a no-op for one that does not.
///
/// 🚨★★★ONE FUNCTION FOR EVERY SINK. The editor's hub calls it from a
/// listener; the standalone hosts' recording sink (timesheet ink, conte,
/// envelope) calls it directly. Both sinks see every surface replacement
/// their host makes, and the painter behind both is the same one — so a
/// removal on a conte page gets the same truthful first frame as one on a
/// cel. Register a new sink kind and this is the line it has to reach.
void notePredecessorsFromInvalidation(
  BrushFrameCacheInvalidation invalidation,
) {
  final transition = invalidation.transition;
  if (transition == null) {
    return;
  }
  TilePredecessors.instance.noteBetween(transition.before, transition.after);
}
