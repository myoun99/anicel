/// Every tile — or colour (`BitmapTile.pixelsKey`) — a holder has given a
/// copy of its own — a picture (`BitmapTileImageCache`) — the roll it walks
/// when it lets those copies go early.
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
/// the holder's walk, which sweeps out what died since. A strong list here
/// would pin every tile that ever had a copy — the undo history's
/// included — for the life of the run.
///
/// A sibling of its holder rather than a field on it: the roll is a
/// walkable thing of its own, and the holder is the door copies come
/// through, not the census of them.
///
/// In `models/` since 2026-11-08 (screen-on-the-engine c4), when the
/// engine's ledger in `native/` walked one too. 🪦It walks its own slots
/// since (pool-pages-given-back): a give-back lets a collected tile's slot
/// go, which a roll of the live tiles cannot name.
///
/// 🪦Until 2026-09-17 the roll also remembered WHERE a canvas drew each
/// tile, because letting a picture go had to un-file it from its
/// coordinate's fallback bucket. Nothing is filed by coordinate any more.
class TileRoll {
  TileRoll();

  final List<WeakReference<Object>> _roll = [];

  final Expando<bool> _onRoll = Expando<bool>('tileRoll');

  /// [key] has a copy now — a tile, or the block every tile of a colour
  /// holds (`BitmapTile.pixelsKey`). A key joins the roll once and stays on
  /// it for its life, whatever its copy does: the walk asks the holder what
  /// it holds, not the roll.
  void hold(Object key) {
    if (_onRoll[key] ?? false) {
      return;
    }
    _onRoll[key] = true;
    _roll.add(WeakReference(key));
  }

  /// Every key on the roll that is still alive — and the dead swept out
  /// as it goes, so the roll never grows past the keys that exist.
  List<Object> alive() {
    final result = <Object>[];
    _roll.removeWhere((ref) {
      final key = ref.target;
      if (key == null) {
        return true;
      }
      result.add(key);
      return false;
    });
    return result;
  }

  /// How many entries the roll carries — dead ones included until the next
  /// walk sweeps them. A probe surface.
  int get length => _roll.length;
}
