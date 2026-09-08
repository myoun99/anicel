import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/row_sweep.dart';

/// THE ROW SWEEP — the envelope three legend actions share (the timesheet
/// flag, the fill references, the layer marks).
///
/// It was written by folding those three copies together, and its whole
/// value is in the two things every copy had to remember and one of them
/// could forget: the GAP GUARD, and that an empty sweep writes no history
/// entry. Nothing named the function itself — every pin was a legend
/// button three layers up, so a sweep that lost the guard would have gone
/// red as "the toolbar threw" rather than as "the envelope changed".
///
/// ⚠️The eligibility predicate is the NULLABLE RETURN of [commandFor], not
/// a second filter beside it. That is what makes "which rows" and "what to
/// do to them" one answer, so they cannot disagree — pinned below by a
/// sweep whose rows list is longer than the commands it produces.
void main() {
  const trackId = TrackId('sweep-track');

  Cut cut(String id, int duration, {int leadingGap = 0}) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    leadingGapFrames: leadingGap,
    canvasSize: const CanvasSize(width: 320, height: 180),
    layers: [
      Layer(id: LayerId('$id-a'), name: 'A', frames: const [], timeline: {}),
      Layer(id: LayerId('$id-b'), name: 'B', frames: const [], timeline: {}),
    ],
  );

  /// cut-1 covers [0,8); a FOUR-FRAME GAP at [8,12); cut-2 covers [12,18).
  EditorSessionManager session() {
    final manager = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('sweep'),
        name: 'Sweep',
        createdAt: DateTime.utc(2026, 9, 8),
        tracks: [
          Track(
            id: trackId,
            name: 'Video',
            cuts: [cut('cut-1', 8), cut('cut-2', 6, leadingGap: 4)],
          ),
        ],
      ),
    );
    addTearDown(manager.dispose);
    return manager;
  }

  test('the GAP GUARD: parked with no active cut the sweep stands down — it '
      'never asks for rows, and writes no history entry', () {
    final s = session();
    s.selectGlobalFrame(10);
    expect(
      s.activeCutOrNull,
      isNull,
      reason: 'fixture premise: frame 10 is the gap between the two cuts',
    );
    final undoBefore = s.historyManager.undoCount;
    var asked = 0;

    final swept = sweepActiveCutRows(
      project: s,
      description: 'Sweep in a gap',
      rows: (cut) {
        asked += 1;
        return cut.layers;
      },
      commandFor: (cut, layer) => _Mark(layer.id),
    );

    expect(swept, isFalse);
    expect(
      asked,
      0,
      reason: 'the guard stands down BEFORE the row list is built — a sweep '
          'that got as far as asking would throw on `requireActiveCut`',
    );
    expect(s.historyManager.undoCount, undoBefore);
  });

  test('an EMPTY sweep writes no history entry and answers false — that is '
      'how the caller knows it has nothing to announce', () {
    final s = session();
    final undoBefore = s.historyManager.undoCount;

    final swept = sweepActiveCutRows(
      project: s,
      description: 'Nothing is eligible',
      rows: (cut) => cut.layers,
      commandFor: (cut, layer) => null,
    );

    expect(swept, isFalse);
    expect(
      s.historyManager.undoCount,
      undoBefore,
      reason: 'an entry that undoes nothing is a phantom step on the stack',
    );
  });

  test('the nullable command IS the eligibility predicate: the rows it '
      'refuses are simply not swept', () {
    final s = session();
    final ineligible = s.requireActiveCut.layers.last.id;
    final ran = <LayerId>[];

    final swept = sweepActiveCutRows(
      project: s,
      description: 'Sweep the eligible half',
      rows: (cut) => cut.layers,
      commandFor: (cut, layer) =>
          layer.id == ineligible ? null : _Mark(layer.id, onRun: ran.add),
    );

    expect(swept, isTrue);
    expect(
      ran,
      [s.requireActiveCut.layers.first.id],
      reason: 'the filter and the command are one answer, so a row the '
          'command declines is a row the filter dropped',
    );
  });

  test('every command of one sweep lands as ONE undo entry, and one undo '
      'takes all of them back', () {
    final s = session();
    final undoBefore = s.historyManager.undoCount;
    final live = <LayerId>{};

    final swept = sweepActiveCutRows(
      project: s,
      description: 'Mark every row',
      rows: (cut) => cut.layers,
      commandFor: (cut, layer) =>
          _Mark(layer.id, onRun: live.add, onUndo: live.remove),
    );

    expect(swept, isTrue);
    expect(live, hasLength(2), reason: 'both rows were swept');
    expect(
      s.historyManager.undoCount,
      undoBefore + 1,
      reason: 'one legend action is one undo step, not one per row',
    );

    s.historyManager.undo();
    expect(
      live,
      isEmpty,
      reason: 'a single undo reverses the whole sweep — the composite is '
          'what makes the bulk action feel like one action',
    );
    expect(s.historyManager.undoCount, undoBefore);
  });
}

/// A command that does nothing but say it ran, so the sweep's own shape is
/// what the assertions above can see.
class _Mark implements Command {
  _Mark(this.layerId, {this.onRun, this.onUndo});

  final LayerId layerId;
  final void Function(LayerId id)? onRun;
  final void Function(LayerId id)? onUndo;

  @override
  String get description => 'mark $layerId';

  @override
  void execute() => onRun?.call(layerId);

  @override
  void undo() => onUndo?.call(layerId);
}
