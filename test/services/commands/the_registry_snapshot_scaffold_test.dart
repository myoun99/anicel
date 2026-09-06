// THE UNDO SCAFFOLD THE LINK-REGISTRY COMMANDS SHARE: refuse to undo what
// was never executed, walk the command's own inverse, then put the link
// registry back exactly as it stood before the first execute.
//
// Four commands wrote that scaffold out by hand and nothing named it
// (audit round 8). These pins drive all four through the same three
// questions, so a copy that starts answering differently is caught here
// rather than by whichever command happens to have a test of its own.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/commands/create_folder_command.dart';
import 'package:anicel/src/services/commands/delete_layer_command.dart';
import 'package:anicel/src/services/commands/dissolve_folder_command.dart';
import 'package:anicel/src/services/commands/unlink_layer_command.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  const folderId = LayerId('folder-under-test');

  late ProjectRepository repository;
  late Cut cut;

  setUp(() {
    repository = ProjectRepository(initialProject: createDefaultProject());
    cut = repository.requireProject().tracks.first.cuts.first;
  });

  LayerLinkRegistry registryNow() => repository.requireProject().linkRegistry;

  void makeFolder() {
    CreateFolderCommand(
      repository: repository,
      cutId: cut.id,
      name: 'Folder',
      memberLayerIds: [cut.layers.first.id],
      folderIdByCut: {cut.id: folderId},
      groupId: 'group-under-test',
    ).execute();
  }

  /// One entry per command, each built fresh so "never executed" is a real
  /// state rather than a leftover.
  Map<String, Command Function()> commands() => {
    'CreateFolderCommand': () => CreateFolderCommand(
      repository: repository,
      cutId: cut.id,
      name: 'Folder',
      memberLayerIds: [cut.layers.first.id],
      folderIdByCut: {cut.id: const LayerId('folder-fresh')},
      groupId: 'group-fresh',
    ),
    'DeleteLayerCommand': () => DeleteLayerCommand(
      repository: repository,
      cutId: cut.id,
      layerId: cut.layers.first.id,
    ),
    'DissolveFolderCommand': () {
      makeFolder();
      return DissolveFolderCommand(
        repository: repository,
        cutId: cut.id,
        folderId: folderId,
      );
    },
    'UnlinkLayerCommand': () => UnlinkLayerCommand(
      repository: repository,
      brushFrameStore: BrushFrameStore(),
      cutId: cut.id,
      sourceLayerId: cut.layers.first.id,
    ),
  };

  group('⛔undoing what was never executed throws, never half-applies', () {
    commands().forEach((name, build) {
      test(name, () {
        final command = build();
        final before = registryNow();
        expect(command.undo, throwsA(isA<StateError>()));
        expect(
          registryNow().groups.length,
          before.groups.length,
          reason: 'the refusal touched nothing',
        );
      });
    });
  });

  group('the registry comes back exactly as it stood', () {
    commands().forEach((name, build) {
      test(name, () {
        final command = build();
        final before = registryNow();
        command.execute();
        command.undo();

        expect(
          registryNow().groups.map((group) => group.id).toList(),
          before.groups.map((group) => group.id).toList(),
          reason: 'the snapshot is the registry from BEFORE the execute',
        );
      });
    });
  });

  group('execute → undo → execute → undo, and the registry still matches', () {
    commands().forEach((name, build) {
      test(name, () {
        final command = build();
        final before = registryNow();
        command.execute();
        command.undo();
        command.execute();
        command.undo();

        expect(
          registryNow().groups.map((group) => group.id).toList(),
          before.groups.map((group) => group.id).toList(),
          reason:
              '⛔the snapshot is taken ONCE — a redo that re-snapshots '
              'records the state the redo is about to overwrite',
        );
      });
    });
  });

  test('the folder command\'s own inverse runs too: the row goes and the '
      'member is released', () {
    final memberId = cut.layers.first.id;
    final command = CreateFolderCommand(
      repository: repository,
      cutId: cut.id,
      name: 'Folder',
      memberLayerIds: [memberId],
      folderIdByCut: {cut.id: folderId},
      groupId: 'group-under-test',
    );
    command.execute();
    expect(
      requireCut(
        repository.requireProject(),
        cut.id,
      ).layers.any((layer) => layer.id == folderId),
      isTrue,
    );

    command.undo();

    final layers = requireCut(repository.requireProject(), cut.id).layers;
    expect(layers.any((layer) => layer.id == folderId), isFalse);
    expect(layers.firstWhere((layer) => layer.id == memberId).folderId, isNull);
  });
}
