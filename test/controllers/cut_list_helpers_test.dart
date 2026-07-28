import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/cut_list_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';

void main() {
  group('cutListEntriesFor', () {
    test('returns an empty list for a project with no tracks', () {
      final project = _projectWithTracks(const []);

      expect(cutListEntriesFor(project), isEmpty);
    });

    test('returns an empty list for tracks with no cuts', () {
      final project = _projectWithTracks([
        _track(id: 'video-track', name: 'Video Track', cuts: []),
        _track(
          id: 'audio-track',
          name: 'Audio Track',
          type: TrackType.audio,
          cuts: [],
        ),
      ]);

      expect(cutListEntriesFor(project), isEmpty);
    });

    test('returns cuts in project track/cut order', () {
      final project = _projectWithTracks([
        _track(
          id: 'track-1',
          name: 'Track 1',
          cuts: [
            _cut(id: 'cut-1-a'),
            _cut(id: 'cut-1-b'),
          ],
        ),
        _track(
          id: 'track-2',
          name: 'Track 2',
          cuts: [
            _cut(id: 'cut-2-a'),
            _cut(id: 'cut-2-b'),
          ],
        ),
      ]);

      final entries = cutListEntriesFor(project);

      expect(entries.map((entry) => entry.cutId).toList(), const [
        CutId('cut-1-a'),
        CutId('cut-1-b'),
        CutId('cut-2-a'),
        CutId('cut-2-b'),
      ]);
    });

    test('includes track and cut identity, display data, and indexes', () {
      final project = _projectWithTracks([
        _track(
          id: 'track-1',
          name: 'Video Track',
          cuts: [_cut(id: 'cut-1', name: 'Cut One')],
        ),
      ]);

      final entry = cutListEntriesFor(project).single;

      expect(entry.trackId, const TrackId('track-1'));
      expect(entry.trackName, 'Video Track');
      expect(entry.trackIndex, 0);
      expect(entry.trackType, TrackType.video);
      expect(entry.cutId, const CutId('cut-1'));
      expect(entry.cutName, 'Cut One');
      expect(entry.cutIndex, 0);
      expect(entry.isActive, isFalse);
    });

    test('marks the active cut when activeCutId is provided', () {
      final project = _projectWithTracks([
        _track(
          id: 'track-1',
          name: 'Track 1',
          cuts: [
            _cut(id: 'cut-1'),
            _cut(id: 'cut-2'),
          ],
        ),
      ]);

      final entries = cutListEntriesFor(
        project,
        activeCutId: const CutId('cut-2'),
      );

      expect(entries.map((entry) => entry.isActive).toList(), [false, true]);
    });

    test('marks no cuts active when activeCutId is null', () {
      final project = _projectWithTracks([
        _track(
          id: 'track-1',
          name: 'Track 1',
          cuts: [
            _cut(id: 'cut-1'),
            _cut(id: 'cut-2'),
          ],
        ),
      ]);

      final entries = cutListEntriesFor(project);

      expect(entries.every((entry) => !entry.isActive), isTrue);
    });

    test('marks no cuts active when activeCutId is not found', () {
      final project = _projectWithTracks([
        _track(
          id: 'track-1',
          name: 'Track 1',
          cuts: [
            _cut(id: 'cut-1'),
            _cut(id: 'cut-2'),
          ],
        ),
      ]);

      final entries = cutListEntriesFor(
        project,
        activeCutId: const CutId('missing-cut'),
      );

      expect(entries.every((entry) => !entry.isActive), isTrue);
    });

    test('handles multiple tracks with multiple cuts', () {
      final project = _projectWithTracks([
        _track(
          id: 'track-1',
          name: 'Track 1',
          cuts: [
            _cut(id: 'cut-1-a'),
            _cut(id: 'cut-1-b'),
          ],
        ),
        _track(
          id: 'track-2',
          name: 'Track 2',
          cuts: [
            _cut(id: 'cut-2-a'),
            _cut(id: 'cut-2-b'),
          ],
        ),
        _track(
          id: 'track-3',
          name: 'Track 3',
          cuts: [_cut(id: 'cut-3-a')],
        ),
      ]);

      final entries = cutListEntriesFor(project);

      expect(entries, hasLength(5));
      expect(entries.map((entry) => entry.trackIndex).toList(), [
        0,
        0,
        1,
        1,
        2,
      ]);
      expect(entries.map((entry) => entry.cutIndex).toList(), [0, 1, 0, 1, 0]);
    });

    test('preserves audio/video track type in entries', () {
      final project = _projectWithTracks([
        _track(
          id: 'video-track',
          name: 'Video Track',
          type: TrackType.video,
          cuts: [_cut(id: 'video-cut')],
        ),
        _track(
          id: 'audio-track',
          name: 'Audio Track',
          type: TrackType.audio,
          cuts: [_cut(id: 'audio-cut')],
        ),
      ]);

      final entries = cutListEntriesFor(project);

      expect(entries.map((entry) => entry.trackType).toList(), [
        TrackType.video,
        TrackType.audio,
      ]);
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
  required String name,
  required List<Cut> cuts,
  TrackType type = TrackType.video,
}) {
  return Track(id: TrackId(id), name: name, cuts: cuts, type: type);
}

Cut _cut({required String id, String? name}) {
  return Cut(
    id: CutId(id),
    name: name ?? id,
    layers: const [],
    duration: 1,
    canvasSize: const CanvasSize(width: 1280, height: 720),
  );
}
