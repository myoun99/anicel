import 'dart:async';

import 'command.dart';

/// The app's one wait window as a step stands behind it — opaque here: the
/// UI draws it, and this layer only carries it from a step's first run to
/// its undo and redo.
abstract interface class WaitWindow {}

/// What an undo or a redo stands behind: the [window] its step's first run
/// stood behind, and what it works out [ahead] of it off the UI thread
/// ([WorksAheadCommand]), null when nothing.
typedef StepBehind = ({WaitWindow window, WorkAhead? ahead});

final Object _windowUp = Object();

/// Runs [body] behind [window]: every step it lands is undone and redone
/// behind the same window ([StepWindows]).
R behindWaitWindow<R>(WaitWindow window, R Function() body) =>
    runZoned(body, zoneValues: {_windowUp: window});

/// 🗣️F-551-Q1 (유저 2026-11-04: 「전부 늘 띄운다」 — 무거운 조작은 누를 때마다
/// 창 뒤로, 그 되돌리기 · 다시하기도 매번): WHICH WINDOW EACH HISTORY ENTRY
/// STOOD BEHIND as it was first taken, so its undo and its redo stand behind
/// the same. Stamped where every entry comes into the history, as the places
/// are (I-41, `HistoryPlaces`). ⛔Not per command: a command a light door
/// and a heavy one both make (a cel's pixels written over) is heavy where
/// the heavy one made it, and the door says so by its window.
/// ↩️Until 2026-11-04 a command named its window itself (`WallMove`, the
/// canvas's or the pasteboard's), which only a resize and a pasteboard
/// could.
final class StepWindows {
  /// Weak, so an entry that falls off the deep end takes its window along.
  final Expando<WaitWindow> _of = Expando<WaitWindow>('F-551');

  /// [entry] lands behind the window that is up where it lands, if one is.
  void stamp(Command entry) {
    if (Zone.current[_windowUp] case final WaitWindow up) {
      _of[entry] = up;
    }
  }

  /// [folded] stands behind what the first of [run], the entries it folds,
  /// stood behind — or the window up now.
  void fold(Command folded, List<Command> run) {
    for (final entry in run) {
      if (_of[entry] case final window?) {
        _of[folded] = window;
        return;
      }
    }
    stamp(folded);
  }

  /// The window [entry]'s first run stood behind; null for none.
  WaitWindow? of(Command entry) => _of[entry];
}
