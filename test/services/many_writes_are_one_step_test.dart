import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「These writes are one step」 has ONE answer, [oneStepOf]: nothing when
/// there are none, the command itself when there is one, a composite when
/// there are several (one-step-of-many-commands, 2026-09-29 — sixteen sites
/// had written that fold out by hand, and a dozen more wrapped even a lone
/// write). The composite's constructor is private to that answer, so no
/// site can write a copy of it; these pin the answer itself.
class _Write implements Command {
  _Write(this.log, this.name);

  final List<String> log;
  final String name;

  @override
  String get description => name;

  @override
  void execute() => log.add('do $name');

  @override
  void undo() => log.add('undo $name');
}

void main() {
  test('no writes are no step — nothing runs, nothing is filed, nobody '
      'is told', () {
    final history = HistoryManager();
    var heard = 0;
    history.addListener(() => heard += 1);

    history.executeAsOneStep('nothing', const []);
    history.runAsOneStep('nothing either', () {});

    expect(oneStepOf('nothing', const []), isNull);
    expect(history.undoCount, 0);
    expect(heard, 0);
  });

  test('one write is filed as itself, not wrapped', () {
    final log = <String>[];
    final only = _Write(log, 'a');

    expect(identical(oneStepOf('one', [only]), only), isTrue);

    final history = HistoryManager()..executeAsOneStep('one', [only]);
    expect(log, ['do a']);
    expect(history.undoCount, 1);
    history.undo();
    expect(log, ['do a', 'undo a']);
  });

  test('several writes run in order and come back as ONE undo, in '
      'reverse', () {
    final log = <String>[];
    final history = HistoryManager()
      ..executeAsOneStep('two', [_Write(log, 'a'), _Write(log, 'b')]);

    expect(log, ['do a', 'do b']);
    expect(history.undoCount, 1);
    history.undo();
    expect(log, ['do a', 'do b', 'undo b', 'undo a']);
    expect(history.undoCount, 0);
  });

  test('a grouped body is filed by the same answer', () {
    final log = <String>[];
    final history = HistoryManager();

    history.runAsOneStep('two', () {
      history
        ..execute(_Write(log, 'a'))
        ..execute(_Write(log, 'b'));
    });

    expect(history.undoCount, 1);
    history.undo();
    expect(log, ['do a', 'do b', 'undo b', 'undo a']);
  });
}
