import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/cut_insertion.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/project_repository.dart';

/// THE ONE INSERTION, asked directly: a cut put into a project takes its
/// room from the gaps ahead, and is taken back out with that room handed
/// back as it was RECORDED.
///
/// What the cut does to the cuts behind it is pinned where the user said it
/// (`a_cut_takes_its_room_the_way_a_block_does_test`, 유저 #19 · F-97).
/// These are the edges that file's two verbs never reach: the slot a cut
/// takes when none is named, the write that names a track or a cut that is
/// not there, and the way back by the recorded numbers.
void main() {
  Cut cut(String id, {int gap = 0, int length = 10}) => createDefaultCut(
    cutId: CutId(id),
    name: id,
    layerId: LayerId('$id-cel'),
  ).copyWith(leadingGapFrames: gap, duration: length);

  /// The default project's track holding [cuts] alone.
  ({Project project, TrackId trackId}) filmOf(List<Cut> cuts) {
    final base = createDefaultProject();
    final track = base.tracks.first;
    return (
      project: base.copyWith(tracks: [track.copyWith(cuts: cuts)]),
      trackId: track.id,
    );
  }

  List<(String, int)> laidOut(Project project) => [
    for (final cut in project.tracks.first.cuts)
      (cut.id.value, cut.leadingGapFrames),
  ];

  test('with no slot named, the cut goes after the track\'s last', () {
    final film = filmOf([cut('a'), cut('b', gap: 4)]);

    final inserted = projectWithCutInserted(
      film.project,
      trackId: film.trackId,
      cut: cut('new'),
    );

    expect(laidOut(inserted.project), [('a', 0), ('b', 4), ('new', 0)]);
    expect(inserted.gapsBefore, isEmpty, reason: 'nothing behind it to ask');
  });

  test('it takes its room from the gap ahead, and records the gap as it '
      'was', () {
    final film = filmOf([cut('a'), cut('b', gap: 25)]);

    final inserted = projectWithCutInserted(
      film.project,
      trackId: film.trackId,
      cut: cut('new', length: 10),
      index: 1,
    );

    expect(laidOut(inserted.project), [('a', 0), ('new', 0), ('b', 15)]);
    expect(inserted.gapsBefore, {const CutId('b'): 25});
  });

  test('taken back out, the room is handed back by the RECORDED number — '
      'not by adding the cut\'s length back', () {
    // b had 4 frames of room and the cut took 10: b was pushed. Handing the
    // footprint back would leave b a 10-frame gap it never had.
    final film = filmOf([cut('a'), cut('b', gap: 4)]);
    final inserted = projectWithCutInserted(
      film.project,
      trackId: film.trackId,
      cut: cut('new', length: 10),
      index: 1,
    );
    expect(laidOut(inserted.project), [('a', 0), ('new', 0), ('b', 0)]);

    final back = projectWithCutTakenOut(
      inserted.project,
      cutId: const CutId('new'),
      gapsBefore: inserted.gapsBefore,
    );

    expect(laidOut(back), [('a', 0), ('b', 4)]);
  });

  test('a track that is not there is said, not skipped', () {
    final film = filmOf([cut('a')]);
    expect(
      () => projectWithCutInserted(
        film.project,
        trackId: const TrackId('no-such-track'),
        cut: cut('new'),
      ),
      throwsStateError,
    );
  });

  test('and so is a cut that is not there to take out', () {
    final film = filmOf([cut('a')]);
    expect(
      () => projectWithCutTakenOut(
        film.project,
        cutId: const CutId('never-put-in'),
        gapsBefore: const {},
      ),
      throwsStateError,
    );
  });

  test('CutInsertion is that law as ONE write, there and back', () {
    final film = filmOf([cut('a'), cut('b', gap: 25)]);
    final repository = ProjectRepository(initialProject: film.project);
    final before = laidOut(repository.requireProject());
    final insertion = CutInsertion(
      trackId: film.trackId,
      cut: cut('new', length: 10),
      index: 1,
    );

    insertion.apply(repository);
    expect(laidOut(repository.requireProject()), [
      ('a', 0),
      ('new', 0),
      ('b', 15),
    ]);

    insertion.revert(repository);
    expect(laidOut(repository.requireProject()), before);
  });
}
