import '../../models/bitmap_tile.dart';
import '../../models/placed_tile.dart';
import '../../models/tile_coord.dart';

/// Every tile that has been given a picture, and where a canvas draws it —
/// the roll the budget walks when the pictures held add up to more than
/// the device allows ([TilePictureBudget]).
///
/// 🚨★★★THE CACHE COULD NOT BE ASKED 「WHAT DO YOU HOLD」 (render round,
/// 2026-09-16). Its pictures live in an `Expando` keyed by the tile object:
/// a picture is found FROM its tile and dies WITH its tile, and nothing can
/// walk them. That is the right shape for a cache that never has to let a
/// picture go early — and it stopped being enough the moment the screen
/// below 100% is fed from level images (안 1): a zoomed-out cel then holds
/// every tile's full-size picture while nothing draws one. Letting those go
/// needs a roll to walk; this is it.
///
/// ⛔WEAK. Being on the roll must not keep a tile alive: it is read only by
/// the budget's walk, which sweeps out what died since. A strong list here
/// would pin every tile that ever had a picture — the undo history's
/// included — for the life of the run.
///
/// A sibling of `BitmapTileImageCache` rather than a field on it, for the
/// reason `TilePredecessors` gives: the cache sits at the long-class
/// ceiling.
class PicturedTiles {
  PicturedTiles();

  static final PicturedTiles instance = PicturedTiles();

  final List<WeakReference<BitmapTile>> _roll = [];

  /// Where a canvas draws each tile — what the cache is asked with when the
  /// picture goes. Refreshed on every [hold]: a tile object can be carried
  /// to another coordinate by a whole-tile translate.
  final Expando<TileCoord> _coordOf = Expando<TileCoord>('picturedTileCoords');

  /// [placed]'s tile has a picture now — truth or stand-in. A tile joins
  /// the roll once and stays on it for its life, whatever its picture does:
  /// the walk asks the cache what it holds, not the roll.
  void hold(PlacedTile placed) {
    final first = _coordOf[placed.tile] == null;
    _coordOf[placed.tile] = placed.coord;
    if (first) {
      _roll.add(WeakReference(placed.tile));
    }
  }

  /// Every tile on the roll that is still alive, at its coordinate — and
  /// the dead swept out as it goes, so the roll never grows past the tiles
  /// that exist.
  List<PlacedTile> alive() {
    final result = <PlacedTile>[];
    _roll.removeWhere((ref) {
      final tile = ref.target;
      if (tile == null) {
        return true;
      }
      result.add((coord: _coordOf[tile]!, tile: tile));
      return false;
    });
    return result;
  }

  /// How many entries the roll carries — dead ones included until the next
  /// walk sweeps them. A probe surface.
  int get length => _roll.length;
}
