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
  BitmapSurface Function(BitmapSurface surface) painted,
});

/// The cels the canvases are painting with tile pictures right now — and
/// the pictures a change to one of them will need, made AHEAD so the paint
/// that shows the change finds them ready.
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
/// their painter already names the cel by, and each says how it paints a
/// surface of it: the drawing canvas draws the active row THROUGH its
/// colour keys, so the tiles it paints are other objects than the cel's
/// own — warming the cel's own there would warm pictures nobody draws.
class ShownCels {
  ShownCels({BitmapTileImageCache? cache})
    : _cache = cache ?? BitmapTileImageCache.instance;

  static final ShownCels instance = ShownCels();

  final BitmapTileImageCache _cache;

  final Map<Object, _Shown> _byCanvas = {};

  /// [canvas] is painting [cel] — a surface of it turned into tiles the way
  /// [painted] does, as it is when omitted. Calling again replaces it.
  void show(
    Object canvas,
    ShownCel cel, {
    BitmapSurface Function(BitmapSurface surface)? painted,
  }) {
    _byCanvas[canvas] = (cel: cel, painted: painted ?? _asIs);
  }

  /// [canvas] is not painting a cel any more.
  void hide(Object canvas) {
    _byCanvas.remove(canvas);
  }

  static BitmapSurface _asIs(BitmapSurface surface) => surface;

  /// Whether any canvas is painting a cel at all.
  bool get anyShown => _byCanvas.isNotEmpty;

  /// Whether a canvas is painting [key]'s cel.
  bool isShown(BrushFrameKey key) {
    final cel = (key.layerId, key.frameId);
    return _byCanvas.values.any((shown) => shown.cel == cel);
  }

  /// Every tile [cels] would put on screen, on every canvas showing it.
  Iterable<BitmapTile> _painted(Iterable<CelSurface> cels) sync* {
    final canvases = _byCanvas.values.toList();
    for (final (key, surface) in cels) {
      final cel = (key.layerId, key.frameId);
      for (final shown in canvases) {
        if (shown.cel != cel) {
          continue;
        }
        yield* shown.painted(surface).tiles.values;
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
      for (final tile in _painted(cels))
        if (_cache.imageFor(tile) == null) tile,
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
      if (_cache.imageFor(tile) != null) {
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
