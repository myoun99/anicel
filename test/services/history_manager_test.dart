import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_manager.dart';

void main() {
  _pressureTests();
  _foldTests();
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

void _foldTests() {
  // swipe-is-one-undo: a gesture that writes across many events — the
  // rail's column swipe — folds what it wrote at the release.
  group('foldSince', () {
    test('folds everything pushed since the mark into ONE step, and only '
        'that', () {
      final history = HistoryManager();
      final earlier = _FakeCommand();
      history.execute(earlier);
      final mark = history.mark;
      final run = [_FakeCommand(), _FakeCommand(), _FakeCommand()];
      run.forEach(history.execute);

      history.foldSince(mark, 'Sweep');

      expect(history.undoCount, 2);
      expect(
        [for (final command in run) command.executeCount],
        [1, 1, 1],
        reason: 'folding re-files what already ran — it runs nothing again',
      );
      history.undo();
      expect([for (final command in run) command.undoCount], [1, 1, 1]);
      expect(earlier.undoCount, 0, reason: 'the step before the mark');
    });

    test('a run an undo broke into is left as it was', () {
      final history = HistoryManager();
      final mark = history.mark;
      for (var i = 0; i < 3; i += 1) {
        history.execute(_FakeCommand());
      }
      history.undo();

      history.foldSince(mark, 'Sweep');

      expect(history.undoCount, 2, reason: 'nothing folded');
    });

    test('a run the deep end cut into is left as it was — a fold would take '
        'half of the gesture', () {
      final history = HistoryManager(maxEntries: 4);
      history.execute(_FakeCommand());
      history.execute(_FakeCommand());
      final mark = history.mark;
      final run = [_FakeCommand(), _FakeCommand(), _FakeCommand()];
      run.forEach(history.execute);
      expect(history.undoCount, 4, reason: 'the premise: the stack trimmed');

      history.foldSince(mark, 'Sweep');
      history.undo();

      expect(
        [for (final command in run) command.undoCount],
        [0, 0, 1],
        reason: 'one undo is still one entry — not the last two of three',
      );
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
