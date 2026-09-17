import 'package:flutter/foundation.dart' show VoidCallback;

import '../../models/bitmap_tile.dart';
import '../../models/tile_coord.dart';
import '../../services/brush_frame_store.dart';
import '../../services/cel_source_effect_pass.dart';
import '../../services/history_manager.dart';
import '../canvas/after_frame_once.dart';
import '../canvas/bitmap_tile_image_cache.dart';
import '../canvas/shown_cels.dart';

/// Undo and redo whose first frame is whole — and whose pictures are made
/// ahead, so that frame is also quick.
///
/// 🚨★★★**NO STEP MAY SHOW A BLANK TILE WHERE THE PICTURE WAS WHOLE — AND
/// NOT THE OLD PICTURE EITHER** (F-68: a blank is a gap, the old picture is
/// a lie). Since 2026-09-17 the paint that shows a step makes every picture
/// it needs inside itself, so the step lands at once and its first frame
/// is whole by construction — nothing here waits. What this still does:
///
/// - After every step, the next one each way is read and its pictures
///   made a ration a frame — a press at a human pace finds them ready and
///   the frame that shows it pays nothing.
/// - Pictures no step can reach next are let go: an entry deeper than the
///   next step each way keeps its tiles, not their pictures — a press that
///   gets there before the warm-up does has them made in its own paint.
///
/// The plan on the undo-held-tile-pictures card, approved 2026-09-11
/// (「전부 확인했으니 진행해도되」).
class HistoryPictures {
  /// [store] says whether a cel still holds a tile an entry holds; without
  /// one no picture is let go, because a fork could be showing it.
  HistoryPictures({
    required this.history,
    ShownCels? shown,
    BrushFrameStore? store,
    BitmapTileImageCache? cache,
  }) : _shown = shown ?? ShownCels.instance,
       _store = store,
       _cache = cache ?? BitmapTileImageCache.instance {
    if (store != null) {
      history.addListener(_letDeepPicturesGoAfterTheFrame);
    }
  }

  final HistoryManager history;
  final ShownCels _shown;
  final BrushFrameStore? _store;
  final BitmapTileImageCache _cache;

  /// Takes one undo — or, with [undo] false, one redo — through [apply].
  void step({required bool undo, required VoidCallback apply}) {
    // The adoption the step runs first, run HERE — so what is read below
    // is what the step will actually put back.
    history.onBeforeUndoRedo?.call();
    if (!(undo ? history.canUndo : history.canRedo)) {
      // The adoption emptied the stack this press was for (a fresh entry
      // clears redo); the step itself would stop here too.
      return;
    }
    apply();
    _warmAheadAfterTheFrame();
  }

  final AfterFrameOnce _warmAhead = AfterFrameOnce();

  /// After a step lands, the NEXT one each way is read and its pictures
  /// made — a ration a frame, while the user looks at this one.
  ///
  /// ⚠️After the frame, not inside the step: a parked payload comes back
  /// through a synchronous disk read, and paying it inside the step would
  /// hold up the very frame that shows the step. WHEN it runs cannot make
  /// a step put back a wrong picture — a read-ahead is adopted only
  /// against the surface it leaned on.
  void _warmAheadAfterTheFrame() {
    // Nothing on screen, nothing to warm.
    if (!_shown.anyShown) {
      return;
    }
    _warmAhead.ask(() {
      if (_disposed) {
        return;
      }
      _shown.warm([
        for (final undo in const [true, false])
          for (final MapEntry(:key, value: cel) in history
              .readAhead(undo: undo, wants: _shown.isShown)
              .entries)
            (key, cel.next),
      ]);
    });
  }

  final AfterFrameOnce _release = AfterFrameOnce();

  /// After anything moves the history — a commit, a step, the budget — the
  /// pictures of the tiles only a DEEPER entry holds are let go.
  ///
  /// ⚠️A tile a cel still holds keeps its picture: a paste, a duplicate and
  /// an unlink store the same tile objects under a second key, so a tile
  /// one entry holds alone can be another cel's picture on screen.
  ///
  /// After the frame, for the warm's reason: inside the change, the walk
  /// would hold up the frame that shows it.
  void _letDeepPicturesGoAfterTheFrame() {
    // The warm's guard too: nothing on screen.
    if (!_shown.anyShown) {
      return;
    }
    _release.ask(() {
      final store = _store;
      if (_disposed || store == null) {
        return;
      }
      history.visitDeepHeldTiles((coord, tile) => _letGo(store, coord, tile));
    });
  }

  /// The pictures of what a canvas paints for [tile] go — the tile's own,
  /// and on a row drawn through colour keys its keyed copy's, which lives
  /// exactly as long as the tile does — unless a cel still holds [tile].
  void _letGo(BrushFrameStore store, TileCoord coord, BitmapTile tile) {
    final keyed = keyedCopyOf(tile);
    final pictured =
        _cache.imageFor(tile) != null ||
        (keyed != null && _cache.imageFor(keyed) != null);
    if (!pictured || store.holdsTile(coord, tile)) {
      return;
    }
    _cache.releasePicture(coord, tile);
    if (keyed != null && !identical(keyed, tile)) {
      _cache.releasePicture(coord, keyed);
    }
  }

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    history.removeListener(_letDeepPicturesGoAfterTheFrame);
  }
}
