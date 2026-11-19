import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/brush_frame_key.dart';

/// What the cels of a store's hot tier weigh — each, and all of them
/// ([bytes]) — by the bytes their tiles hold here
/// ([BitmapSurface.keptTileBytes]): the sum the hot budget is asked of at
/// every store, kept because a walk of every hot tile there would be the
/// store's own cost.
///
/// 🚨A SUM KEPT OF WEIGHTS THAT MOVE, AND RIGHT AT EVERY READ (card
/// cel-originals-are-held-twice-in-ram-and-on-the-gpu ②). A tile the
/// engine made weighs nothing till its bytes come here
/// ([BitmapTile.ownBytes]) — its copy once the hand rests, a read back —,
/// which no store is told of and which may be long after its cel was
/// weighed. So the cels that hold such a tile are kept beside their weight
/// ([_mayWeighMore]) and weighed again at the first read after bytes came
/// to any tile ([BitmapTile.timesBytesCameHere]): a read with none come
/// since costs that one comparison, and a cel leaves the list once every
/// tile of it holds its bytes — no tile's weight moves twice.
///
/// ↩️Till 2026-11-19 a store kept a map of estimates and their sum, two
/// fields written side by side at eight places and each estimate final as
/// it was made: right while a tile weighed a tile's bytes wherever they
/// lay.
final class HotCelWeights {
  final Map<BrushFrameKey, int> _weighed = {};

  /// The cels weighed some tile of which may yet weigh more
  /// ([BitmapSurface.keptTilesMayWeighMore]), each with the picture it was
  /// weighed as.
  final Map<BrushFrameKey, BitmapSurface> _mayWeighMore = {};

  int _bytes = 0;

  /// Where [BitmapTile.timesBytesCameHere] stood as [_mayWeighMore] was
  /// last weighed.
  int _cameHereAsWeighed = BitmapTile.timesBytesCameHere;

  /// What every cel weighed here weighs now.
  int get bytes {
    final came = BitmapTile.timesBytesCameHere;
    if (came != _cameHereAsWeighed) {
      _cameHereAsWeighed = came;
      for (final MapEntry(:key, value: surface)
          in _mayWeighMore.entries.toList()) {
        weigh(key, surface);
      }
    }
    return _bytes;
  }

  /// How many cels are weighed again once bytes come ([_mayWeighMore]) — a
  /// probe: one all of whose tiles hold their bytes is weighed no more.
  int get weighedAgainCount => _mayWeighMore.length;

  /// [key] weighs what [surface] does from now on, whatever it weighed.
  void weigh(BrushFrameKey key, BitmapSurface surface) {
    letGo(key);
    final bytes = surface.keptTileBytes;
    _weighed[key] = bytes;
    _bytes += bytes;
    if (surface.keptTilesMayWeighMore) {
      _mayWeighMore[key] = surface;
    }
  }

  /// [key] weighs nothing from now on — as it did, where it was not
  /// weighed.
  void letGo(BrushFrameKey key) {
    _bytes -= _weighed.remove(key) ?? 0;
    _mayWeighMore.remove(key);
  }

  /// What [from] weighed is [to]'s from now on, whatever [to] weighed;
  /// nothing moves where [from] was not weighed.
  void move(BrushFrameKey from, BrushFrameKey to) {
    final bytes = _weighed.remove(from);
    if (bytes == null) {
      return;
    }
    final surface = _mayWeighMore.remove(from);
    letGo(to);
    _weighed[to] = bytes;
    if (surface != null) {
      _mayWeighMore[to] = surface;
    }
  }

  /// No cel weighs anything from now on.
  void clear() {
    _weighed.clear();
    _mayWeighMore.clear();
    _bytes = 0;
  }
}
