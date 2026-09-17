import '../../models/bitmap_tile.dart';
import '../../services/memory_pressure_budget.dart';
import 'after_frame_once.dart';
import 'bitmap_tile_image_cache.dart';
import 'pictured_tiles.dart';

/// Lets the pictures nobody is showing go when the ones held add up to more
/// than the device allows — least recently shown first, and never the ones
/// a canvas showed in its latest paint.
///
/// 🚨★★★WHY A BUDGET AT ALL (render round, 2026-09-16). A tile's picture
/// lived exactly as long as its tile, so a shown cel held EVERY tile's
/// picture whether the view reached it or not: a fully inked 5000² page is
/// 100MB of them and its pasteboard 870MB, and zoomed out to fit — where
/// the screen needs a few megabytes of level images (안 1) — all of it
/// stayed. 유저 09-16: 「메모리는 신경쓰고싶고, 렉(반응성)은 최우선」 — so the
/// pictures the view is not using are what goes, and they are made again
/// only when the view comes back to them — inside the paint that shows
/// them, like any tile that has no picture.
///
/// ⚠️WHAT A PAINT STAMPS ([shown]). At 100% and above, the tiles under the
/// canvas's visible rect. Below 100% the screen is fed from level tiles
/// ([TilePyramid]), which keep standing when the pictures under them go —
/// so those paints stamp nothing, the full-size pictures may go, and the
/// paint that zooms back to 1:1 makes the ones it shows. (🪦For a few hours
/// of 2026-09-16, before the active layer had level tiles, a zoomed-out
/// paint stamped the tiles under its view too, so that zooming in would
/// not be a blank filling over frames; no paint can be a blank any more.)
///
/// The law for the device: a sixteenth of RAM, clamped to [128MB, 512MB].
/// A 4K view of 128px tiles is 32MB of pictures, so the ceiling is a dozen
/// screens of warm pictures beside the visible ones.
class TilePictureBudget {
  TilePictureBudget({BitmapTileImageCache? cache, PicturedTiles? pictured})
    : _cache = cache ?? BitmapTileImageCache.instance,
      _pictured = pictured ?? PicturedTiles.instance;

  static final TilePictureBudget instance = TilePictureBudget();

  final BitmapTileImageCache _cache;
  final PicturedTiles _pictured;

  /// This device's ceiling on tile pictures ([CacheBudgetLine.tileImages]);
  /// null RAM (no engine: tests, host runs) keeps the desktop-class ceiling,
  /// as every device law does.
  static int deviceScaledByteBudget({required int? physicalMemoryBytes}) =>
      deviceScaledBudget(
        physicalMemoryBytes: physicalMemoryBytes,
        divisor: 16,
        floor: 128 * 1024 * 1024,
        ceiling: 512 * 1024 * 1024,
      );

  /// Bytes of tile pictures allowed before the ones nobody shows go. The
  /// session sets it from the allowance; until it does, the desktop law.
  int byteBudget = deviceScaledByteBudget(physicalMemoryBytes: null);

  /// How many paints, of any canvas, a canvas's latest paint stays current
  /// for. An idle canvas beside a busy one keeps its visible pictures this
  /// long; past it they may go, and its next paint makes them again.
  static const int recentPaints = 16;

  int _paintSerial = 0;

  /// The serial of each scope's latest paint. Forgotten once it is older
  /// than [recentPaints], so this never outgrows the canvases in use.
  final Map<Object?, int> _lastPaintOf = <Object?, int>{};

  final Expando<_Shown> _shownAt = Expando<_Shown>('tilePictureShownAt');

  /// A canvas painting [scope] — the lineage its painter names its cel by —
  /// began a paint. Every [shown] until the next [paintBegan] is this
  /// paint's.
  void paintBegan(Object? scope) {
    _paintSerial += 1;
    _lastPaintOf[scope] = _paintSerial;
  }

  /// The paint in progress for [scope] has [tile] under its visible rect.
  void shown(Object? scope, BitmapTile tile) {
    _shownAt[tile] = _Shown(scope, _paintSerial);
  }

  /// Whether [tile] was under the visible rect of its canvas's latest
  /// paint, and that paint is recent.
  bool _current(BitmapTile tile) {
    final shown = _shownAt[tile];
    return shown != null &&
        shown.serial == _lastPaintOf[shown.scope] &&
        _paintSerial - shown.serial < recentPaints;
  }

  /// Whether the pictures held exceed [byteBudget].
  bool get overBudget => BitmapTileImageCache.liveImageBytes > byteBudget;

  final AfterFrameOnce _letGoAfterFrame = AfterFrameOnce();

  /// A paint ended: if the pictures are over budget now, let go after the
  /// frame — never inside a paint, which is where the pictures are drawn.
  /// Without a scheduler binding (headless painter tests) at once, and then
  /// only what that paint did not show.
  void paintEnded() {
    if (overBudget) {
      _letGoAfterFrame.ask(letGo);
    }
  }

  /// Lets go the pictures of tiles no canvas is showing — the never-shown
  /// first, then the least recently shown — until the pictures held fit
  /// [byteBudget] or none is left to let go. Returns how many went.
  ///
  /// 🪦Until 2026-09-17 the cache could REFUSE one — a picture lent to a
  /// coordinate as its stand-in stayed whatever this said. Nothing is lent
  /// any more, so what this picks goes.
  int letGo() {
    if (!overBudget) {
      return 0;
    }
    final candidates = <({int serial, BitmapTile tile})>[];
    for (final tile in _pictured.alive()) {
      if (_cache.imageFor(tile) == null || _current(tile)) {
        continue;
      }
      candidates.add((serial: _shownAt[tile]?.serial ?? -1, tile: tile));
    }
    candidates.sort((a, b) => a.serial.compareTo(b.serial));
    var went = 0;
    for (final candidate in candidates) {
      if (!overBudget) {
        break;
      }
      _cache.releasePicture(candidate.tile);
      went += 1;
    }
    _lastPaintOf.removeWhere(
      (_, serial) => _paintSerial - serial >= recentPaints,
    );
    return went;
  }
}

/// One stamp: the paint that last had a tile under its visible rect.
class _Shown {
  const _Shown(this.scope, this.serial);

  final Object? scope;
  final int serial;
}
