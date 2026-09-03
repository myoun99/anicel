// THE REPOSITORY'S TRACK EDITS: A REORDER PAST THE END IS A NO-OP, A
// REMOVAL OF A TRACK IT DOES NOT HOLD IS REFUSED, AND A TRANSITION LAYER
// LANDS ON ITS OWN TRACK ONLY.
//
// Three survivors of the mutation campaign (2026-09-03): the reorder guard's
// `>=` became `>` (an index one past the end slipped through), the removal
// check's `==` became `!=` (a missing track passed and a found one threw),
// and the transition write's `==` became `!=` (every OTHER track took the
// layer) — none noticed. These pins do.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_repository.dart';

Project _twoTracks() => Project(
  id: const ProjectId('p'),
  name: 'P',
  createdAt: DateTime.utc(2026, 9, 3),
  tracks: [
    Track(id: const TrackId('a'), name: 'A', cuts: const []),
    Track(id: const TrackId('b'), name: 'B', cuts: const []),
  ],
);

List<TrackId> _order(ProjectRepository repository) => [
  for (final track in repository.currentProject!.tracks) track.id,
];

void main() {
  group('reorderTrack', () {
    test('moves a track to a valid slot', () {
      final repository = ProjectRepository(initialProject: _twoTracks());
      repository.reorderTrack(fromIndex: 0, toIndex: 1);
      expect(_order(repository), [const TrackId('b'), const TrackId('a')]);
    });

    test('a slot one past the end is refused and the order stays', () {
      final repository = ProjectRepository(initialProject: _twoTracks());
      repository.reorderTrack(fromIndex: 0, toIndex: 2);
      expect(_order(repository), [const TrackId('a'), const TrackId('b')]);
    });
  });

  group('removeTrack', () {
    test('removes the track it names', () {
      final repository = ProjectRepository(initialProject: _twoTracks());
      repository.removeTrack(const TrackId('a'));
      expect(_order(repository), [const TrackId('b')]);
    });

    test('a track the project does not hold is refused', () {
      final repository = ProjectRepository(initialProject: _twoTracks());
      expect(
        () => repository.removeTrack(const TrackId('zz')),
        throwsStateError,
      );
      expect(_order(repository), [const TrackId('a'), const TrackId('b')]);
    });
  });

  test('updateTrackTransitionLayer lands on the named track only', () {
    final repository = ProjectRepository(initialProject: _twoTracks());
    final before = repository.currentProject!;
    final renamed = before.tracks.first.transitionLayer.copyWith(
      name: 'renamed transition',
    );
    repository.updateTrackTransitionLayer(
      trackId: const TrackId('a'),
      transitionLayer: renamed,
    );
    final after = repository.currentProject!;
    expect(after.tracks[0].transitionLayer.name, 'renamed transition');
    expect(
      after.tracks[1].transitionLayer.name,
      before.tracks[1].transitionLayer.name,
    );
    expect(after.tracks[1].transitionLayer, isA<Layer>());
  });
}
