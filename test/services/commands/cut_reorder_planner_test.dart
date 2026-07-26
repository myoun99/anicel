import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/canvas_size.dart';
import 'package:quick_animaker_v2/src/models/cut.dart';
import 'package:quick_animaker_v2/src/models/cut_id.dart';
import 'package:quick_animaker_v2/src/models/project.dart';
import 'package:quick_animaker_v2/src/models/project_id.dart';
import 'package:quick_animaker_v2/src/models/track.dart';
import 'package:quick_animaker_v2/src/models/track_id.dart';
import 'package:quick_animaker_v2/src/services/commands/cut_reorder_planner.dart';

void main() {
  const planner = CutReorderPlanner();

  group('CutReorderPlanner', () {
    test('finds Cut position in first Track', () {
      final project = _projectWithTracks([
        _track(id: 'track-a', cutIds: ['cut-a', 'cut-b', 'cut-c']),
      ]);

      final position = planner.findCutPosition(
        project: project,
        cutId: const CutId('cut-b'),
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

      final position = planner.findCutPosition(
        project: project,
        cutId: const CutId('cut-c'),
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
        planner.findCutPosition(
          project: project,
          cutId: const CutId('missing-cut'),
        ),
        isNull,
      );
      expect(
        () => planner.requireCutPosition(
          project: project,
          cutId: const CutId('missing-cut'),
        ),
        throwsStateError,
      );
    });

    test('canMoveLeft and canMoveRight reflect first middle and last Cuts', () {
      final positions = _positionsForThreeCuts();

      expect(planner.canMoveLeft(positions[0]), isFalse);
      expect(planner.canMoveRight(positions[0]), isTrue);
      expect(planner.canMoveLeft(positions[1]), isTrue);
      expect(planner.canMoveRight(positions[1]), isTrue);
      expect(planner.canMoveLeft(positions[2]), isTrue);
      expect(planner.canMoveRight(positions[2]), isFalse);
    });

    test('calculates target indexes for a middle Cut', () {
      final middlePosition = _positionsForThreeCuts()[1];

      expect(planner.moveLeftTargetIndex(middlePosition), 0);
      expect(planner.moveRightTargetIndex(middlePosition), 2);
    });

    test('fails clearly for edge target indexes', () {
      final positions = _positionsForThreeCuts();

      expect(() => planner.moveLeftTargetIndex(positions[0]), throwsStateError);
      expect(
        () => planner.moveRightTargetIndex(positions[2]),
        throwsStateError,
      );
    });
  });
}

List<CutPosition> _positionsForThreeCuts() {
  final project = _projectWithTracks([
    _track(id: 'track-a', cutIds: ['cut-a', 'cut-b', 'cut-c']),
  ]);
  const planner = CutReorderPlanner();

  return [
    planner.requireCutPosition(project: project, cutId: const CutId('cut-a')),
    planner.requireCutPosition(project: project, cutId: const CutId('cut-b')),
    planner.requireCutPosition(project: project, cutId: const CutId('cut-c')),
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
