import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

import '../../models/bitmap_tile.dart';
import '../../models/tile_coord.dart';
import '../../services/brush_frame_store.dart';
import '../../services/cel_source_effect_pass.dart';
import '../../services/history_manager.dart';
import '../canvas/bitmap_tile_image_cache.dart';
import '../canvas/shown_cels.dart';

/// Undo and redo whose first frame is whole.
///
/// 🚨★★★**NO STEP MAY SHOW A BLANK TILE WHERE THE PICTURE WAS WHOLE — AND
/// NOT THE OLD PICTURE EITHER** (F-68: a blank is a gap, the old picture is
/// a lie). So the pictures a step will show are made ready BEFORE it lands:
///
/// - After every step, the next one each way is read and its pictures
///   started a few tiles a frame — a press at a human pace finds them
///   ready and lands at once.
/// - A press that outruns that is answered on the spot where the engine
///   can upload synchronously (Impeller: iPad, Android, macOS).
/// - Where it cannot (Skia: Windows) the step WAITS for its pictures, then
///   lands. The model does not move until the screen can show where it
///   moved to, so the two never disagree.
/// - Pictures no step can reach next are let go: an entry deeper than the
///   next step each way keeps its tiles, not their pictures — a press that
///   gets there before the warm-up does takes the wait above.
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

  /// Takes one undo — or, with [undo] false, one redo — through [apply]: at
  /// once when every picture it will show is ready, as soon as they are
  /// otherwise.
  void step({required bool undo, required VoidCallback apply}) {
    final waiting = _waitingUndo;
    if (waiting != null) {
      // Pressed again while a step waits. The SAME way is still one step,
      // not a queue — a key held down would otherwise go on undoing after
      // it was let go. The OTHER way takes the waiting one back: the two
      // presses cancel, and nothing happens that the user did not see.
      if (waiting != undo) {
        _endWait();
      }
      return;
    }
    // The adoption the step runs first, run HERE — so what is read below
    // is what the step will actually put back.
    history.onBeforeUndoRedo?.call();
    if (!(undo ? history.canUndo : history.canRedo)) {
      // The adoption emptied the stack this press was for (a fresh entry
      // clears redo); the step itself would stop here too.
      return;
    }
    final waitFor = <CelSurface>[];
    final ahead = history.readAhead(undo: undo, wants: _shown.isShown);
    for (final MapEntry(:key, value: cel) in ahead.entries) {
      final now = cel.now;
      // Only a picture that is WHOLE now can be broken by the step. One
      // still coming in (the cel was switched to a moment ago) is made no
      // less whole by it, and waiting would hold the press for nothing.
      if (now != null &&
          _shown.drawable([(key, now)]) &&
          !_shown.drawable([(key, cel.next)])) {
        waitFor.add((key, cel.next));
      }
    }
    if (waitFor.isEmpty) {
      _land(apply);
      return;
    }
    // Where the engine uploads on the spot (Impeller) the wait ends before
    // it begins: [ShownCels.whenDrawable] makes the pictures and lands the
    // step inside this call. There is no second path for that engine.
    _wait(undo, waitFor, apply);
  }

  /// Which way the waiting step goes — null while none waits.
  bool? _waitingUndo;
  VoidCallback? _stopWaiting;

  void _wait(bool undo, List<CelSurface> cels, VoidCallback apply) {
    final revision = history.revision;
    // Reached only with a canvas showing a cel, so the bindings are up.
    final pointers = GestureBinding.instance.pointerRouter;
    VoidCallback? stopDrawable;
    _waitingUndo = undo;
    _stopWaiting = () {
      stopDrawable?.call();
      pointers.removeGlobalRoute(_onPointerWhileWaiting);
    };
    // 🚨★★★A PRESS IS HONOURED ONLY WHILE THE USER IS STILL WAITING ON IT.
    // A step nobody has seen yet, landing after they moved on, would land
    // ON what they did next — under a stroke begun after the press, or
    // over a lift whose erase it would put back. So a touch anywhere drops
    // it, and when the pictures arrive it still stands down if the history
    // moved or there is work the adoption would take.
    pointers.addGlobalRoute(_onPointerWhileWaiting);
    stopDrawable = _shown.whenDrawable(cels, () {
      _endWait();
      if (_disposed ||
          history.revision != revision ||
          (history.pendingBeforeUndoRedo?.call() ?? false)) {
        return;
      }
      _land(apply);
    });
  }

  void _endWait() {
    final stop = _stopWaiting;
    _stopWaiting = null;
    _waitingUndo = null;
    stop?.call();
  }

  void _onPointerWhileWaiting(PointerEvent event) {
    if (event is PointerDownEvent) {
      _endWait();
    }
  }

  void _land(VoidCallback apply) {
    apply();
    _warmAheadAfterTheFrame();
  }

  bool _aheadScheduled = false;

  /// After a step lands, the NEXT one each way is read and its pictures
  /// started — a few tiles a frame, while the user looks at this one.
  ///
  /// ⚠️After the frame, not inside the step: a parked payload comes back
  /// through a synchronous disk read, and paying it inside the step would
  /// hold up the very frame that shows the step. WHEN it runs cannot make
  /// a step put back a wrong picture — a read-ahead is adopted only
  /// against the surface it leaned on.
  void _warmAheadAfterTheFrame() {
    // Nothing on screen, nothing to warm — and no binding needed for it.
    if (_aheadScheduled || !_shown.anyShown) {
      return;
    }
    _aheadScheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _aheadScheduled = false;
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
      })
      ..ensureVisualUpdate();
  }

  bool _releaseScheduled = false;

  /// After anything moves the history — a commit, a step, the budget — the
  /// pictures of the tiles only a DEEPER entry holds are let go.
  ///
  /// ⚠️A tile a cel still holds keeps its picture: a paste, a duplicate and
  /// an unlink store the same tile objects under a second key, so a tile
  /// one entry holds alone can be another cel's picture on screen. The ways
  /// the screen borrows a picture for a tile not ready yet are the cache's
  /// to refuse ([BitmapTileImageCache.releasePicture]).
  ///
  /// After the frame, for the warm's reason: inside the change, the walk
  /// would hold up the frame that shows it.
  void _letDeepPicturesGoAfterTheFrame() {
    // The warm's guard too: nothing on screen, and no binding needed.
    if (_releaseScheduled || !_shown.anyShown) {
      return;
    }
    _releaseScheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _releaseScheduled = false;
        final store = _store;
        if (_disposed || store == null) {
          return;
        }
        history.visitDeepHeldTiles((coord, tile) => _letGo(store, coord, tile));
      })
      ..ensureVisualUpdate();
  }

  /// The pictures of what a canvas paints for [tile] go — the tile's own,
  /// and on a row drawn through colour keys its keyed copy's, which lives
  /// exactly as long as the tile does; truth and stand-in alike — unless a
  /// cel still holds [tile].
  void _letGo(BrushFrameStore store, TileCoord coord, BitmapTile tile) {
    final keyed = keyedCopyOf(tile);
    final pictured =
        _cache.displayImageFor(tile) != null ||
        (keyed != null && _cache.displayImageFor(keyed) != null);
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
    _endWait();
    history.removeListener(_letDeepPicturesGoAfterTheFrame);
  }
}
