import 'package:flutter/foundation.dart' show VoidCallback;

import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/placed_tile.dart';
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
/// the pictures a change to one of them will need, so the change can have
/// them ready before it lands.
///
/// 🚨★★★**A STEP MUST NOT BREAK A WHOLE PICTURE** (undo-held-tile-pictures,
/// stage 1, 2026-09-11). A tile's picture is keyed on the tile OBJECT, so a
/// surface made of new objects has no pictures until they are made — and an
/// undo into an entry the budget had parked is exactly that. Measured on a
/// 225-tile cel: 204 tiles blank on the first frame, filling in over
/// several.
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
  Iterable<PlacedTile> _painted(Iterable<CelSurface> cels) sync* {
    final canvases = _byCanvas.values.toList();
    for (final (key, surface) in cels) {
      final cel = (key.layerId, key.frameId);
      for (final shown in canvases) {
        if (shown.cel != cel) {
          continue;
        }
        for (final entry in shown.painted(surface).tiles.entries) {
          yield (coord: entry.key, tile: entry.value);
        }
      }
    }
  }

  /// Whether every tile of [cels], painted the way the canvases paint them,
  /// has a picture to draw — or never will through the decoder, which
  /// refused it: waiting on that one would be waiting forever.
  bool drawable(Iterable<CelSurface> cels) {
    for (final placed in _painted(cels)) {
      if (_cache.displayImageFor(placed.tile) == null &&
          !_cache.decodeRefused(placed.tile)) {
        return false;
      }
    }
    return true;
  }

  /// Starts making [cels] drawable, [BitmapTileImageCache.decodeStartBudget]
  /// tiles a frame — the painter's own ration, for the painter's reason: a
  /// start copies a tile on the UI thread, and a whole cel of them in one
  /// frame is the hitch the ration exists to prevent.
  ///
  /// ⚠️REPLACES whatever was queued. A warm is for the NEXT step, and the
  /// one it replaces is not next any more.
  void warm(Iterable<CelSurface> cels) {
    _queue = [
      for (final placed in _painted(cels))
        if (_needsPicture(placed)) placed,
    ];
    _pump(BitmapTileImageCache.decodeStartBudget);
  }

  List<PlacedTile> _queue = const [];
  final AfterFrameOnce _nextPump = AfterFrameOnce();

  bool _needsPicture(PlacedTile placed) =>
      _cache.displayImageFor(placed.tile) == null &&
      _cache.needsDecodeStart(placed.tile);

  /// Starts up to [budget] of the queue — through the engine's synchronous
  /// upload where it has one, so no tile is left IN FLIGHT there: a tile
  /// the asynchronous decoder is holding can only be waited for, even on an
  /// engine that could have made its picture on the spot.
  ///
  /// ⛔UNFILED, both ways. These pictures are for a surface nobody shows
  /// yet, and filing them under the cel's scope would offer them to the
  /// coordinate fallback as "the latest picture here" — the NEXT step's
  /// picture drawn for this one.
  void _pump(int budget) {
    var next = 0;
    var left = budget;
    while (next < _queue.length && left > 0) {
      final placed = _queue[next];
      next += 1;
      if (!_needsPicture(placed)) {
        continue;
      }
      left -= 1;
      final uploaded = _cache.adoptSyncUpload(
        placed,
        staleScope: BitmapTileImageCache.unfiled,
      );
      if (uploaded == null) {
        _cache.ensureDecoded(placed, staleScope: BitmapTileImageCache.unfiled);
      }
    }
    _queue = _queue.sublist(next);
    if (_queue.isNotEmpty) {
      _scheduleNextPump();
    }
  }

  /// The rest of the queue goes on after the frame, a ration at a time.
  void _scheduleNextPump() =>
      _nextPump.ask(() => _pump(BitmapTileImageCache.decodeStartBudget));

  /// Calls [then] once [cels] are drawable, and returns what stops the
  /// wait.
  ///
  /// Every picture they still need is started AT ONCE: somebody is waiting
  /// on these, which is the one case the per-frame ration is not for. Where
  /// the engine uploads synchronously (Impeller) that makes them drawable
  /// before this returns, and [then] runs at once — the on-the-spot answer
  /// is this same call, not a second path beside it.
  VoidCallback whenDrawable(Iterable<CelSurface> cels, VoidCallback then) {
    final waitingOn = cels.toList();
    warm(waitingOn);
    _pump(_queue.length);
    if (drawable(waitingOn)) {
      then();
      return _nothing;
    }
    var waiting = true;
    late final VoidCallback check;
    void stop() {
      if (waiting) {
        waiting = false;
        _cache.removeListener(check);
      }
    }

    check = () {
      if (drawable(waitingOn)) {
        stop();
        then();
      }
    };
    _cache.addListener(check);
    return stop;
  }

  static void _nothing() {}
}
