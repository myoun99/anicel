import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/command.dart';

/// A step of several commands works out ahead what its children do, in the
/// order the step runs them — a 겸용 변경's resize comes first, its undo
/// would come last — each child a share of the window's count.
void main() {
  final log = <String>[];

  setUp(log.clear);

  WorksAheadCommand step(List<Command> commands) =>
      oneStepOf('step', commands)! as WorksAheadCommand;

  test('in the order the step runs them, each a share of the count', () async {
    final ahead = step([
      _Ahead('first', log),
      _Plain(),
      _Ahead('second', log),
    ]).workAhead(undo: false);
    final reports = <double>[];
    await ahead!.run(reports.add);
    expect(log, ['first', 'second']);
    expect(reports, [0.25, 0.5, 0.75, 1.0]);
  });

  test('an undo runs them the other way', () async {
    final ahead = step([
      _Ahead('first', log, undoToo: true),
      _Ahead('second', log, undoToo: true),
    ]).workAhead(undo: true);
    await ahead!.run((_) {});
    expect(log, ['second', 'first']);
  });

  test('behind the window of the first child it runs', () {
    WallMove? wallOf(bool undo) => step([
      _Ahead('first', log, undoToo: true, wall: WallMove.pasteboard),
      _Ahead('second', log, undoToo: true),
    ]).workAhead(undo: undo)?.wall;
    expect(wallOf(false), WallMove.pasteboard);
    expect(wallOf(true), WallMove.canvasSize);
  });

  test('nothing ahead where no child has any', () {
    expect(
      step([_Ahead('first', log), _Plain()]).workAhead(undo: true),
      isNull,
    );
    expect(step([_Plain(), _Plain()]).workAhead(undo: false), isNull);
  });
}

class _Plain implements Command {
  @override
  String get description => 'plain';

  @override
  void execute() {}

  @override
  void undo() {}
}

/// Works out ahead for its run — and, with [undoToo], for its undo — behind
/// the window of [wall], saying it has, half then all.
class _Ahead extends _Plain implements WorksAheadCommand {
  _Ahead(
    this.name,
    this.log, {
    this.undoToo = false,
    this.wall = WallMove.canvasSize,
  });

  final String name;
  final List<String> log;
  final bool undoToo;
  final WallMove wall;

  @override
  WorkAhead? workAhead({required bool undo}) => undo && !undoToo
      ? null
      : (
          wall: wall,
          run: (report) async {
            log.add(name);
            report(0.5);
            report(1);
          },
        );
}
