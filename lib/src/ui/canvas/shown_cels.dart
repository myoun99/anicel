import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/brush_frame_key.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import 'after_frame_once.dart';
import 'bitmap_tile_image_cache.dart';

/// A cel as a canvas names it — the scope its painter already uses.
typedef ShownCel = (LayerId, FrameId);

/// One surface of one cel.
typedef CelSurface = (BrushFrameKey, BitmapSurface);

typedef _Shown = ({
  ShownCel cel,
  BitmapSurface Function(BitmapSurface surface)? pictured,
});

/// The cels the canvases are showing right now — and, for a canvas that
/// draws tile pictures, the pictures a change to one of them will need,
/// made AHEAD so the paint that shows the change finds them ready.
///
/// 🚨★★★A STEP MUST NOT BREAK A WHOLE PICTURE (undo-held-tile-pictures,
/// stage 1, 2026-09-11). A tile's picture is keyed on the tile OBJECT, so a
/// surface made of new objects has no pictures until they are made — and
/// an undo into an entry the budget had parked is exactly that. Since
/// 2026-09-17 the paint makes every picture it needs inside itself, so no
/// step can show a blank whatever this did; what warming still buys is
/// the frame's TIME: a cel's worth of pictures made a ration a frame
/// while the user looks at the current step, rather than all at once in
/// the paint that shows the next one.
///
/// ⚠️**THE CANVASES REGISTER THEMSELVES** ([show], [hide]) under the scope
/// their painter already names the cel by, and each says what it draws
/// pictures of. The drawing canvas draws none: the engine lays its frame
/// from the tiles (`EngineStackScreen`), and a picture made ahead for it
/// is one nobody draws — of a tile the engine landed, a wait for the GPU
/// to read it back. ↩️It said it painted the active row with its texts
/// laid — other objects than the cel's own where a text lies — while its
/// stack drew pictures (till 2026-11-12), and through its colour keys too,
/// until the engine keyed a row (float-warp-resamples-in-the-c-engine (1),
/// 2026-11-11).
class ShownCels {
  ShownCels({BitmapTileImageCache? cache})
    : _cache = cache ?? BitmapTileImageCache.instance;

  static final ShownCels instance = ShownCels();

  final BitmapTileImageCache _cache;

  final Map<Object, _Shown> _byCanvas = {};

  /// [canvas] is showing [cel]. [pictured] turns a surface of it into the
  /// tiles the canvas draws pictures of ([asItIs] where those are the
  /// cel's own) — null for a canvas that draws none, which has none made
  /// ahead. Calling again replaces it.
  void show(
    Object canvas,
    ShownCel cel, {
    required BitmapSurface Function(BitmapSurface surface)? pictured,
  }) {
    _byCanvas[canvas] = (cel: cel, pictured: pictured);
  }

  /// [canvas] is not showing a cel any more.
  void hide(Object canvas) {
    _byCanvas.remove(canvas);
  }

  /// A surface as a canvas that draws pictures of the cel's own tiles
  /// turns it into them ([show]).
  static BitmapSurface asItIs(BitmapSurface surface) => surface;

  /// Whether any canvas is showing a cel at all.
  bool get anyShown => _byCanvas.isNotEmpty;

  /// Whether a canvas is showing [key]'s cel.
  bool isShown(BrushFrameKey key) {
    final cel = key.cel;
    return _byCanvas.values.any((shown) => shown.cel == cel);
  }

  /// Every tile of [cels] a canvas showing it would draw a picture of.
  Iterable<BitmapTile> _pictured(Iterable<CelSurface> cels) sync* {
    final canvases = _byCanvas.values.toList();
    for (final (key, surface) in cels) {
      final cel = key.cel;
      for (final shown in canvases) {
        final pictured = shown.pictured;
        if (shown.cel != cel || pictured == null) {
          continue;
        }
        yield* pictured(surface).tiles.values;
      }
    }
  }

  /// Pictures a warm makes per frame. A picture is a tile copy +
  /// premultiply + upload on the UI thread, and a whole cel of them in one
  /// frame is the hitch the ration exists to prevent.
  static const int picturesPerFrame = 32;

  /// Starts making [cels]' pictures, [picturesPerFrame] a frame, through
  /// the same door the paint would take ([BitmapTileImageCache.pictureFor]).
  ///
  /// ⚠️REPLACES whatever was queued. A warm is for the NEXT step, and the
  /// one it replaces is not next any more.
  void warm(Iterable<CelSurface> cels) {
    _queue = [
      for (final tile in _pictured(cels))
        if (_cache.heldFor(tile) == null) tile,
    ];
    _pump();
  }

  List<BitmapTile> _queue = const [];
  final AfterFrameOnce _nextPump = AfterFrameOnce();

  void _pump() {
    var next = 0;
    var left = picturesPerFrame;
    while (next < _queue.length && left > 0) {
      final tile = _queue[next];
      next += 1;
      if (_cache.heldFor(tile) != null) {
        continue;
      }
      left -= 1;
      _cache.pictureFor(tile);
    }
    _queue = _queue.sublist(next);
    if (_queue.isNotEmpty) {
      // The rest of the queue goes on after the frame, a ration at a time.
      _nextPump.ask(_pump);
    }
  }
}
