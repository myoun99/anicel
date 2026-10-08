// LINK-DUPLICATING A LAYER ROUND-TRIPS: THE COPY LANDS AT THE SEAT IT IS
// AIMED AT AND JOINS ITS SOURCE IN ONE LINK GROUP; UNDO REMOVES THE COPY
// AND THE GROUP.
//
// No test named this command file (audit 2026-09-03); the coordinator
// tests reach it through linkDuplicateLayer. These pins drive it directly.
//
// ↩️It landed 「right after its source」, always: the layer menu's 「링크해서
// 복제」 was its one door. It is the shared pill's linked PASTE now (I-77),
// and a paste lands where it is pressed — as a new row does
// (`newRowPlacement`).
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/services/commands/link_duplicate_layer_command.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  const copyId = LayerId('copy-under-test');

  late ProjectRepository repository;
  late Cut cut;
  late Layer source;

  setUp(() {
    repository = ProjectRepository(initialProject: createDefaultProject());
    cut = repository.requireProject().tracks.first.cuts.first;
    source = cut.layers.first;
  });

  Cut currentCut() => requireCut(repository.requireProject(), cut.id);

  LinkDuplicateLayerCommand command() => LinkDuplicateLayerCommand(
    repository: repository,
    cutId: cut.id,
    sourceLayerId: source.id,
    // The seat directly above the source — the cut's first row.
    insertionIndex: 1,
    layerIdMap: {source.id: copyId},
    newGroupIdBySource: {source.id: 'group-under-test'},
  );

  test('execute lands the copy after its source, linked to it', () {
    command().execute();
    final layers = currentCut().layers;
    final sourceIndex = layers.indexWhere((layer) => layer.id == source.id);
    final copyIndex = layers.indexWhere((layer) => layer.id == copyId);
    expect(copyIndex, sourceIndex + 1);
    expect(layers[copyIndex].name, source.name);

    final groups = repository.requireProject().linkRegistry.groups;
    final linked = groups.where(
      (group) =>
          group.contains(cutId: cut.id, layerId: source.id) &&
          group.contains(cutId: cut.id, layerId: copyId),
    );
    expect(linked, hasLength(1), reason: 'one group holds both');
  });

  test('undo removes the copy and its group', () {
    final groupsBefore = repository.requireProject().linkRegistry.groups.length;
    final duplicate = command();
    duplicate.execute();
    duplicate.undo();
    expect(currentCut().layers.any((layer) => layer.id == copyId), isFalse);
    expect(currentCut().layers.length, cut.layers.length);
    expect(
      repository.requireProject().linkRegistry.groups.length,
      groupsBefore,
    );
  });

  test('undo before execute is refused', () {
    expect(command().undo, throwsStateError);
  });

  group('the copy lands where a new row would, at the seat it is aimed at',
      () {
    Layer row(String id, {String? folder, String? rides}) => Layer(
      id: LayerId(id),
      name: id,
      frames: const [],
      folderId: folder == null ? null : LayerId(folder),
      attachedToLayerId: rides == null ? null : LayerId(rides),
    );
    Layer folderRow(String id) => Layer(
      id: LayerId(id),
      name: id,
      frames: const [],
      kind: LayerKind.folder,
    );

    /// The default project's cut, holding [rows] under its fixtures.
    void stack(List<Layer> rows) {
      final project = repository.requireProject();
      final track = project.tracks.first;
      final fixtures = [
        for (final layer in cut.layers)
          if (layer.kind != LayerKind.animation) layer,
      ];
      repository.replaceProject(
        project.copyWith(
          tracks: [
            track.copyWith(
              cuts: [
                cut.copyWith(layers: [...rows, ...fixtures]),
                ...track.cuts.skip(1),
              ],
            ),
            ...project.tracks.skip(1),
          ],
        ),
      );
    }

    List<String> drawingRows() => [
      for (final layer in currentCut().layers)
        if (layer.kind == LayerKind.animation || layer.kind.groupsLayers)
          layer.id.value,
    ];

    Layer rowNow(String id) =>
        currentCut().layers.firstWhere((layer) => layer.id.value == id);

    void linkCopy(
      String sourceId, {
      required int at,
      required Map<String, String> copies,
    }) => LinkDuplicateLayerCommand(
      repository: repository,
      cutId: cut.id,
      sourceLayerId: LayerId(sourceId),
      insertionIndex: at,
      layerIdMap: {
        for (final entry in copies.entries)
          LayerId(entry.key): LayerId(entry.value),
      },
      newGroupIdBySource: {
        for (final id in copies.keys) LayerId(id): 'group-of-$id',
      },
    ).execute();

    test('not above its source', () {
      stack([row('s'), row('x'), row('y')]);

      linkCopy('s', at: 3, copies: {'s': 's2'});

      expect(drawingRows(), ['s', 'x', 'y', 's2']);
    });

    test('aimed inside another attach group, it lands past the group', () {
      stack([row('s'), row('base'), row('over', rides: 'base'), row('y')]);

      linkCopy('s', at: 2, copies: {'s': 's2'});

      expect(drawingRows(), ['s', 'base', 'over', 's2', 'y']);
    });

    test('it joins the folder it lands in', () {
      stack([row('s'), row('m', folder: 'F'), folderRow('F'), row('y')]);

      linkCopy('s', at: 2, copies: {'s': 's2'});

      expect(drawingRows(), ['s', 'm', 's2', 'F', 'y']);
      expect(rowNow('s2').folderId, const LayerId('F'));
      expect(folderStructureProblem(currentCut().layers), isNull);
    });

    test('and leaves the one it was copied in', () {
      // ↩️A folder pointer out of the slice 「carried over unchanged」 — right
      // while the copy always landed beside its source, and a row claiming a
      // folder it is not under once it could land anywhere.
      stack([row('m', folder: 'F'), folderRow('F'), row('y')]);

      linkCopy('m', at: 3, copies: {'m': 'm2'});

      expect(drawingRows(), ['m', 'F', 'y', 'm2']);
      expect(rowNow('m2').folderId, isNull);
      expect(folderStructureProblem(currentCut().layers), isNull);
    });

    test('a folder that travels WITH the group keeps its rows: the organizer '
        'is copied, and its copy holds the copied rider', () {
      stack([
        row('base'),
        row('r', rides: 'base', folder: 'ORG'),
        folderRow('ORG'),
        row('m', folder: 'F'),
        folderRow('F'),
      ]);

      // Aimed into F, above m.
      linkCopy(
        'base',
        at: 4,
        copies: {'base': 'base2', 'r': 'r2', 'ORG': 'ORG2'},
      );

      expect(drawingRows(), [
        'base', 'r', 'ORG', 'm', 'base2', 'r2', 'ORG2', 'F', //
      ]);
      expect(rowNow('r2').folderId, const LayerId('ORG2'));
      expect(rowNow('r2').attachedToLayerId, const LayerId('base2'));
      expect(rowNow('base2').folderId, const LayerId('F'));
      expect(rowNow('ORG2').folderId, const LayerId('F'));
      expect(folderStructureProblem(currentCut().layers), isNull);
    });
  });
}
