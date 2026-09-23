import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/set_layer_placement_command.dart';
import 'package:anicel/src/services/commands/update_layer_audio_clips_command.dart';
import 'package:anicel/src/services/commands/update_layer_mark_command.dart';
import 'package:anicel/src/services/commands/update_layer_transform_enabled_command.dart';
import 'package:anicel/src/services/commands/update_se_name_tag_command.dart';
import 'package:anicel/src/services/project_repository.dart';

/// The last of the layer-row commands the undo stack carried unnamed.
void main() {
  Layer layer(
    String id, {
    LayerKind kind = LayerKind.image,
    bool transformEnabled = false,
  }) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    timeline: const {},
    kind: kind,
    transformEnabled: transformEnabled,
  );

  Cut cut(String id, List<Layer> layers) => Cut(
    id: CutId(id),
    name: id,
    layers: layers,
    duration: 12,
    canvasSize: const CanvasSize(width: 100, height: 100),
  );

  Project projectWith({
    required List<Cut> cuts,
    List<Layer> seLayers = const [],
    LayerLinkRegistry? links,
  }) => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 9, 5),
    linkRegistry: links,
    tracks: [
      Track(id: const TrackId('t'), name: 'V', seLayers: seLayers, cuts: cuts),
    ],
  );

  Layer rowOf(ProjectRepository repository, String cutId, String layerId) =>
      repository
          .requireProject()
          .tracks
          .single
          .cuts
          .firstWhere((c) => c.id == CutId(cutId))
          .layers
          .firstWhere((l) => l.id == LayerId(layerId));

  group('UpdateLayerMarkCommand', () {
    ProjectRepository open({LayerLinkRegistry? links}) => ProjectRepository(
      initialProject: projectWith(
        links: links,
        cuts: [
          cut('c1', [layer('l1')]),
          cut('c2', [layer('l2')]),
        ],
      ),
    );

    LayerLinkRegistry linked() => LayerLinkRegistry(
      groups: [
        LayerLinkGroup(
          id: 'g1',
          members: const [
            LayerLinkMember(
              trackId: TrackId('t'),
              cutId: CutId('c1'),
              layerId: LayerId('l1'),
            ),
            LayerLinkMember(
              trackId: TrackId('t'),
              cutId: CutId('c2'),
              layerId: LayerId('l2'),
            ),
          ],
        ),
      ],
    );

    UpdateLayerMarkCommand mark(ProjectRepository repository) =>
        UpdateLayerMarkCommand(
          repository: repository,
          cutId: const CutId('c1'),
          layerId: const LayerId('l1'),
          mark: const LayerMark(process: LayerProcess.key),
        );

    test('the mark is written and undone', () {
      final repository = open();
      final command = mark(repository);

      command.execute();
      expect(rowOf(repository, 'c1', 'l1').mark.process, LayerProcess.key);

      command.undo();
      expect(rowOf(repository, 'c1', 'l1').mark.process, isNull);
    });

    test('a LINKED row marks its mirror too — linked members are the same '
        'layer seen from different cuts', () {
      final repository = open(links: linked());

      mark(repository).execute();

      expect(rowOf(repository, 'c2', 'l2').mark.process, LayerProcess.key);
    });
  });

  group('UpdateLayerTransformEnabledCommand', () {
    ProjectRepository open({LayerLinkRegistry? links}) => ProjectRepository(
      initialProject: projectWith(
        links: links,
        cuts: [
          cut('c1', [layer('l1')]),
          cut('c2', [layer('l2', transformEnabled: true)]),
        ],
      ),
    );

    UpdateLayerTransformEnabledCommand toggle(ProjectRepository repository) =>
        UpdateLayerTransformEnabledCommand(
          repository: repository,
          layerId: const LayerId('l1'),
          transformEnabled: true,
        );

    test('the switch flips and undoes', () {
      final repository = open();
      final command = toggle(repository);

      command.execute();
      expect(rowOf(repository, 'c1', 'l1').transformEnabled, isTrue);

      command.undo();
      expect(rowOf(repository, 'c1', 'l1').transformEnabled, isFalse);
    });

    test('🚨each linked member remembers its OWN previous value — one '
        'remembered bool would flatten rows that started out disagreeing', () {
      final repository = open(
        links: LayerLinkRegistry(
          groups: [
            LayerLinkGroup(
              id: 'g1',
              members: const [
                LayerLinkMember(
                  trackId: TrackId('t'),
                  cutId: CutId('c1'),
                  layerId: LayerId('l1'),
                ),
                LayerLinkMember(
                  trackId: TrackId('t'),
                  cutId: CutId('c2'),
                  layerId: LayerId('l2'),
                ),
              ],
            ),
          ],
        ),
      );
      final command = toggle(repository);

      command.execute();
      command.undo();

      expect(rowOf(repository, 'c1', 'l1').transformEnabled, isFalse);
      expect(
        rowOf(repository, 'c2', 'l2').transformEnabled,
        isTrue,
        reason: 'it started true and must go back to true',
      );
    });

    test('undo before execute is refused', () {
      expect(toggle(open()).undo, throwsStateError);
    });
  });

  group('UpdateLayerAudioClipsCommand', () {
    ProjectRepository open() => ProjectRepository(
      initialProject: projectWith(
        cuts: [cut('c', const [])],
        seLayers: [layer('se', kind: LayerKind.se)],
      ),
    );

    Layer seRow(ProjectRepository repository) =>
        repository.requireProject().tracks.single.seLayers.single;

    test('⚠️an SE row is a TRACK fixture — the write reaches it with no '
        'cut at all', () {
      final repository = open();
      final command = UpdateLayerAudioClipsCommand(
        repository: repository,
        cutId: null,
        layerId: const LayerId('se'),
        audioClips: [
          AudioClip(filePath: '/take.wav', frameId: const FrameId('f1')),
        ],
      );

      command.execute();
      expect(seRow(repository).audioClips.single.filePath, '/take.wav');

      command.undo();
      expect(seRow(repository).audioClips, isEmpty);
    });
  });

  group('UpdateSeNameTagCommand', () {
    ProjectRepository open() => ProjectRepository(
      initialProject: projectWith(
        cuts: [cut('c', const [])],
        seLayers: [layer('se', kind: LayerKind.se)],
      ),
    );

    Layer seRow(ProjectRepository repository) =>
        repository.requireProject().tracks.single.seLayers.single;

    test('a tag is set and undone', () {
      final repository = open();
      final command = UpdateSeNameTagCommand(
        repository: repository,
        layerId: const LayerId('se'),
        seNameTag: const SeNameTag(showLine: false),
      );

      command.execute();
      expect(seRow(repository).seNameTag?.showLine, isFalse);

      command.undo();
      expect(seRow(repository).seNameTag, isNull);
    });

    test('NULL resets the row to the stacked default, and undo brings the '
        'tag back', () {
      final repository = open();
      UpdateSeNameTagCommand(
        repository: repository,
        layerId: const LayerId('se'),
        seNameTag: const SeNameTag(showLine: false),
      ).execute();

      final clear = UpdateSeNameTagCommand(
        repository: repository,
        layerId: const LayerId('se'),
        seNameTag: null,
      );
      clear.execute();
      expect(seRow(repository).seNameTag, isNull);

      clear.undo();
      expect(seRow(repository).seNameTag?.showLine, isFalse);
    });

    test('undo before execute is refused', () {
      expect(
        UpdateSeNameTagCommand(
          repository: open(),
          layerId: const LayerId('se'),
          seNameTag: null,
        ).undo,
        throwsStateError,
      );
    });
  });

  group('SetLayerPlacementCommand', () {
    ProjectRepository open() => ProjectRepository(
      initialProject: projectWith(
        cuts: [
          cut('c', [layer('a'), layer('b'), layer('c')]),
        ],
      ),
    );

    List<String> orderOf(ProjectRepository repository) => [
      for (final l
          in repository.requireProject().tracks.single.cuts.single.layers)
        l.id.value,
    ];

    test('the rows resequence, and undo puts the order back', () {
      final repository = open();
      final command = SetLayerPlacementCommand(
        repository: repository,
        cutId: const CutId('c'),
        order: const [LayerId('c'), LayerId('a'), LayerId('b')],
      );

      command.execute();
      expect(orderOf(repository), ['c', 'a', 'b']);

      command.undo();
      expect(orderOf(repository), ['a', 'b', 'c']);
    });

    test('undo before execute is refused', () {
      expect(
        SetLayerPlacementCommand(
          repository: open(),
          cutId: const CutId('c'),
          order: const [LayerId('a'), LayerId('b'), LayerId('c')],
        ).undo,
        throwsStateError,
      );
    });
  });
}
