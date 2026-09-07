import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/cut_reorder_planner.dart';
import 'package:anicel/src/services/project_lookup.dart';

void main() {
  const planner = CutReorderPlanner();

  group('CutReorderPlanner', () {
    test('finds Cut position in first Track', () {
      final project = _projectWithTracks([
        _track(id: 'track-a', cutIds: ['cut-a', 'cut-b', 'cut-c']),
      ]);

      final position = cutPositionOf(
        project,
        const CutId('cut-b'),
      );

      expect(position, isNotNull);
      expect(position!.trackId, const TrackId('track-a'));
      expect(position.cutId, const CutId('cut-b'));
      expect(position.cutIndex, 1);
      expect(position.cutCount, 3);
    });

    test('finds Cut position in later Track', () {
      final project = _projectWithTracks([
        _track(id: 'track-a', cutIds: ['cut-a']),
        _track(id: 'track-b', cutIds: ['cut-b', 'cut-c']),
      ]);

      final position = cutPositionOf(
        project,
        const CutId('cut-c'),
      );

      expect(position, isNotNull);
      expect(position!.trackId, const TrackId('track-b'));
      expect(position.cutId, const CutId('cut-c'));
      expect(position.cutIndex, 1);
      expect(position.cutCount, 2);
    });

    test('returns null and throws StateError for missing Cut', () {
      final project = _projectWithTracks([
        _track(id: 'track-a', cutIds: ['cut-a']),
      ]);

      expect(
        cutPositionOf(
          project,
          const CutId('missing-cut'),
        ),
        isNull,
      );
      expect(
        () => requireCutPosition(
          project,
          const CutId('missing-cut'),
        ),
        throwsStateError,
      );
    });

    test('canMove reflects first middle and last Cuts, both ways', () {
      final positions = _positionsForThreeCuts();

      expect(planner.canMove(positions[0], CutMoveDirection.left), isFalse);
      expect(planner.canMove(positions[0], CutMoveDirection.right), isTrue);
      expect(planner.canMove(positions[1], CutMoveDirection.left), isTrue);
      expect(planner.canMove(positions[1], CutMoveDirection.right), isTrue);
      expect(planner.canMove(positions[2], CutMoveDirection.left), isTrue);
      expect(planner.canMove(positions[2], CutMoveDirection.right), isFalse);
    });

    test('calculates target indexes for a middle Cut', () {
      final middlePosition = _positionsForThreeCuts()[1];

      expect(planner.moveTargetIndex(middlePosition, CutMoveDirection.left), 0);
      expect(
        planner.moveTargetIndex(middlePosition, CutMoveDirection.right),
        2,
      );
    });

    test('fails clearly for edge target indexes', () {
      final positions = _positionsForThreeCuts();

      expect(
        () => planner.moveTargetIndex(positions[0], CutMoveDirection.left),
        throwsStateError,
      );
      expect(
        () => planner.moveTargetIndex(positions[2], CutMoveDirection.right),
        throwsStateError,
      );
    });

    test('a one-cut track cannot move either way', () {
      // The guards used to be two sentences; a lone cut is where they both
      // have to say no.
      final only = requireCutPosition(
        _projectWithTracks([_track(id: 'track-a', cutIds: ['cut-a'])]),
        const CutId('cut-a'),
      );
      expect(planner.canMove(only, CutMoveDirection.left), isFalse);
      expect(planner.canMove(only, CutMoveDirection.right), isFalse);
    });
  });
}

List<CutPosition> _positionsForThreeCuts() {
  final project = _projectWithTracks([
    _track(id: 'track-a', cutIds: ['cut-a', 'cut-b', 'cut-c']),
  ]);

  return [
    requireCutPosition(project, const CutId('cut-a')),
    requireCutPosition(project, const CutId('cut-b')),
    requireCutPosition(project, const CutId('cut-c')),
  ];
}

Project _projectWithTracks(List<Track> tracks) {
  return Project(
    id: const ProjectId('project-1'),
    name: 'Project',
    tracks: tracks,
    createdAt: DateTime.utc(2026),
  );
}

Track _track({required String id, required List<String> cutIds}) {
  return Track(id: TrackId(id), name: id, cuts: cutIds.map(_cut).toList());
}

Cut _cut(String id) {
  return Cut(
    id: CutId(id),
    name: id,
    layers: const [],
    duration: 1,
    canvasSize: const CanvasSize(width: 1280, height: 720),
  );
}
