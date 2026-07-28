import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_manager.dart';

void main() {
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
