import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_folder.dart' show createFolderLayer;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/project_timeline.dart';
import 'package:anicel/src/models/timeline_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/commands/cut_command_input_planner.dart';
import 'package:anicel/src/services/commands/update_layer_blend_mode_command.dart';
import 'package:anicel/src/services/commands/update_layer_collapsed_command.dart';
import 'package:anicel/src/services/commands/update_layer_lanes_expanded_command.dart';
import 'package:anicel/src/services/commands/update_layer_name_command.dart';
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';

/// 🗣️F-575 (유저 2026-11-09): 「겸용컷이고 … A레이어의 이름을 바꾸는게
/// 불가능. 다른 레이어는 바뀌고 … 새 프로젝트에서 겸용컷만들고 레이어구조
/// 똑같이해서 … 성공함」 — a folder dissolved in a 겸용 cut left its link
/// group behind with no row in it; the row next added took the freed id, so
/// stood in the dead group ahead of its own, and every control written to a
/// row's whole group threw on the member that was not there.
void main() {
  const a = CutId('a');
  const b = CutId('b');
  const track = TrackId('t');

  Layer row(String id, {String? folder}) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    kind: LayerKind.animation,
    folderId: folder == null ? null : LayerId(folder),
  );

  Layer folder(String id) => createFolderLayer(id: LayerId(id), name: id);

  Cut cut(CutId id, List<Layer> layers) => Cut(
    id: id,
    name: id.value,
    layers: layers,
    duration: 12,
    canvasSize: const CanvasSize(width: 100, height: 100),
  );

  LayerLinkMember member(CutId cutId, String layer) =>
      LayerLinkMember(trackId: track, cutId: cutId, layerId: LayerId(layer));

  LayerLinkGroup linkOf(String id, List<LayerLinkMember> members) =>
      LayerLinkGroup(id: id, members: members);

  Project project({
    required List<Layer> inA,
    required List<Layer> inB,
    required List<LayerLinkGroup> groups,
  }) => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 11, 10),
    tracks: [
      Track(id: track, name: 'V', cuts: [cut(a, inA), cut(b, inB)]),
    ],
    linkRegistry: LayerLinkRegistry(groups: groups),
  );

  /// The members of [project]'s table with no row at their address.
  List<LayerLinkMember> deadMembersOf(Project project) {
    final standing = {
      for (final track in project.tracksOfEveryTimeline)
        for (final cut in track.cuts)
          for (final row in cut.layers) (cut.id, row.id),
    };
    return [
      for (final group in project.linkRegistry.groups)
        for (final member in group.members)
          if (!standing.contains((member.cutId, member.layerId))) member,
    ];
  }

  Layer rowOf(ProjectRepository repository, CutId cutId, String id) =>
      requireLayer(
        repository.requireProject(),
        cutId: cutId,
        layerId: LayerId(id),
      );

  /// Two 겸용 cuts: a row, and a folder holding one, each linked across.
  ({
    ProjectRepository repository,
    HistoryManager history,
    CutCommandCoordinator commands,
  })
  linkedPair({String folderInB = 'b-folder'}) {
    final repository = ProjectRepository(
      initialProject: project(
        inA: [
          row('a-row'),
          row('a-held', folder: 'a-folder'),
          folder('a-folder'),
        ],
        inB: [
          row('b-row'),
          row('b-held', folder: folderInB),
          folder(folderInB),
        ],
        groups: [
          linkOf('link-row', [member(a, 'a-row'), member(b, 'b-row')]),
          linkOf('link-held', [member(a, 'a-held'), member(b, 'b-held')]),
          linkOf('link-folder', [member(a, 'a-folder'), member(b, folderInB)]),
        ],
      ),
    );
    final history = HistoryManager();
    return (
      repository: repository,
      history: history,
      commands: CutCommandCoordinator(
        repository: repository,
        editingSession: EditingSessionState(activeCutId: a),
        historyManager: history,
        brushFrameStore: BrushFrameStore(),
      ),
    );
  }

  final doors = <String, void Function(CutCommandCoordinator commands)>{
    'a row deleted': (commands) =>
        commands.deleteLayer(cutId: a, layerId: const LayerId('a-row')),
    'a row deleted from its other cut': (commands) =>
        commands.deleteLayer(cutId: b, layerId: const LayerId('b-row')),
    'a folder dissolved': (commands) =>
        commands.dissolveFolder(cutId: a, folderId: const LayerId('a-folder')),
    'a folder dissolved from its other cut': (commands) =>
        commands.dissolveFolder(cutId: b, folderId: const LayerId('b-folder')),
    'a folder deleted with what it holds': (commands) =>
        commands.deleteLayer(cutId: a, layerId: const LayerId('a-folder')),
    'a cut deleted': (commands) => commands.deleteCut(cutId: b),
  };

  for (final MapEntry(key: name, value: door) in doors.entries) {
    test('$name: no link is left naming a row that is gone, and the undo '
        'puts every link back', () {
      final (:repository, :history, :commands) = linkedPair();
      final before = repository.requireProject().linkRegistry;

      door(commands);
      expect(deadMembersOf(repository.requireProject()), isEmpty);

      history.undo();
      final undone = repository.requireProject();
      expect(undone.linkRegistry.groups, before.groups);
      expect(deadMembersOf(undone), isEmpty);

      history.redo();
      expect(deadMembersOf(repository.requireProject()), isEmpty);
    });
  }

  test('a row added where a dissolved folder stood is in one group, and is '
      'renamed from either cut', () {
    // `layer-1` is the first free id, which the new row's copy takes when
    // the folder that wore it has gone.
    final (:repository, :history, :commands) = linkedPair(
      folderInB: 'layer-1',
    );
    commands.dissolveFolder(cutId: a, folderId: const LayerId('a-folder'));
    history.execute(
      plannedAddLayerCommand(
        repository: repository,
        cutId: a,
        layer: row('a-new'),
      ),
    );

    final links = repository.requireProject().linkRegistry;
    expect(
      links.counterpartIn(
        cutId: a,
        layerId: const LayerId('a-new'),
        targetCutId: b,
      ),
      const LayerId('layer-1'),
      reason: 'fixture: the copy wears the id the folder left',
    );
    expect(links.groupOf(cutId: b, layerId: const LayerId('layer-1'))!.members, [
      member(a, 'a-new'),
      member(b, 'layer-1'),
    ]);

    commands.renameLayer(
      cutId: b,
      layerId: const LayerId('layer-1'),
      name: 'A',
    );
    expect(rowOf(repository, a, 'a-new').name, 'A');
    expect(rowOf(repository, b, 'layer-1').name, 'A');
  });

  group('a project that comes in naming a row that is gone', () {
    // The state F-575's file was in: `b-row` in a dead group, ahead of the
    // group of the row it really shares its pictures with.
    Project asTheFileHadIt() => project(
      inA: [row('a-row')],
      inB: [row('b-row')],
      groups: [
        linkOf('link-dead', [member(a, 'gone'), member(b, 'b-row')]),
        linkOf('link-live', [member(a, 'a-row'), member(b, 'b-row')]),
      ],
    );

    void expectRepaired(ProjectRepository repository) {
      final project = repository.requireProject();
      expect(deadMembersOf(project), isEmpty);
      expect(
        project.linkRegistry
            .groupOf(cutId: b, layerId: const LayerId('b-row'))!
            .id,
        'link-live',
      );
      expect(
        project.linkRegistry.groups.map((group) => group.id),
        ['link-live'],
      );
    }

    test('is repaired when it is opened', () {
      expectRepaired(ProjectRepository(initialProject: asTheFileHadIt()));
    });

    test('is repaired when it replaces the one open', () {
      final repository = ProjectRepository(
        initialProject: project(inA: [row('a')], inB: [row('b')], groups: []),
      )..replaceProject(asTheFileHadIt());
      expectRepaired(repository);
    });

    // The controls the card names, each written to the row's whole group.
    final controls =
        <String, void Function(ProjectRepository repository, LayerId id)>{
          'its name': (repository, id) => UpdateLayerNameCommand(
            repository: repository,
            cutId: b,
            layerId: id,
            name: 'A',
          ).execute(),
          'its attach fold': (repository, id) => UpdateLayerCollapsedCommand(
            repository: repository,
            cutId: b,
            layerId: id,
            collapsed: true,
          ).execute(),
          'its fx lanes': (repository, id) => UpdateLayerLanesExpandedCommand(
            repository: repository,
            cutId: b,
            layerId: id,
            expanded: true,
          ).execute(),
          'its blend mode': (repository, id) => UpdateLayerBlendModeCommand(
            repository: repository,
            cutId: b,
            layerId: id,
            blendMode: LayerBlendMode.multiply,
          ).execute(),
        };

    final reads = <String, Object? Function(Layer row)>{
      'its name': (row) => row.name,
      'its attach fold': (row) => row.collapsed,
      'its fx lanes': (row) => row.lanesExpanded,
      'its blend mode': (row) => row.blendMode,
    };

    for (final MapEntry(key: name, value: control) in controls.entries) {
      test('writes $name to the row it really shares it with', () {
        final repository = ProjectRepository(
          initialProject: asTheFileHadIt(),
        );
        final before = reads[name]!(rowOf(repository, a, 'a-row'));

        control(repository, const LayerId('b-row'));

        final after = reads[name]!(rowOf(repository, a, 'a-row'));
        expect(after, isNot(before));
        expect(after, reads[name]!(rowOf(repository, b, 'b-row')));
      });
    }

    test('writes its fx to the row it really shares it with', () {
      final repository = ProjectRepository(
        initialProject: asTheFileHadIt(),
      );
      final history = HistoryManager();
      final commands = CutCommandCoordinator(
        repository: repository,
        editingSession: EditingSessionState(activeCutId: b),
        historyManager: history,
        brushFrameStore: BrushFrameStore(),
      );
      final blur = LayerEffect(
        id: const EffectId('blur'),
        kind: EffectKind.brightnessContrast,
      );

      commands.updateLayerEffects(
        cutId: b,
        layerId: const LayerId('b-row'),
        effects: [blur],
      );

      expect(rowOf(repository, b, 'b-row').effects, hasLength(1));
      expect(rowOf(repository, a, 'a-row').effects, hasLength(1));
    });
  });

  test('of three, the two that stand stay linked', () {
    final repository = ProjectRepository(
      initialProject: project(
        inA: [row('a-row')],
        inB: [row('b-row')],
        groups: [
          linkOf('link', [
            member(a, 'a-row'),
            member(a, 'gone'),
            member(b, 'b-row'),
          ]),
        ],
      ),
    );

    expect(repository.requireProject().linkRegistry.groups.single.members, [
      member(a, 'a-row'),
      member(b, 'b-row'),
    ]);
  });

  test('a row of that id in another cut is not the row the link names', () {
    final repository = ProjectRepository(
      initialProject: project(
        inA: [row('same')],
        inB: [row('b-row')],
        groups: [
          // No row `same` stands in b: the one in a is another cut's.
          linkOf('link', [member(b, 'same'), member(b, 'b-row')]),
        ],
      ),
    );

    expect(repository.requireProject().linkRegistry.groups, isEmpty);
  });

  test('a row standing in a timeline not open stands', () {
    const open = CutId('open');
    const away = CutId('away');
    Track trackOf(String id, CutId cutId, String rowId) => Track(
      id: TrackId(id),
      name: id,
      cuts: [
        cut(cutId, [row(rowId)]),
      ],
    );
    final links = linkOf('link', [
      LayerLinkMember(
        trackId: const TrackId('t1'),
        cutId: open,
        layerId: const LayerId('open-row'),
      ),
      LayerLinkMember(
        trackId: const TrackId('t2'),
        cutId: away,
        layerId: const LayerId('away-row'),
      ),
    ]);
    final repository = ProjectRepository(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 11, 10),
        timelines: [
          ProjectTimeline(
            id: const TimelineId('tl-1'),
            number: 1,
            tracks: [trackOf('t1', open, 'open-row')],
          ),
          ProjectTimeline(
            id: const TimelineId('tl-2'),
            number: 2,
            tracks: [trackOf('t2', away, 'away-row')],
          ),
        ],
        currentTimelineId: const TimelineId('tl-1'),
        linkRegistry: LayerLinkRegistry(groups: [links]),
      ),
    );

    expect(repository.requireProject().linkRegistry.groups, [links]);
  });

  test('a write that takes no row leaves the very same table', () {
    final (:repository, :history, :commands) = linkedPair();
    final before = repository.requireProject().linkRegistry;

    commands.renameLayer(
      cutId: a,
      layerId: const LayerId('a-row'),
      name: 'renamed',
    );

    expect(identical(repository.requireProject().linkRegistry, before), isTrue);
    expect(history.canUndo, isTrue);
  });
}
