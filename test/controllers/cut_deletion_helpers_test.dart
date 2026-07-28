import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/cut_deletion_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';

void main() {
  group('cutDeletionFallbackFor', () {
    test('uses the previous cut when deleting a middle cut', () {
      final project = _projectWithTracks([
        _track(
          id: 'track-1',
          cuts: [_cut('cut-1'), _cut('cut-2'), _cut('cut-3')],
        ),
      ]);

      final decision = cutDeletionFallbackFor(
        project,
        deletingCutId: const CutId('cut-2'),
      );

      expect(
        decision,
        const CutDeletionFallbackDecision.useExistingCut(CutId('cut-1')),
      );
    });

    test('uses the next cut when deleting the first cut', () {
      final project = _projectWithTracks([
        _track(
          id: 'track-1',
          cuts: [_cut('cut-1'), _cut('cut-2'), _cut('cut-3')],
        ),
      ]);

      final decision = cutDeletionFallbackFor(
        project,
        deletingCutId: const CutId('cut-1'),
      );

      expect(
        decision,
        const CutDeletionFallbackDecision.useExistingCut(CutId('cut-2')),
      );
    });

    test('uses the previous cut when deleting the last cut', () {
      final project = _projectWithTracks([
        _track(
          id: 'track-1',
          cuts: [_cut('cut-1'), _cut('cut-2'), _cut('cut-3')],
        ),
      ]);

      final decision = cutDeletionFallbackFor(
        project,
        deletingCutId: const CutId('cut-3'),
      );

      expect(
        decision,
        const CutDeletionFallbackDecision.useExistingCut(CutId('cut-2')),
      );
    });

    test('R28 #14: deleting the ONLY cut empties the track — no replacement '
        'cut is requested', () {
      final project = _projectWithTracks([
        _track(id: 'track-1', cuts: [_cut('only-cut')]),
      ]);

      final decision = cutDeletionFallbackFor(
        project,
        deletingCutId: const CutId('only-cut'),
      );

      expect(decision, const CutDeletionFallbackDecision.emptyTrack());
      expect(decision.cutId, isNull);
    });

    test('uses project order across multiple tracks', () {
      final project = _projectWithTracks([
        _track(id: 'track-1', cuts: [_cut('cut-1-a'), _cut('cut-1-b')]),
        _track(id: 'track-2', cuts: [_cut('cut-2-a'), _cut('cut-2-b')]),
      ]);

      final decision = cutDeletionFallbackFor(
        project,
        deletingCutId: const CutId('cut-2-a'),
      );

      expect(
        decision,
        const CutDeletionFallbackDecision.useExistingCut(CutId('cut-1-b')),
      );
    });

    test('ignores empty tracks while preserving stable project order', () {
      final project = _projectWithTracks([
        _track(id: 'empty-track-1', cuts: []),
        _track(id: 'track-1', cuts: [_cut('cut-1')]),
        _track(id: 'empty-track-2', type: TrackType.audio, cuts: []),
        _track(id: 'track-2', cuts: [_cut('cut-2')]),
      ]);

      final decision = cutDeletionFallbackFor(
        project,
        deletingCutId: const CutId('cut-1'),
      );

      expect(
        decision,
        const CutDeletionFallbackDecision.useExistingCut(CutId('cut-2')),
      );
    });

    test('handles cuts on audio and video tracks in project order', () {
      final project = _projectWithTracks([
        _track(id: 'video-track', cuts: [_cut('video-cut')]),
        _track(
          id: 'audio-track',
          type: TrackType.audio,
          cuts: [_cut('audio-cut')],
        ),
      ]);

      final decision = cutDeletionFallbackFor(
        project,
        deletingCutId: const CutId('audio-cut'),
      );

      expect(
        decision,
        const CutDeletionFallbackDecision.useExistingCut(CutId('video-cut')),
      );
    });

    test('throws StateError when deleting cut id is missing', () {
      final project = _projectWithTracks([
        _track(id: 'empty-track', cuts: []),
        _track(id: 'track-1', cuts: [_cut('cut-1')]),
      ]);

      expect(
        () => cutDeletionFallbackFor(
          project,
          deletingCutId: const CutId('missing-cut'),
        ),
        throwsStateError,
      );
    });

    test('does not mutate the project', () {
      final project = _projectWithTracks([
        _track(id: 'track-1', cuts: [_cut('cut-1'), _cut('cut-2')]),
      ]);

      cutDeletionFallbackFor(project, deletingCutId: const CutId('cut-1'));

      expect(project.tracks.single.cuts.map((cut) => cut.id).toList(), const [
        CutId('cut-1'),
        CutId('cut-2'),
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
