import 'dart:async';

import '../models/layer.dart';
import 'command.dart';

/// The app's one wait window as a step stands behind it — opaque here: the
/// UI draws it, and this layer only carries it from a step's first run to
/// its undo and redo.
abstract interface class WaitWindow {}

/// What an undo or a redo stands behind: the [window] its step's first run
/// stood behind, and what it works out [ahead] of it off the UI thread
/// ([WorksAheadCommand]), null when nothing.
typedef StepBehind = ({WaitWindow window, WorkAhead? ahead});

/// Whether a step that lands on [blocks] stands behind the app's wait
/// window: only when they are more than one. [blocks] are what the step's
/// own door names, each as often as it likes — a block named twice is one.
///
/// 🗣️F-566 (유저 2026-11-05): 「진행창 뜨고 안뜨고는 tvp기준으로 정함」 ·
/// 「변형도 셀 하나만 할때는 진행창안띄움. 다른 블록에 걸쳐서 변형할때만
/// 진행창뜸. 그러니 우리도 색변환이던 뭐던 여러행이나 여러 블록. 즉 대상이
/// 여러블록일때만 띄우도록. 대상이 한 블록이면 안띄움」. ONE answer for every
/// heavy door: a door says what it reaches, never whether it waits.
/// ↩️F-551-Q1 (유저 2026-11-04: 「전부 늘 띄운다」) stood every press
/// behind it, a cel's own too.
bool reachesManyBlocks(Iterable<Object> blocks) {
  Object? first;
  for (final block in blocks) {
    if (first == null) {
      first = block;
    } else if (block != first) {
      return true;
    }
  }
  return false;
}

/// The drawings [rows] hold, each a block to a verb that takes rows whole —
/// a row, or a cut's rows — for [reachesManyBlocks].
Iterable<Object> drawingsOf(Iterable<Layer> rows) sync* {
  for (final row in rows) {
    for (final cel in row.frames) {
      yield (row.id, cel.id);
    }
  }
}

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
