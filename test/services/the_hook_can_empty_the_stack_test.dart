import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_manager.dart';

/// 🚨THE HOOK CAN EMPTY THE STACK THE PRESS WAS ABOUT.
///
/// `onBeforeUndoRedo` exists so the selection layer can adopt a PENDING
/// move into history before undo touches the stacks (R16-①) — and adopting
/// means `execute()`, which pushes to undo and CLEARS redo. So by the time
/// the hook returns, the stack this step was about can be empty, and
/// popping it then is a range error on a press the user is allowed to
/// make.
///
/// The guard that catches this reads as a redundant second check, which is
/// exactly why it needs a test: deleting it broke nothing in the suite
/// before this file existed.
void main() {
  test('a hook that adopts a command mid-REDO leaves the press harmless', () {
    final history = HistoryManager();
    final first = _FakeCommand();
    history.execute(first);
    history.undo();
    expect(history.canRedo, isTrue, reason: 'the premise: there is a redo');

    // The selection layer's adoption: a fresh command lands in history,
    // which clears the redo stack under the press already in flight.
    var adopted = false;
    history.onBeforeUndoRedo = () {
      if (adopted) {
        return;
      }
      adopted = true;
      history.execute(_FakeCommand());
    };

    expect(
      history.redo,
      returnsNormally,
      reason:
          'the redo stack the press was about is gone — the press does '
          'nothing rather than throwing a range error',
    );
    expect(history.canRedo, isFalse);
  });

  test('a hook that adopts a command mid-UNDO leaves the press harmless', () {
    final history = HistoryManager();
    history.execute(_FakeCommand());

    var adopted = false;
    history.onBeforeUndoRedo = () {
      if (adopted) {
        return;
      }
      adopted = true;
      // Clearing is the shape that matters: whatever the hook did, the
      // stack this step was about can be empty when it returns.
      history.clear();
    };

    expect(history.undo, returnsNormally);
    expect(history.canUndo, isFalse);
  });

  test('an EMPTY stack still throws on entry — that is a caller asking for '
      'something impossible, not a hook doing its job', () {
    final history = HistoryManager();
    expect(history.undo, throwsStateError);
    expect(history.redo, throwsStateError);
  });
}

class _FakeCommand implements Command {
  @override
  String get description => 'Fake command';

  @override
  void execute() {}

  @override
  void undo() {}
}
