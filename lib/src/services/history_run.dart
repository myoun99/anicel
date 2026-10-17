import 'history_manager.dart';

/// The steps one HOLD writes — a photo held on a sheet (I-97), each grab
/// of it a step: undo takes them back one at a time while it is held
/// ([takeBack]), and once it is let go they are ONE step ([end]).
///
/// 🗣️The transform tool's law (유저 2026-09-20: 「변형도구 사용시 변형에 대한
/// 조작마다 언두로 기록 … 확정하면 변형 하나로서의 언두만 작동」), for every
/// hold since F-377 (유저 2026-10-17: 「변형 상태는 모두 기본적으로 그걸
/// 따르도록. 텍스트 변형이든 뭐든」). The box keeps its operations as values
/// and writes once; a hold writes each step as it is made, so the cel shows
/// it and a save keeps it — and folds them when it lets go, as a gesture
/// does ([HistoryGestures.foldSince]).
///
/// ⚠️A RUN IS ONLY EVER ITS OWN STEPS. A hold lasts across many events,
/// and the hand may write something else meanwhile — a key, a menu. That
/// breaks the run: what it wrote so far stays as it is, and the next step
/// of the hold begins a run again. So neither a take-back nor the fold can
/// reach a step that is not the hold's.
final class HistoryRun {
  HistoryRun(this._gestures);

  final HistoryGestures _gestures;

  /// Where the run began; null with none under way.
  HistoryMark? _since;

  /// How many entries the run's own steps pushed.
  int _own = 0;

  /// Begins a run here — what is taken in hand.
  void begin() {
    _since = _gestures.mark;
    _own = 0;
  }

  /// Writes one step of the hold through [write] — a run begun again where
  /// something else was written since the last.
  void write(void Function() write) {
    if (_since != null && !_whole) {
      begin();
    }
    final before = _gestures.mark.pushed;
    write();
    _own += _gestures.mark.pushed - before;
  }

  /// Counts ONE step another hand filed at the run's asking as the run's
  /// own — the cel a text's press asked for, which the door files as the
  /// press comes up (`onAutoFrameSettled`), long before the text is set to
  /// be [write]n with it.
  ///
  /// ⛔It stays the run's only while it is all that was filed: anything
  /// else filed meanwhile leaves the run not whole, and its next step
  /// begins it again ([write]).
  void adopt() => _own += 1;

  /// Whether a run is under way and nothing but its own steps were pushed
  /// since it began.
  bool get _whole {
    final since = _since;
    return since != null && _gestures.mark.pushed - since.pushed == _own;
  }

  /// Whether undo has a step of the run to take back ([takeBack]).
  bool get canTakeBack => _whole && _gestures.keepsSince(_since!);

  /// Takes the run's last step back — undone, and no redo's: a step the
  /// hand took back inside its hold is not one it made
  /// ([HistoryGestures.retractSince]).
  void takeBack() {
    if (canTakeBack) {
      _gestures.retractSince(_since!);
    }
  }

  /// Ends the run: its steps fold into ONE called [description], where it
  /// is still whole.
  void end(String description) {
    final since = _since;
    final whole = _whole;
    _since = null;
    _own = 0;
    if (since != null && whole) {
      _gestures.foldSince(since, description);
    }
  }
}
