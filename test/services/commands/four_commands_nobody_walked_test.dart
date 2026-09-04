import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/reorder_track_command.dart';
import 'package:anicel/src/services/commands/update_cut_durations_command.dart';
import 'package:anicel/src/services/commands/update_project_trailing_frames_command.dart';
import 'package:anicel/src/services/commands/update_track_display_command.dart';
import 'package:anicel/src/services/project_repository.dart';

/// 🚨A COMMAND NOBODY EXECUTES IN A TEST IS AN UNDO NOBODY HAS WALKED.
///
/// These four went on the undo stack with nothing naming them (the audit's
/// untested-file pass, 2026-09-05). What each one owes is the same:
/// execute changes exactly what it says, undo puts the project back, and
/// undo before execute is refused rather than half-applied.
void main() {
  Layer layer(String id) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    timeline: const {},
    kind: LayerKind.image,
  );

  Cut cut(String id, {int duration = 12, int leadingGap = 0}) => Cut(
    id: CutId(id),
    name: id,
    layers: [layer('$id-l')],
    duration: duration,
    leadingGapFrames: leadingGap,
    canvasSize: const CanvasSize(width: 100, height: 100),
  );

  Track track(String id, List<Cut> cuts) =>
      Track(id: TrackId(id), name: id, cuts: cuts);

  Project projectWith({required List<Track> tracks, int trailingFrames = 0}) =>
      Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 9, 5),
        trailingFrames: trailingFrames,
        tracks: tracks,
      );

  ProjectRepository repositoryWith(Project project) =>
      ProjectRepository(initialProject: project);

  group('UpdateTrackDisplayCommand', () {
    ProjectRepository open() => repositoryWith(
      projectWith(
        tracks: [
          track('t', [cut('c')]),
        ],
      ),
    );

    Track trackOf(ProjectRepository repository) =>
        repository.requireProject().tracks.single;

    test('opacity alone leaves the fx switch where it was', () {
      final repository = open();
      final before = trackOf(repository).fxEnabled;

      UpdateTrackDisplayCommand(
        repository: repository,
        trackId: const TrackId('t'),
        description: 'Track opacity',
        opacity: 0.25,
      ).execute();

      expect(trackOf(repository).opacity, 0.25);
      expect(
        trackOf(repository).fxEnabled,
        before,
        reason:
            'null leaves that property alone — the opacity drag and the '
            'fx switch share this command',
      );
    });

    test('the fx switch alone leaves the opacity', () {
      final repository = open();
      UpdateTrackDisplayCommand(
        repository: repository,
        trackId: const TrackId('t'),
        description: 'Track opacity',
        opacity: 0.25,
      ).execute();

      UpdateTrackDisplayCommand(
        repository: repository,
        trackId: const TrackId('t'),
        description: 'Track fx',
        fxEnabled: false,
      ).execute();

      expect(trackOf(repository).opacity, 0.25);
      expect(trackOf(repository).fxEnabled, isFalse);
    });

    test('undo puts the whole previous project back', () {
      final repository = open();
      final command = UpdateTrackDisplayCommand(
        repository: repository,
        trackId: const TrackId('t'),
        description: 'Track opacity',
        opacity: 0.25,
      );

      command.execute();
      command.undo();

      expect(trackOf(repository).opacity, 1.0);
    });

    test('undo before execute is refused', () {
      expect(
        UpdateTrackDisplayCommand(
          repository: open(),
          trackId: const TrackId('t'),
          description: 'Track opacity',
          opacity: 0.25,
        ).undo,
        throwsStateError,
      );
    });

    test('the description is the CALLER\'s — a drag says what it edited', () {
      expect(
        UpdateTrackDisplayCommand(
          repository: open(),
          trackId: const TrackId('t'),
          description: 'Drag the track opacity',
          opacity: 0.25,
        ).description,
        'Drag the track opacity',
      );
    });
  });

  group('ReorderTrackCommand', () {
    ProjectRepository open() => repositoryWith(
      projectWith(
        tracks: [
          track('a', [cut('c1')]),
          track('b', [cut('c2')]),
          track('c', [cut('c3')]),
        ],
      ),
    );

    List<String> orderOf(ProjectRepository repository) => [
      for (final t in repository.requireProject().tracks) t.id.value,
    ];

    test('a track moves, and the rest close up behind it', () {
      final repository = open();

      ReorderTrackCommand(
        repository: repository,
        fromIndex: 0,
        toIndex: 2,
        trackName: 'a',
      ).execute();

      expect(orderOf(repository), ['b', 'c', 'a']);
    });

    test('undo restores the order', () {
      final repository = open();
      final command = ReorderTrackCommand(
        repository: repository,
        fromIndex: 2,
        toIndex: 0,
        trackName: 'c',
      );

      command.execute();
      expect(orderOf(repository), ['c', 'a', 'b']);

      command.undo();
      expect(orderOf(repository), ['a', 'b', 'c']);
    });

    test('the description names the track the user dragged', () {
      expect(
        ReorderTrackCommand(
          repository: open(),
          fromIndex: 0,
          toIndex: 1,
          trackName: 'Background',
        ).description,
        contains('Background'),
      );
    });

    test('undo before execute is refused', () {
      expect(
        ReorderTrackCommand(
          repository: open(),
          fromIndex: 0,
          toIndex: 1,
          trackName: 'a',
        ).undo,
        throwsStateError,
      );
    });
  });

  group('UpdateProjectTrailingFramesCommand', () {
    ProjectRepository open() => repositoryWith(
      projectWith(
        tracks: [
          track('t', [cut('c')]),
        ],
        trailingFrames: 4,
      ),
    );

    test('the movie length changes and undoes', () {
      final repository = open();
      final command = UpdateProjectTrailingFramesCommand(
        repository: repository,
        trailingFrames: 20,
      );

      command.execute();
      expect(repository.requireProject().trailingFrames, 20);

      command.undo();
      expect(repository.requireProject().trailingFrames, 4);
    });

    test('🚨executing TWICE keeps the FIRST previous length', () {
      final repository = open();
      final command = UpdateProjectTrailingFramesCommand(
        repository: repository,
        trailingFrames: 20,
      );

      command.execute();
      command.execute();
      command.undo();

      expect(repository.requireProject().trailingFrames, 4);
    });

    test('undo before execute is refused', () {
      expect(
        UpdateProjectTrailingFramesCommand(
          repository: open(),
          trailingFrames: 20,
        ).undo,
        throwsStateError,
      );
    });
  });

  group('UpdateCutDurationsCommand', () {
    ProjectRepository open() => repositoryWith(
      projectWith(
        tracks: [
          track('t', [cut('c1'), cut('c2', leadingGap: 3)]),
        ],
      ),
    );

    Cut cutOf(ProjectRepository repository, String id) => repository
        .requireProject()
        .tracks
        .single
        .cuts
        .firstWhere((c) => c.id == CutId(id));

    test('durations and gaps apply together — an end trim can consume the '
        'following cut\'s gap in one step', () {
      final repository = open();

      UpdateCutDurationsCommand(
        repository: repository,
        before: {const CutId('c1'): 12},
        after: {const CutId('c1'): 15},
        beforeGaps: {const CutId('c2'): 3},
        afterGaps: {const CutId('c2'): 0},
      ).execute();

      expect(cutOf(repository, 'c1').duration, 15);
      expect(cutOf(repository, 'c2').leadingGapFrames, 0);
    });

    test('undo restores both halves', () {
      final repository = open();
      final command = UpdateCutDurationsCommand(
        repository: repository,
        before: {const CutId('c1'): 12},
        after: {const CutId('c1'): 15},
        beforeGaps: {const CutId('c2'): 3},
        afterGaps: {const CutId('c2'): 0},
      );

      command.execute();
      command.undo();

      expect(cutOf(repository, 'c1').duration, 12);
      expect(cutOf(repository, 'c2').leadingGapFrames, 3);
    });

    test('execute is IDEMPOTENT — a drag re-applies it every frame', () {
      final repository = open();
      final command = UpdateCutDurationsCommand(
        repository: repository,
        before: {const CutId('c1'): 12},
        after: {const CutId('c1'): 15},
      );

      command.execute();
      command.execute();
      command.undo();

      expect(cutOf(repository, 'c1').duration, 12);
    });

    test('a start slide edits only the gap', () {
      final repository = open();

      UpdateCutDurationsCommand(
        repository: repository,
        before: const {},
        after: const {},
        beforeGaps: {const CutId('c2'): 3},
        afterGaps: {const CutId('c2'): 7},
      ).execute();

      expect(cutOf(repository, 'c2').leadingGapFrames, 7);
      expect(cutOf(repository, 'c2').duration, 12);
    });
  });
}
