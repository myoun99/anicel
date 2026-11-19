import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/history_run.dart';
import 'package:anicel/src/services/history_step_scope.dart';

void main() {
  _pressureTests();
  _lineTests();
  _runTests();
  group('HistoryManager', () {
    test('starts empty', () {
      final historyManager = HistoryManager();

      expect(historyManager.canUndo, isFalse);
      expect(historyManager.canRedo, isFalse);
      expect(historyManager.undoCount, 0);
      expect(historyManager.redoCount, 0);
    });

    test('executes command', () {
      final historyManager = HistoryManager();
      final command = _FakeCommand();

      historyManager.execute(command);

      expect(command.executeCount, 1);
      expect(command.undoCount, 0);
      expect(historyManager.canUndo, isTrue);
      expect(historyManager.canRedo, isFalse);
      expect(historyManager.undoCount, 1);
      expect(historyManager.redoCount, 0);
    });

    test('undoes command', () {
      final historyManager = HistoryManager();
      final command = _FakeCommand();

      historyManager.execute(command);
      historyManager.undo();

      expect(command.executeCount, 1);
      expect(command.undoCount, 1);
      expect(historyManager.canUndo, isFalse);
      expect(historyManager.canRedo, isTrue);
      expect(historyManager.undoCount, 0);
      expect(historyManager.redoCount, 1);
    });

    test('redoes command', () {
      final historyManager = HistoryManager();
      final command = _FakeCommand();

      historyManager.execute(command);
      historyManager.undo();
      historyManager.redo();

      expect(command.executeCount, 2);
      expect(command.undoCount, 1);
      expect(historyManager.canUndo, isTrue);
      expect(historyManager.canRedo, isFalse);
      expect(historyManager.undoCount, 1);
      expect(historyManager.redoCount, 0);
    });

    test('execute clears redo stack', () {
      final historyManager = HistoryManager();
      final commandA = _FakeCommand(description: 'A');
      final commandB = _FakeCommand(description: 'B');

      historyManager.execute(commandA);
      historyManager.undo();
      historyManager.execute(commandB);

      expect(historyManager.canUndo, isTrue);
      expect(historyManager.canRedo, isFalse);
      expect(historyManager.undoCount, 1);
      expect(historyManager.redoCount, 0);
      expect(commandA.executeCount, 1);
      expect(commandA.undoCount, 1);
      expect(commandB.executeCount, 1);
    });

    test('undo with empty stack throws', () {
      final historyManager = HistoryManager();

      expect(historyManager.undo, throwsStateError);
    });

    test('redo with empty stack throws', () {
      final historyManager = HistoryManager();

      expect(historyManager.redo, throwsStateError);
    });

    test('clear empties both stacks', () {
      final historyManager = HistoryManager();
      final command = _FakeCommand();

      historyManager.execute(command);
      historyManager.undo();
      historyManager.clear();

      expect(historyManager.canUndo, isFalse);
      expect(historyManager.canRedo, isFalse);
      expect(historyManager.undoCount, 0);
      expect(historyManager.redoCount, 0);
    });

    test('notifies on every stack change (brush strokes execute here with '
        'no session notify — the undo buttons subscribe directly)', () {
      final historyManager = HistoryManager();
      var notifies = 0;
      historyManager.addListener(() => notifies += 1);

      historyManager.execute(_FakeCommand());
      expect(notifies, 1);
      historyManager.undo();
      expect(notifies, 2);
      historyManager.redo();
      expect(notifies, 3);
      historyManager.clear();
      expect(notifies, 4);
    });
  });
}

/// 🚨THE OS WARNING REACHES THE UNDO STACK (H-crash, 유저 2026-08-27: 「세번째,
/// 네번째 변형쯤에서 말없이 앱 종료됨」 — iPhone).
///
/// `didHaveMemoryPressure` reached `BrushFrameStore` and stopped there. The
/// undo stack sat beside it holding up to 512 MB of full-canvas surface
/// snapshots — a MOVE retains a PRE and a POST per confirm — and heard
/// nothing. On iOS that warning is the last thing before the kill.
void _pressureTests() {
  test('pressure drops retained snapshots, and the newest always survives',
      () async {
    final history = HistoryManager();
    for (var i = 0; i < 6; i++) {
      history.execute(_HeavyCommand(bytes: 40 * 1024 * 1024)); // 240 MB
    }
    expect(history.undoCount, 6, reason: 'under the 512 MB budget, all stay');

    history.respondToMemoryPressure();
    // ⚠️The relief is a spill pass now, not this line: these entries hold
    // nothing that can move, so the pass stands down and sheds — but it
    // does it from a microtask.
    await history.drainSpilling();

    expect(
      history.retainedBytes,
      lessThanOrEqualTo(HistoryManager.retainedByteBudgetUnderPressure),
      reason: 'the point of the signal',
    );
    expect(
      history.undoCount,
      greaterThanOrEqualTo(1),
      reason: '⛔pressure must not cost you the undo you are about to press',
    );
  });

  test('pressure only ever LOWERS — a second warning drops nothing more',
      () async {
    final history = HistoryManager();
    history.execute(_HeavyCommand(bytes: 10 * 1024 * 1024));
    history.respondToMemoryPressure();
    await history.drainSpilling();
    final after = history.undoCount;
    history.respondToMemoryPressure();
    await history.drainSpilling();
    expect(history.undoCount, after);
  });
}

void _lineTests() {
  // 🗣️a-gesture-at-the-history-cap-does-not-fold-Q1 (유저 2026-11-19:
  // 「동작하나에 1줄」): a gesture that writes across many events — the
  // rail's column swipe — is ONE entry from its first step.
  group('gestures.open', () {
    test('every step filed while a line is open goes into it, and the line '
        'goes up as ONE entry when it closes', () {
      final history = HistoryManager();
      final earlier = _FakeCommand();
      history.execute(earlier);
      final line = history.gestures.open('Sweep');
      final run = [_FakeCommand(), _FakeCommand(), _FakeCommand()];
      run.forEach(history.execute);

      expect(history.undoCount, 1, reason: 'nothing on the stack yet');
      expect(line.written, 3);
      line.close();

      expect(history.undoCount, 2);
      expect(
        [for (final command in run) command.executeCount],
        [1, 1, 1],
        reason: 'put up as it ran — it runs nothing again',
      );
      history.undo();
      expect([for (final command in run) command.undoCount], [1, 1, 1]);
      expect(earlier.undoCount, 0, reason: 'the step before the line');
    });

    // ↩️Each step went on the stack and the release folded them: at the
    // cap the fold lost the gesture's start, and every step pushed an old
    // entry out (서피스 실측 11-19 — 24 stamps, 24 undos, 24 entries gone).
    test('at the depth cap a gesture costs ONE old entry, not one a step', () {
      final history = HistoryManager(maxEntries: 4);
      final earlier = [for (var i = 0; i < 4; i += 1) _FakeCommand()];
      earlier.forEach(history.execute);
      final line = history.gestures.open('Sweep');
      final run = [for (var i = 0; i < 6; i += 1) _FakeCommand()];
      run.forEach(history.execute);
      line.close();

      expect(history.undoCount, 4);
      history.undo();
      expect(
        [for (final command in run) command.undoCount],
        [1, 1, 1, 1, 1, 1],
      );
      for (var i = 0; i < 3; i += 1) {
        history.undo();
      }
      expect(
        [for (final command in earlier) command.undoCount],
        [0, 1, 1, 1],
        reason: 'only the oldest fell off for it',
      );
    });

    test('a line takes its newest steps back and forgets them — no redo', () {
      final history = HistoryManager();
      final line = history.gestures.open('Sweep');
      final run = [_FakeCommand(), _FakeCommand(), _FakeCommand()];
      run.forEach(history.execute);

      line.takeBack(2);

      expect([for (final command in run) command.undoCount], [0, 1, 1]);
      expect(line.written, 1);
      expect(history.canRedo, isFalse, reason: 'taken back, not undone');
      line.close();
      expect(history.undoCount, 1);
      history.undo();
      expect([for (final command in run) command.undoCount], [1, 1, 1]);
    });

    test('an undo while a line is open takes back what it holds, whole — '
        'and the steps after it are an entry of their own', () {
      final history = HistoryManager();
      final line = history.gestures.open('Sweep');
      final before = [_FakeCommand(), _FakeCommand()];
      before.forEach(history.execute);
      expect(history.canUndo, isTrue, reason: 'the line is an undo');

      history.undo();
      expect([for (final command in before) command.undoCount], [1, 1]);

      final after = [_FakeCommand(), _FakeCommand()];
      after.forEach(history.execute);
      line.close();
      expect(history.undoCount, 1);
      expect(
        history.canRedo,
        isFalse,
        reason: 'the line\'s first step after it is an edit',
      );
      history.undo();
      expect([for (final command in after) command.undoCount], [1, 1]);
    });

    test('putUp puts what a line holds up now, and the line goes on into an '
        'entry of its own', () {
      final history = HistoryManager();
      final line = history.gestures.open('Sweep');
      history.execute(_FakeCommand());
      history.gestures.putUp();
      expect(history.undoCount, 1);
      history.execute(_FakeCommand());
      line.close();
      expect(history.undoCount, 2);
    });

    test('a line that took nothing puts nothing up, and a closed line takes '
        'nothing more', () {
      final history = HistoryManager();
      history.gestures.open('Sweep').close();
      expect(history.canUndo, isFalse);

      history.execute(_FakeCommand());
      history.execute(_FakeCommand());
      expect(history.undoCount, 2, reason: 'entries of their own');
    });

    test('the bytes a line holds are counted, and let go with the history', () {
      final history = HistoryManager();
      final line = history.gestures.open('Sweep');
      history.execute(_HeavyCommand(bytes: 1024));
      expect(history.retainedBytes, 1024);

      history.clear();
      expect(history.retainedBytes, 0);
      expect(history.canUndo, isFalse);
      line.close();
      expect(history.undoCount, 0, reason: 'what was let go stays gone');
    });

    // F-343: what a step made that its own undo does not take back is the
    // step scope's, handed back by that step's undo.
    test('what each step of a line made is its entry\'s once it is up — '
        'the one undo hands all of it back', () {
      final history = HistoryManager();
      final scope = _Scope();
      history.scope = scope;
      final line = history.gestures.open('Sweep');
      history
        ..execute(_FakeCommand())
        ..execute(_FakeCommand());
      line.close();

      history.undo();

      expect(scope.handedBack, [
        [1, 2],
      ]);
    });

    test('a step a line takes back hands back what it made', () {
      final history = HistoryManager();
      final scope = _Scope();
      history.scope = scope;
      final line = history.gestures.open('Sweep');
      history
        ..execute(_FakeCommand())
        ..execute(_FakeCommand());

      line.takeBack(1);

      expect(scope.handedBack, [
        [2],
      ]);
      line.close();
      history.undo();
      expect(scope.handedBack.last, [1], reason: 'and the one left, up');
    });
  });
}

/// A step scope that says each step it runs made the next number, and
/// keeps what each undo handed back.
class _Scope implements HistoryStepScope {
  int _made = 0;
  final List<List<Object>> handedBack = [];

  @override
  Object? execute(void Function() write) {
    write();
    return _made += 1;
  }

  @override
  void undo(void Function() write, List<Object> made) {
    write();
    handedBack.add(made);
  }

  @override
  Object? redo(void Function() write) => execute(write);
}

void _runTests() {
  // F-377 (유저 2026-10-17): 「변형 상태는 모두 기본적으로 그걸 따르도록」
  // — a hold's steps take undo one at a time while it is held, and are ONE
  // entry — from the first (🗣️a-gesture-at-the-history-cap-does-not-fold
  // -Q1, 「동작하나에 1줄」).
  group('HistoryRun', () {
    test('a hold\'s steps take undo one at a time — and no redo — and are '
        'ONE entry when it ends', () {
      final history = HistoryManager();
      final earlier = _FakeCommand();
      history.execute(earlier);
      final run = HistoryRun(history.gestures, 'Hold')..begin();
      final steps = [_FakeCommand(), _FakeCommand(), _FakeCommand()];
      for (final step in steps) {
        run.write(() => history.execute(step));
      }

      expect(run.canTakeBack, isTrue);
      run.takeBack();
      expect([for (final step in steps) step.undoCount], [0, 0, 1]);
      expect(history.canRedo, isFalse, reason: 'taken back, not undone');

      run.end();
      expect(history.undoCount, 2, reason: 'the step before, and the hold');
      history.undo();
      expect(
        [for (final step in steps) step.undoCount],
        [1, 1, 1],
        reason: 'one undo takes the hold back whole',
      );
      expect(earlier.undoCount, 0);
    });

    test('a hold\'s steps never stand on the stack while it is held — at the '
        'depth cap it costs one old entry', () {
      final history = HistoryManager(maxEntries: 4);
      final earlier = [for (var i = 0; i < 4; i += 1) _FakeCommand()];
      earlier.forEach(history.execute);
      final run = HistoryRun(history.gestures, 'Hold')..begin();
      for (var i = 0; i < 3; i += 1) {
        run.write(() => history.execute(_FakeCommand()));
        expect(history.undoCount, 4);
      }

      run.end();
      for (var i = 0; i < 4; i += 1) {
        history.undo();
      }
      expect(
        [for (final command in earlier) command.undoCount],
        [0, 1, 1, 1],
        reason: 'the hold, then the three before it: the oldest alone fell',
      );
    });

    test('a step written past the hold breaks its run: the take-back and '
        'the entry reach the hold\'s own steps alone', () {
      final history = HistoryManager();
      final run = HistoryRun(history.gestures, 'Hold')..begin();
      final first = _FakeCommand();
      run.write(() => history.execute(first));
      final elsewhere = _FakeCommand();
      history.execute(elsewhere);

      expect(run.canTakeBack, isFalse);
      run.takeBack();
      expect(elsewhere.undoCount, 0, reason: 'not the hold\'s to take');

      final after = [_FakeCommand(), _FakeCommand()];
      for (final step in after) {
        run.write(() => history.execute(step));
      }
      run.end();

      expect(
        history.undoCount,
        3,
        reason: 'the step before the break, the one written past it, and '
            'what the hold wrote after it',
      );
      history.undo();
      expect([for (final step in after) step.undoCount], [1, 1]);
      expect(elsewhere.undoCount, 0);
      history.undo();
      expect(elsewhere.undoCount, 1, reason: 'under the hold\'s, as written');
    });

    test('a hold that wrote nothing takes nothing back and puts nothing up',
        () {
      final history = HistoryManager();
      final earlier = _FakeCommand();
      history.execute(earlier);
      final run = HistoryRun(history.gestures, 'Hold')..begin();

      expect(run.canTakeBack, isFalse);
      run.takeBack();
      run.end();

      expect(earlier.undoCount, 0);
      expect(history.undoCount, 1);
    });

    test('a step another hand filed at the run\'s asking is the run\'s own '
        'once adopted — one entry with what the run writes', () {
      final history = HistoryManager();
      final run = HistoryRun(history.gestures, 'Hold')..begin();
      final asked = _FakeCommand();
      history.execute(asked);
      final own = _FakeCommand();

      run
        ..adopt()
        ..write(() => history.execute(own))
        ..end();

      expect(history.undoCount, 1, reason: 'the two in one');
      history.undo();
      expect([asked.undoCount, own.undoCount], [1, 1]);
    });

    test('⛔adopted, a step is the run\'s only while it is all that was '
        'filed: with another beside it, the run begins again', () {
      final history = HistoryManager();
      final run = HistoryRun(history.gestures, 'Hold')..begin();
      final asked = _FakeCommand();
      history.execute(asked);
      final elsewhere = _FakeCommand();
      history.execute(elsewhere);
      final own = _FakeCommand();

      run
        ..adopt()
        ..write(() => history.execute(own))
        ..end();

      expect(history.undoCount, 3);
      history.undo();
      expect([asked.undoCount, elsewhere.undoCount], [0, 0]);
    });

    test('⛔a step filed since the run began and undone is not there to '
        'adopt — what stands on top is older than the run', () {
      final history = HistoryManager();
      final earlier = _FakeCommand();
      history.execute(earlier);
      final run = HistoryRun(history.gestures, 'Hold')..begin();
      history
        ..execute(_FakeCommand())
        ..undo();

      run.adopt();
      expect(run.canTakeBack, isFalse, reason: 'nothing of the run\'s');
      run.end();

      expect(history.undoCount, 1, reason: 'the step before the run');
      history.undo();
      expect(earlier.undoCount, 1, reason: 'its own entry still');
    });

    test('a hold begun again puts up what the last one held: two holds, '
        'two entries', () {
      final history = HistoryManager();
      final run = HistoryRun(history.gestures, 'Hold')..begin();
      final first = _FakeCommand();
      run.write(() => history.execute(first));

      run.begin();
      expect(
        (history.undoCount, history.gestures.heldSteps),
        (1, 0),
        reason: 'the first up as the hold begins again',
      );
      final second = _FakeCommand();
      run.write(() => history.execute(second));

      expect(
        (history.undoCount, history.gestures.heldSteps),
        (1, 1),
        reason: 'the first up, the second held',
      );
      run.takeBack();
      expect([first.undoCount, second.undoCount], [0, 1]);
      expect(run.canTakeBack, isFalse, reason: 'the first is not this one');
    });
  });
}

class _HeavyCommand implements Command, RetainedBytesCommand {
  _HeavyCommand({required this.bytes});

  final int bytes;

  @override
  int estimatedRetainedBytes({required bool undone}) => bytes;

  @override
  String get description => 'Heavy';

  @override
  void execute() {}

  @override
  void undo() {}
}

class _FakeCommand implements Command {
  _FakeCommand({this.description = 'Fake command'});

  @override
  final String description;

  int executeCount = 0;
  int undoCount = 0;

  @override
  void execute() {
    executeCount += 1;
  }

  @override
  void undo() {
    undoCount += 1;
  }
}
