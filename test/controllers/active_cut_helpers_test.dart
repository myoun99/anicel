import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/active_cut_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';

void main() {
  group('defaultActiveCutIdFor', () {
    test('prefers the first cut from the first video track with cuts', () {
      final project = _projectWithTracks([
        _track(
          id: 'audio-track',
          type: TrackType.audio,
          cuts: [_cut('audio-cut')],
        ),
        _track(
          id: 'video-track-1',
          cuts: [_cut('video-cut-1'), _cut('video-cut-2')],
        ),
        _track(id: 'video-track-2', cuts: [_cut('video-cut-3')]),
      ]);

      expect(defaultActiveCutIdFor(project), const CutId('video-cut-1'));
    });

    test('skips empty video tracks', () {
      final project = _projectWithTracks([
        _track(id: 'empty-video-track', cuts: []),
        _track(
          id: 'audio-track',
          type: TrackType.audio,
          cuts: [_cut('audio-cut')],
        ),
        _track(id: 'video-track', cuts: [_cut('video-cut')]),
      ]);

      expect(defaultActiveCutIdFor(project), const CutId('video-cut'));
    });

    test(
      'falls back to the first non-video track cut if no video cut exists',
      () {
        final project = _projectWithTracks([
          _track(id: 'empty-video-track', cuts: []),
          _track(
            id: 'audio-track-1',
            type: TrackType.audio,
            cuts: [_cut('audio-cut-1')],
          ),
          _track(
            id: 'audio-track-2',
            type: TrackType.audio,
            cuts: [_cut('audio-cut-2')],
          ),
        ]);

        expect(defaultActiveCutIdFor(project), const CutId('audio-cut-1'));
      },
    );

    test('throws when no cuts exist', () {
      final project = _projectWithTracks([
        _track(id: 'empty-video-track', cuts: []),
        _track(id: 'empty-audio-track', type: TrackType.audio, cuts: []),
      ]);

      expect(() => defaultActiveCutIdFor(project), throwsStateError);
    });

    test('sample project resolves to the existing sample cut id', () {
      final project = _projectWithTracks([
        _track(id: 'sample-track', cuts: [_cut('sample-cut')]),
      ]);

      expect(defaultActiveCutIdFor(project), const CutId('sample-cut'));
    });
  });

  group('findCutById', () {
    test('finds cuts by CutId', () {
      final cutA = _cut('cut-a');
      final cutB = _cut('cut-b');
      final project = _projectWithTracks([
        _track(id: 'video-track', cuts: [cutA]),
        _track(id: 'audio-track', type: TrackType.audio, cuts: [cutB]),
      ]);

      expect(findCutById(project, const CutId('cut-b')), same(cutB));
      expect(findCutById(project, const CutId('missing-cut')), isNull);
    });
  });

  group('requireCutById', () {
    test('returns a matching cut or throws', () {
      final cut = _cut('cut-a');
      final project = _projectWithTracks([
        _track(id: 'video-track', cuts: [cut]),
      ]);

      expect(requireCutById(project, const CutId('cut-a')), same(cut));
      expect(
        () => requireCutById(project, const CutId('missing')),
        throwsStateError,
      );
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
