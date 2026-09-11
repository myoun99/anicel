import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

import '../../services/history_manager.dart';
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
///
/// The plan on the undo-held-tile-pictures card, approved 2026-09-11
/// (「전부 확인했으니 진행해도되」).
class HistoryPictures {
  HistoryPictures({required this.history, ShownCels? shown})
    : _shown = shown ?? ShownCels.instance;

  final HistoryManager history;
  final ShownCels _shown;

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

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _endWait();
  }
}
