import '../../models/bitmap_tile.dart';

/// Every tile that has been given a picture — the roll the budget walks
/// when the pictures held add up to more than the device allows
/// ([TilePictureBudget]).
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
/// A sibling of `BitmapTileImageCache` rather than a field on it: the roll
/// is a walkable thing of its own, and the cache is the door pictures come
/// through, not the census of them.
///
/// 🪦Until 2026-09-17 the roll also remembered WHERE a canvas drew each
/// tile, because letting a picture go had to un-file it from its
/// coordinate's fallback bucket. Nothing is filed by coordinate any more.
class PicturedTiles {
  PicturedTiles();

  static final PicturedTiles instance = PicturedTiles();

  final List<WeakReference<BitmapTile>> _roll = [];

  final Expando<bool> _onRoll = Expando<bool>('picturedTiles');

  /// [tile] has a picture now. A tile joins the roll once and stays on it
  /// for its life, whatever its picture does: the walk asks the cache what
  /// it holds, not the roll.
  void hold(BitmapTile tile) {
    if (_onRoll[tile] ?? false) {
      return;
    }
    _onRoll[tile] = true;
    _roll.add(WeakReference(tile));
  }

  /// Every tile on the roll that is still alive — and the dead swept out
  /// as it goes, so the roll never grows past the tiles that exist.
  List<BitmapTile> alive() {
    final result = <BitmapTile>[];
    _roll.removeWhere((ref) {
      final tile = ref.target;
      if (tile == null) {
        return true;
      }
      result.add(tile);
      return false;
    });
    return result;
  }

  /// How many entries the roll carries — dead ones included until the next
  /// walk sweeps them. A probe surface.
  int get length => _roll.length;
}
