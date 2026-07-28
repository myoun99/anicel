import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/editing_session_state.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';

void main() {
  group('EditingSessionState', () {
    test('owns the active cut id supplied at construction', () {
      final session = EditingSessionState(activeCutId: const CutId('cut-a'));

      expect(session.activeCutId, const CutId('cut-a'));
    });

    test('can update the active cut id without mutating project data', () {
      final cutA = _cut('cut-a');
      final cutB = _cut('cut-b');
      final project = _projectWithTracks([
        _track(id: 'video-track', cuts: [cutA, cutB]),
      ]);
      final session = EditingSessionState.forProject(project);

      session.setActiveCutId(const CutId('cut-b'));

      expect(session.activeCutId, const CutId('cut-b'));
      expect(project.tracks.single.cuts[0].id, const CutId('cut-a'));
      expect(project.tracks.single.cuts[1].id, const CutId('cut-b'));
    });

    test('initializes from the default active cut for a project', () {
      final project = _projectWithTracks([
        _track(
          id: 'audio-track',
          type: TrackType.audio,
          cuts: [_cut('audio-cut')],
        ),
        _track(id: 'video-track', cuts: [_cut('video-cut')]),
      ]);

      final session = EditingSessionState.forProject(project);

      expect(session.activeCutId, const CutId('video-cut'));
    });

    test('sample project resolves to the existing sample cut id', () {
      final project = _projectWithTracks([
        _track(id: 'sample-track', cuts: [_cut('sample-cut')]),
      ]);

      final session = EditingSessionState.forProject(project);

      expect(session.activeCutId, const CutId('sample-cut'));
    });

    test('throws when initialized from a project with no cuts', () {
      final project = _projectWithTracks([
        _track(id: 'empty-video-track', cuts: []),
      ]);

      expect(() => EditingSessionState.forProject(project), throwsStateError);
    });
  });
}

Project _projectWithTracks(List<Track> tracks) {
  return Project(
    id: const ProjectId('project'),
    name: 'Project',
    tracks: tracks,
    createdAt: DateTime.utc(2026),
  );
}

Track _track({
  required String id,
  required List<Cut> cuts,
  TrackType type = TrackType.video,
}) {
  return Track(id: TrackId(id), name: id, cuts: cuts, type: type);
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
