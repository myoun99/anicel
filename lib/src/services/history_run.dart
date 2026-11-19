import 'history_manager.dart';

/// The steps one HOLD writes — a photo held on a sheet (I-97), each grab
/// of it a step: undo takes them back one at a time while it is held
/// ([takeBack]), and the hold is ONE entry ([end]).
///
/// 🗣️The transform tool's law (유저 2026-09-20: 「변형도구 사용시 변형에 대한
/// 조작마다 언두로 기록 … 확정하면 변형 하나로서의 언두만 작동」), for every
/// hold since F-377 (유저 2026-10-17: 「변형 상태는 모두 기본적으로 그걸
/// 따르도록. 텍스트 변형이든 뭐든」). The box keeps its operations as values
/// and writes once; a hold writes each step as it is made, so the cel shows
/// it and a save keeps it — into ONE line from its first step, put up when
/// it lets go ([HistoryGestures.line], 🗣️a-gesture-at-the-history-cap-
/// does-not-fold-Q1: 「동작하나에 1줄」).
///
/// ⚠️A RUN IS ONLY EVER ITS OWN STEPS. A hold lasts across many events,
/// and the hand may write something else meanwhile — a key, a menu. That
/// breaks the run: what it wrote so far goes up as one entry, under what
/// was written, and the next step of the hold begins a run again. So a
/// take-back never reaches a step that is not the hold's.
final class HistoryRun {
  HistoryRun(this._gestures, this._description);

  final HistoryGestures _gestures;

  /// What the hold's entry is called.
  final String _description;

  /// The run under way; null with none.
  HistoryLine? _line;

  /// How many steps each write put into the line, newest last — what
  /// [takeBack] takes a write at a time.
  final List<int> _writes = [];

  /// Begins a run here — what is taken in hand. A run under way ends.
  void begin() {
    end();
    _line = _gestures.line(_description);
  }

  /// Writes one step of the hold through [write] — a run begun again where
  /// something else was written since the last.
  void write(void Function() write) {
    final line = _line;
    if (line == null) {
      write();
      return;
    }
    if (line.written == 0) {
      _writes.clear();
    }
    final wrote = line.write(write);
    if (wrote > 0) {
      _writes.add(wrote);
    }
  }

  /// Takes ONE step another hand filed at the run's asking in as the run's
  /// own — the cel a text's press asked for, which the door files as the
  /// press comes up (`onAutoFrameSettled`), long before the text is set to
  /// be [write]n with it.
  ///
  /// ⛔Only while it is all that was filed: with anything else filed
  /// meanwhile it stays as it is ([HistoryLine.adopt]).
  void adopt() {
    if (_line?.adopt() ?? false) {
      _writes
        ..clear()
        ..add(1);
    }
  }

  /// Whether undo has a step of the run to take back ([takeBack]).
  bool get canTakeBack => (_line?.written ?? 0) > 0 && _writes.isNotEmpty;

  /// Takes the run's last step back — undone, and no redo's: a step the
  /// hand took back inside its hold is not one it made
  /// ([HistoryLine.takeBack]).
  void takeBack() {
    if (canTakeBack) {
      _line!.takeBack(_writes.removeLast());
    }
  }

  /// Ends the run: what it holds goes up as ONE entry.
  void end() {
    _line?.close();
    _line = null;
    _writes.clear();
  }
}
