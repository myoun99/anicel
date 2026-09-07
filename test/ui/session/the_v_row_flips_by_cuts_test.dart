import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// THE V ROW FLIPS BY CUTS — the same column step a layer row takes, with
/// the track's CUTS as the covering material instead of a layer's blocks.
/// A GAP between two cuts is a place you may stand, so it is walked
/// rather than skipped, in both directions.
///
/// A characterisation test written BEFORE the flip left the session host
/// (G3, round 8). Nothing pinned it: the cut flip is reachable only
/// through the flip verbs, and every existing flip test stands on a
/// LAYER row.
void main() {
  /// Two cuts with a six-frame gap between them. The gap is what makes
  /// the rule visible.
  (EditorSessionManager s, int firstEnd, int secondStart) session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.createCut();
    final track = s.repository.requireProject().tracks.single;
    final second = track.cuts[1].id;
    s.selectCut(second);
    s.cutShift.pushCuts(6);
    final axis = s.trackFrameAxis();
    s.selectRow(TrackRowAddress(track.id));
    return (
      s,
      axis.entryFor(track.cuts.first.id)!.endFrame,
      axis.entryFor(second)!.startFrame,
    );
  }

  test('a forward flip inside a cut steps OUT of it, to the first frame '
      'the cut no longer covers', () {
    final (s, firstEnd, _) = session();
    s.selectGlobalFrame(0);
    s.selectNextDrawing();
    expect(s.editingGlobalFrame, firstEnd);
  });

  test('inside the GAP the step is one frame, and it reaches the next '
      'cut', () {
    final (s, firstEnd, secondStart) = session();
    s.selectGlobalFrame(secondStart - 1);
    s.selectNextDrawing();
    expect(s.editingGlobalFrame, secondStart);
    expect(s.activeCutOrNull, isNotNull, reason: 'landed IN the next cut');
  });

  test('a backward flip out of the gap lands on the covering cut\'s '
      'start, and the start of the film is the floor', () {
    final (s, firstEnd, _) = session();
    s.selectGlobalFrame(firstEnd);
    s.selectPreviousDrawing();
    expect(s.editingGlobalFrame, 0);

    // F-21: a step that falls through the floor lands ON it rather than
    // doing nothing.
    s.selectPreviousDrawing();
    expect(s.editingGlobalFrame, 0);
  });

  test('flipping ANOTHER track\'s cut row walks that track: the step and '
      'the landing are on one axis', () {
    // Two tracks, a cut each. Standing on B's cut row is what makes B the
    // track being walked — and the landing must agree with the step.
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('two-tracks'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('a'),
            name: 'A',
            cuts: [
              createDefaultCut(
                cutId: const CutId('a1'),
                name: '1',
                layerId: const LayerId('a1-layer'),
              ),
            ],
          ),
          Track(
            id: const TrackId('b'),
            name: 'B',
            cuts: [
              createDefaultCut(
                cutId: const CutId('b1'),
                name: '1',
                layerId: const LayerId('b1-layer'),
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);

    s.selectCut(const CutId('a1'));
    s.selectFrameIndex(5);
    s.selectRow(const TrackRowAddress(TrackId('b')));
    expect(
      s.selectedTrackId,
      const TrackId('b'),
      reason: 'standing on a cut row TAKES its track',
    );

    s.selectPreviousDrawing();
    expect(
      s.activeCutId,
      const CutId('b1'),
      reason:
          "the step was measured on B's axis, so B's cut is what "
          'frame 0 names',
    );
  });

  test('F-21: stepping back OUT of the first cut lands on frame 0 instead '
      'of doing nothing', () {
    final (s, _, _) = session();
    // Inside the first cut, which starts at the film's own floor: the
    // column to the left of it is off the axis entirely.
    s.selectGlobalFrame(5);
    expect(s.editingGlobalFrame, 5);

    s.selectPreviousDrawing();
    expect(s.editingGlobalFrame, 0);
  });
}
