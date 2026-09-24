import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/import_media_command.dart';
import 'package:anicel/src/services/commands/track_transition_commands.dart';
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/services/project_repository.dart';

/// The two remaining commands with nothing naming them: an import that
/// lands cuts, layers and pool entries in ONE undo step, and the track's
/// transition row.
void main() {
  Layer layer(String id, {LayerKind kind = LayerKind.image}) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    timeline: const {},
    kind: kind,
  );

  Cut cut(String id, [List<Layer> layers = const []]) => Cut(
    id: CutId(id),
    name: id,
    layers: layers,
    duration: 12,
    canvasSize: const CanvasSize(width: 100, height: 100),
  );

  Project projectWith({
    List<Cut>? cuts,
    List<MediaAsset> assets = const [],
    Layer? transitionLayer,
  }) => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 9, 5),
    mediaAssets: assets,
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'V',
        transitionLayer: transitionLayer,
        cuts:
            cuts ??
            [
              cut('c', [layer('l')]),
            ],
      ),
    ],
  );

  Track trackOf(ProjectRepository repository) =>
      repository.requireProject().tracks.single;

  group('ImportMediaCommand', () {
    test('imported CUTS land on the track and the active cut follows the '
        'first of them', () {
      final repository = ProjectRepository(initialProject: projectWith());
      final session = EditingSessionState(activeCutId: const CutId('c'));
      final command = ImportMediaCommand(
        repository: repository,
        editingSession: session,
        trackId: const TrackId('t'),
        newCuts: [cut('new1'), cut('new2')],
      );

      command.execute();

      expect(
        [for (final c in trackOf(repository).cuts) c.id.value],
        ['c', 'new1', 'new2'],
      );
      expect(session.activeCutId, const CutId('new1'));
    });

    test('undo takes the cuts back out AND returns the active cut', () {
      final repository = ProjectRepository(initialProject: projectWith());
      final session = EditingSessionState(activeCutId: const CutId('c'));
      final command = ImportMediaCommand(
        repository: repository,
        editingSession: session,
        trackId: const TrackId('t'),
        newCuts: [cut('new1')],
      );

      command.execute();
      command.undo();

      expect([for (final c in trackOf(repository).cuts) c.id.value], ['c']);
      expect(session.activeCutId, const CutId('c'));
    });

    test('imported LAYERS land on top of the target cut\'s stack', () {
      final repository = ProjectRepository(initialProject: projectWith());
      final command = ImportMediaCommand(
        repository: repository,
        editingSession: EditingSessionState(activeCutId: const CutId('c')),
        targetCutId: const CutId('c'),
        newLayers: [layer('imported')],
      );

      command.execute();

      expect(
        [for (final l in trackOf(repository).cuts.single.layers) l.id.value],
        ['l', 'imported'],
      );
    });

    test('pool additions ride the SAME undo, and a path already in the '
        'pool is not added twice', () {
      final repository = ProjectRepository(
        initialProject: projectWith(
          assets: [MediaAsset(path: '/a.wav', name: 'a')],
        ),
      );
      final command = ImportMediaCommand(
        repository: repository,
        editingSession: EditingSessionState(activeCutId: const CutId('c')),
        assetAdditions: [
          MediaAsset(path: '/a.wav', name: 'a again'),
          MediaAsset(path: '/b.wav', name: 'b'),
        ],
      );

      command.execute();
      expect(
        [for (final a in repository.requireProject().mediaAssets) a.path],
        ['/a.wav', '/b.wav'],
      );

      command.undo();
      expect(
        [for (final a in repository.requireProject().mediaAssets) a.path],
        ['/a.wav'],
      );
    });

    test('⛔importing cuts with NO track id is refused rather than guessed', () {
      expect(
        ImportMediaCommand(
          repository: ProjectRepository(initialProject: projectWith()),
          editingSession: EditingSessionState(activeCutId: const CutId('c')),
          newCuts: [cut('new1')],
        ).execute,
        throwsStateError,
      );
    });

    test('⛔importing layers with NO target cut is refused', () {
      expect(
        ImportMediaCommand(
          repository: ProjectRepository(initialProject: projectWith()),
          editingSession: EditingSessionState(activeCutId: const CutId('c')),
          newLayers: [layer('imported')],
        ).execute,
        throwsStateError,
      );
    });

    test('undo before execute is refused', () {
      expect(
        ImportMediaCommand(
          repository: ProjectRepository(initialProject: projectWith()),
          editingSession: EditingSessionState(activeCutId: const CutId('c')),
        ).undo,
        throwsStateError,
      );
    });

    test('the description is the caller\'s when it gave one', () {
      expect(
        ImportMediaCommand(
          repository: ProjectRepository(initialProject: projectWith()),
          editingSession: EditingSessionState(activeCutId: const CutId('c')),
          description: 'Import 3 images',
        ).description,
        'Import 3 images',
      );
    });

    group('a new cut at an index takes its room the way Create Cut does (#19)', () {
      /// Where cut [id] sits — the track's own span walk, not a second one.
      int startOf(ProjectRepository repository, String id) =>
          cutSpansOf(trackOf(repository))
              .firstWhere((span) => span.cut.id == CutId(id))
              .startFrame;

      test('in front of a roomy follower the follower does not move — and undo '
          'gives back exactly the gap it had', () {
        final repository = ProjectRepository(
          initialProject: projectWith(
            cuts: [cut('a'), cut('b').copyWith(leadingGapFrames: 30)],
          ),
        );
        final session = EditingSessionState(activeCutId: const CutId('a'));
        final command = ImportMediaCommand(
          repository: repository,
          editingSession: session,
          trackId: const TrackId('t'),
          newCuts: [cut('new')],
          newCutIndex: 1,
        );
        final before = startOf(repository, 'b');

        command.execute();
        expect(
          [for (final c in trackOf(repository).cuts) c.id.value],
          ['a', 'new', 'b'],
        );
        expect(
          startOf(repository, 'b'),
          before,
          reason: 'the room the new cut needed was already free',
        );

        command.undo();
        expect(trackOf(repository).cuts.last.leadingGapFrames, 30);
        expect(startOf(repository, 'b'), before);
        expect(session.activeCutId, const CutId('a'));
      });

      test('a batch keeps its order from that slot', () {
        final repository = ProjectRepository(
          initialProject: projectWith(cuts: [cut('a'), cut('b')]),
        );
        ImportMediaCommand(
          repository: repository,
          editingSession: EditingSessionState(activeCutId: const CutId('a')),
          trackId: const TrackId('t'),
          newCuts: [cut('new1'), cut('new2')],
          newCutIndex: 1,
        ).execute();

        expect(
          [for (final c in trackOf(repository).cuts) c.id.value],
          ['a', 'new1', 'new2', 'b'],
        );
      });

      test('a redo lands exactly where the first run did', () {
        final repository = ProjectRepository(
          initialProject: projectWith(
            cuts: [cut('a'), cut('b').copyWith(leadingGapFrames: 5)],
          ),
        );
        final command = ImportMediaCommand(
          repository: repository,
          editingSession: EditingSessionState(activeCutId: const CutId('a')),
          trackId: const TrackId('t'),
          newCuts: [cut('new')],
          newCutIndex: 1,
        );

        command.execute();
        final first = [for (final c in trackOf(repository).cuts) c];
        command.undo();
        command.execute();

        expect(trackOf(repository).cuts, first);
      });
    });
  });

  group('UpdateTrackTransitionLayerCommand', () {
    Layer transition(String id) => layer(id, kind: LayerKind.transition);

    ProjectRepository open() => ProjectRepository(
      initialProject: projectWith(transitionLayer: transition('before')),
    );

    test('the row is replaced, and undo puts the previous one back', () {
      final repository = open();
      final command = UpdateTrackTransitionLayerCommand(
        repository: repository,
        trackId: const TrackId('t'),
        before: transition('before'),
        after: transition('after'),
      );

      command.execute();
      expect(trackOf(repository).transitionLayer.id, const LayerId('after'));

      command.undo();
      expect(trackOf(repository).transitionLayer.id, const LayerId('before'));
    });

    test('🚨the description is a DEBUG line, not a label — no UI reads it, '
        'and it must stay greppable rather than translated', () {
      final repository = open();
      expect(
        UpdateTrackTransitionLayerCommand(
          repository: repository,
          trackId: const TrackId('t'),
          before: transition('before'),
          after: transition('after'),
          debugLabel: 'transition:drag-edge',
        ).description,
        'transition:drag-edge',
      );
      expect(
        UpdateTrackTransitionLayerCommand(
          repository: repository,
          trackId: const TrackId('t'),
          before: transition('before'),
          after: transition('after'),
        ).description,
        'Edit transition',
      );
    });
  });
}
