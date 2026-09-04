import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/layer_field_command.dart';
import 'package:anicel/src/services/commands/update_layer_name_command.dart';
import 'package:anicel/src/services/commands/update_layer_timesheet_command.dart';
import 'package:anicel/src/services/project_repository.dart';

/// 🚨THE PAIR THAT HAS TO AGREE: execute's `??=` AND undo's throw.
///
/// Both field-command laws remember the previous value on the FIRST
/// execute and keep it. `=` there turns redo-then-undo into an undo that
/// restores the value it just wrote — a history that cannot be walked back
/// past that step, which is the failure neither of the six (and three)
/// commands they replaced had a test for.
void main() {
  Layer layer(String id, {String name = 'L', bool onTimesheet = false}) =>
      Layer(
        id: LayerId(id),
        name: name,
        frames: const [],
        timeline: const {},
        kind: LayerKind.image,
        onTimesheet: onTimesheet,
      );

  Project projectWith({
    required List<Cut> cuts,
    LayerLinkRegistry? links,
    List<Layer> seLayers = const [],
  }) => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 9, 5),
    linkRegistry: links,
    tracks: [
      Track(id: const TrackId('t'), name: 'V', seLayers: seLayers, cuts: cuts),
    ],
  );

  Cut cut(String id, List<Layer> layers) => Cut(
    id: CutId(id),
    name: id,
    layers: layers,
    duration: 12,
    canvasSize: const CanvasSize(width: 100, height: 100),
  );

  Layer layerOf(ProjectRepository repository, String cutId, String layerId) =>
      repository
          .requireProject()
          .tracks
          .single
          .cuts
          .firstWhere((c) => c.id == CutId(cutId))
          .layers
          .firstWhere((l) => l.id == LayerId(layerId));

  group('LayerFieldCommand', () {
    ProjectRepository repositoryWithOne() => ProjectRepository(
      initialProject: projectWith(
        cuts: [
          cut('c', [layer('l')]),
        ],
      ),
    );

    UpdateLayerTimesheetCommand flip(
      ProjectRepository repository, {
      required bool onTimesheet,
    }) => UpdateLayerTimesheetCommand(
      repository: repository,
      cutId: const CutId('c'),
      layerId: const LayerId('l'),
      onTimesheet: onTimesheet,
    );

    test('execute writes the field, undo puts the old value back', () {
      final repository = repositoryWithOne();
      final command = flip(repository, onTimesheet: true);

      command.execute();
      expect(layerOf(repository, 'c', 'l').onTimesheet, isTrue);

      command.undo();
      expect(layerOf(repository, 'c', 'l').onTimesheet, isFalse);
    });

    test('🚨executing TWICE remembers the value from the FIRST time — the '
        'undo after it still walks all the way back', () {
      // ⚠️Measured 2026-09-05: redo-then-undo does NOT distinguish `=` from
      // `??=`, because the undo in between put the old value back and the
      // redo reads the same thing. What distinguishes them is executing
      // again while the NEW value is standing.
      final repository = repositoryWithOne();
      final command = flip(repository, onTimesheet: true);

      command.execute();
      command.execute();
      command.undo();

      expect(
        layerOf(repository, 'c', 'l').onTimesheet,
        isFalse,
        reason:
            '`=` would have remembered TRUE on the second execute, and '
            'this undo would restore the value the command itself wrote',
      );
    });

    test('and redo-then-undo lands there too', () {
      final repository = repositoryWithOne();
      final command = flip(repository, onTimesheet: true);

      command.execute();
      command.undo();
      command.execute();
      command.undo();

      expect(layerOf(repository, 'c', 'l').onTimesheet, isFalse);
    });

    test('undo before execute is refused', () {
      expect(
        flip(repositoryWithOne(), onTimesheet: true).undo,
        throwsStateError,
      );
    });

    test('the description names the field, or the label when one is given', () {
      final repository = repositoryWithOne();
      expect(
        flip(repository, onTimesheet: true).description,
        contains('timesheet flag'),
      );
      expect(
        LayerFieldCommand<bool>(
          repository: repository,
          layerId: const LayerId('l'),
          value: true,
          field: (
            name: 'timesheet flag',
            label: 'Drag rows into the sheet',
            read: (layer) => layer.onTimesheet,
            write: (_) {},
          ),
        ).description,
        'Drag rows into the sheet',
        reason: 'a lane drag says what it edited, not which field it wrote',
      );
    });

    test('⚠️the lookup is ANYWHERE — a track-owned SE row carries these '
        'fields and is in no cut layer list', () {
      final repository = ProjectRepository(
        initialProject: projectWith(
          cuts: [cut('c', const [])],
          seLayers: [layer('se')],
        ),
      );

      LayerFieldCommand<bool>(
        repository: repository,
        layerId: const LayerId('se'),
        value: true,
        field: (
          name: 'timesheet flag',
          label: null,
          read: (layer) => layer.onTimesheet,
          write: (value) => repository.updateLayerTimesheet(
            cutId: null,
            layerId: const LayerId('se'),
            onTimesheet: value,
          ),
        ),
      ).execute();

      expect(
        repository.requireProject().tracks.single.seLayers.single.onTimesheet,
        isTrue,
      );
    });
  });

  group('LinkMirroredLayerFieldCommand', () {
    LayerLinkRegistry linked() => LayerLinkRegistry(
      groups: [
        LayerLinkGroup(
          id: 'g1',
          members: [
            const LayerLinkMember(
              trackId: TrackId('t'),
              cutId: CutId('c1'),
              layerId: LayerId('l1'),
            ),
            const LayerLinkMember(
              trackId: TrackId('t'),
              cutId: CutId('c2'),
              layerId: LayerId('l2'),
            ),
          ],
        ),
      ],
    );

    ProjectRepository repositoryWithLink({LayerLinkRegistry? links}) =>
        ProjectRepository(
          initialProject: projectWith(
            links: links,
            cuts: [
              cut('c1', [layer('l1', name: 'first')]),
              cut('c2', [layer('l2', name: 'second')]),
            ],
          ),
        );

    UpdateLayerNameCommand rename(
      ProjectRepository repository, {
      String cutId = 'c1',
      String layerId = 'l1',
    }) => UpdateLayerNameCommand(
      repository: repository,
      cutId: CutId(cutId),
      layerId: LayerId(layerId),
      name: 'renamed',
    );

    test('one command writes EVERY mirror — linked members are the same '
        'layer seen from different cuts', () {
      final repository = repositoryWithLink(links: linked());

      rename(repository).execute();

      expect(layerOf(repository, 'c1', 'l1').name, 'renamed');
      expect(layerOf(repository, 'c2', 'l2').name, 'renamed');
    });

    test('🚨one undo restores each member its OWN previous value, not a '
        'shared one', () {
      final repository = repositoryWithLink(links: linked());
      final command = rename(repository);

      command.execute();
      command.undo();

      expect(layerOf(repository, 'c1', 'l1').name, 'first');
      expect(
        layerOf(repository, 'c2', 'l2').name,
        'second',
        reason: 'the members had different names before the link wrote one',
      );
    });

    test('an UNLINKED layer mirrors to itself alone', () {
      final repository = repositoryWithLink();

      rename(repository).execute();

      expect(layerOf(repository, 'c1', 'l1').name, 'renamed');
      expect(layerOf(repository, 'c2', 'l2').name, 'second');
    });

    test('🚨executing TWICE remembers each member\'s value from the FIRST '
        'time — every mirror still walks all the way back', () {
      final repository = repositoryWithLink(links: linked());
      final command = rename(repository);

      command.execute();
      command.execute();
      command.undo();

      expect(layerOf(repository, 'c1', 'l1').name, 'first');
      expect(
        layerOf(repository, 'c2', 'l2').name,
        'second',
        reason:
            '`=` would have re-read the targets while the new name was '
            'standing, and the undo would restore "renamed" everywhere',
      );
    });

    test('and redo-then-undo lands there too', () {
      final repository = repositoryWithLink(links: linked());
      final command = rename(repository);

      command.execute();
      command.undo();
      command.execute();
      command.undo();

      expect(layerOf(repository, 'c1', 'l1').name, 'first');
      expect(layerOf(repository, 'c2', 'l2').name, 'second');
    });
    test('undo before execute is refused', () {
      expect(rename(repositoryWithLink()).undo, throwsStateError);
    });
  });
}
