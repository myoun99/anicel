import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart' show createFolderLayer;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/commands/cut_command_input_planner.dart';
import 'package:anicel/src/services/commands/import_media_command.dart';
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

/// 🗣️F-398 (유저 2026-10-18): 「배치 통해 만들어진 레이어(이미지,애니메이션?)가
/// 겸용컷에서 링크가 안됨. 관련 링크안되는것들 다른것도 조사 법 통일」 — a row
/// an import or a paste puts in a 겸용 cut is an ADDED row: its sibling gets
/// it too, joined to it, as Add Layer gives it.
void main() {
  const a = CutId('a');
  const b = CutId('b');

  Layer row(
    String id, {
    LayerKind kind = LayerKind.animation,
    String? folder,
  }) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    kind: kind,
    folderId: folder == null ? null : LayerId(folder),
  );

  Cut cut(CutId id, List<Layer> layers) => Cut(
    id: id,
    name: id.value,
    layers: layers,
    duration: 12,
    canvasSize: const CanvasSize(width: 100, height: 100),
  );

  LayerLinkMember member(CutId cutId, String layer) => LayerLinkMember(
    trackId: const TrackId('t'),
    cutId: cutId,
    layerId: LayerId(layer),
  );

  /// Two 겸용 cuts sharing one row.
  ProjectRepository linkedPair() => ProjectRepository(
    initialProject: Project(
      id: const ProjectId('p'),
      name: 'P',
      createdAt: DateTime.utc(2026, 10, 21),
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'V',
          cuts: [
            cut(a, [row('shared-a')]),
            cut(b, [row('shared-b')]),
          ],
        ),
      ],
      linkRegistry: LayerLinkRegistry(
        groups: [
          LayerLinkGroup(
            id: 'link-0',
            members: [member(a, 'shared-a'), member(b, 'shared-b')],
          ),
        ],
      ),
    ),
  );

  Cut cutOf(ProjectRepository repository, CutId id) => repository
      .requireProject()
      .tracks
      .single
      .cuts
      .firstWhere((cut) => cut.id == id);

  LayerId? copyInB(ProjectRepository repository, LayerId id) => repository
      .requireProject()
      .linkRegistry
      .counterpartIn(cutId: a, layerId: id, targetCutId: b);

  test('an import\'s rows land in the sibling too — a folder with the row '
      'it holds — and its undo takes them all back', () {
    final repository = linkedPair();
    // A PSD's order: the folder row above the row it holds.
    final rows = [
      row('held', folder: 'folder'),
      createFolderLayer(id: const LayerId('folder'), name: 'Folder'),
      row('still', kind: LayerKind.image),
    ];
    final command = ImportMediaCommand(
      repository: repository,
      editingSession: EditingSessionState(activeCutId: a),
      targetCutId: a,
      newLayers: rows,
      layerPlans: planAddLayersCommandInput(
        project: repository.requireProject(),
        cutId: a,
        layers: rows,
      ),
    );

    command.execute();
    final held = copyInB(repository, const LayerId('held'));
    final folder = copyInB(repository, const LayerId('folder'));
    final still = copyInB(repository, const LayerId('still'));
    expect([held, folder, still], everyElement(isNotNull));
    final sibling = cutOf(repository, b).layers;
    expect(
      sibling.byId(held!)!.folderId,
      folder,
      reason: 'the copy is held by its own cut\'s copy of the folder',
    );
    expect(sibling.byId(folder!)!.kind, LayerKind.folder);
    expect(sibling.byId(still!)!.kind, LayerKind.image);

    command.undo();
    expect([for (final layer in cutOf(repository, b).layers) layer.id], [
      const LayerId('shared-b'),
    ]);
    expect(
      [for (final group in repository.requireProject().linkRegistry.groups)
        group.id],
      ['link-0'],
    );

    command.execute();
    expect(
      copyInB(repository, const LayerId('held')),
      held,
      reason: 'a redo puts the same rows back',
    );
  });

  test('a folder of the batch the sibling cannot hold takes the rows it '
      'holds with it', () {
    final repository = linkedPair();
    // A folder of this cut alone: nothing in the sibling to hold a copy.
    repository.insertLayer(
      cutId: a,
      layer: createFolderLayer(id: const LayerId('lone'), name: 'Lone'),
    );
    final rows = [
      row('held', folder: 'inner'),
      createFolderLayer(
        id: const LayerId('inner'),
        name: 'Inner',
      ).copyWith(folderId: const LayerId('lone')),
    ];

    final plans = planAddLayersCommandInput(
      project: repository.requireProject(),
      cutId: a,
      layers: rows,
    );

    expect(plans.map((plan) => plan.mirrors), everyElement(isEmpty));
  });

  test('a duplicated row lands in the sibling too, under an id of its own', () {
    final repository = linkedPair();
    final coordinator = CutCommandCoordinator(
      repository: repository,
      editingSession: EditingSessionState(activeCutId: a),
      historyManager: HistoryManager(),
    );

    final copy = coordinator
        .duplicateLayer(cutId: a, sourceLayerId: const LayerId('shared-a'))
        .layerId;

    final inB = copyInB(repository, copy);
    expect(inB, isNotNull);
    expect(inB, isNot(copy), reason: 'the paste took the first free id');
    expect(cutOf(repository, b).layers.byId(inB!), isNotNull);
  });

  List<LayerId> idsIn(ProjectRepository repository, CutId id) => [
    for (final layer in cutOf(repository, id).layers) layer.id,
  ];

  test('a link paste lands in the sibling too, above its own row there, '
      'linked with them all — and its undo takes both back', () {
    final repository = linkedPair();
    // A row of the sibling's own under its shared one: its seat there is
    // its own, not the one aimed at here.
    repository.insertLayer(cutId: b, layer: row('own-b'), index: 0);
    final history = HistoryManager();
    final coordinator = CutCommandCoordinator(
      repository: repository,
      editingSession: EditingSessionState(activeCutId: a),
      historyManager: history,
    );

    final copy = coordinator.linkDuplicateLayer(
      cutId: a,
      layerId: const LayerId('shared-a'),
      insertionIndex: 1,
    );

    expect(idsIn(repository, a), [const LayerId('shared-a'), copy]);
    final inB = idsIn(repository, b);
    expect(inB, hasLength(3));
    expect(inB.take(2), [const LayerId('own-b'), const LayerId('shared-b')]);
    final copyB = inB.last;
    expect(copyB, isNot(copy));
    expect(
      [
        for (final group in repository.requireProject().linkRegistry.groups)
          [for (final member in group.members) member.layerId],
      ],
      [
        [const LayerId('shared-a'), const LayerId('shared-b'), copy, copyB],
      ],
      reason: 'one picture: the copies are windows onto it in both cuts',
    );

    history.undo();
    expect(idsIn(repository, b), [
      const LayerId('own-b'),
      const LayerId('shared-b'),
    ]);
    expect(
      repository.requireProject().linkRegistry.groups.single.members,
      hasLength(2),
    );

    history.redo();
    expect(idsIn(repository, b).last, copyB, reason: 'the same row again');
  });

  test('a link paste of a group carrying its folder ties the copied folders '
      'to each other, never to the folder they copy — and no two of its '
      'groups share an id', () {
    Layer rider(CutId cutId) => Layer(
      id: LayerId('rider-${cutId.value}'),
      name: 'rider',
      frames: const [],
      attachedToLayerId: LayerId('base-${cutId.value}'),
      folderId: LayerId('org-${cutId.value}'),
    );
    List<Layer> rows(CutId id) => [
      row('base-${id.value}'),
      rider(id),
      createFolderLayer(id: LayerId('org-${id.value}'), name: 'Org'),
    ];
    LayerLinkGroup pair(String id, String row) => LayerLinkGroup(
      id: id,
      members: [member(a, '$row-a'), member(b, '$row-b')],
    );
    final repository = ProjectRepository(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 10, 21),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V',
            cuts: [cut(a, rows(a)), cut(b, rows(b))],
          ),
        ],
        linkRegistry: LayerLinkRegistry(
          // The riders are each their own cut's: a copy joins its rider in
          // a group of their own, in either cut.
          groups: [pair('link-base', 'base'), pair('link-org', 'org')],
        ),
      ),
    );
    final coordinator = CutCommandCoordinator(
      repository: repository,
      editingSession: EditingSessionState(activeCutId: a),
      historyManager: HistoryManager(),
    );

    coordinator.linkDuplicateLayer(
      cutId: a,
      layerId: const LayerId('base-a'),
      insertionIndex: 3,
    );

    final sibling = cutOf(repository, b).layers;
    expect(sibling, hasLength(6));
    final [baseCopy, riderCopy, orgCopy] = sibling.sublist(3);
    expect(riderCopy.attachedToLayerId, baseCopy.id);
    expect(riderCopy.folderId, orgCopy.id);
    expect(orgCopy.kind, LayerKind.folder);
    final registry = repository.requireProject().linkRegistry;
    final orgCopyHere = cutOf(repository, a).layers.last.id;
    expect(
      registry.counterpartIn(
        cutId: a,
        layerId: orgCopyHere,
        targetCutId: b,
      ),
      orgCopy.id,
    );
    expect(
      registry.groups
          .singleWhere((group) => group.id == 'link-org')
          .members
          .map((member) => member.layerId),
      [const LayerId('org-a'), const LayerId('org-b')],
    );
    expect(
      registry
          .groupOf(cutId: b, layerId: riderCopy.id)
          ?.members
          .map((member) => member.layerId),
      [const LayerId('rider-b'), riderCopy.id],
      reason: 'the rider\'s copy shares its rider\'s picture',
    );
    final ids = [for (final group in registry.groups) group.id];
    expect(ids.toSet(), hasLength(ids.length));
  });
}
