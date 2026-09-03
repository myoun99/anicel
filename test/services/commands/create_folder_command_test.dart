// CREATING A FOLDER ROUND-TRIPS: THE FOLDER APPEARS ABOVE ITS MEMBERS AND
// TAKES THEM IN; UNDO REMOVES IT AND HANDS THE MEMBERS BACK.
//
// No test named this command file (audit 2026-09-03); the coordinator
// tests reach it through linked cuts. These pins drive it directly on one
// cut.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/services/commands/create_folder_command.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  const folderId = LayerId('folder-under-test');

  late ProjectRepository repository;
  late Cut cut;
  late Layer member;

  setUp(() {
    repository = ProjectRepository(initialProject: createDefaultProject());
    cut = repository.requireProject().tracks.first.cuts.first;
    member = cut.layers.first;
  });

  Cut currentCut() => requireCut(repository.requireProject(), cut.id);

  CreateFolderCommand command() => CreateFolderCommand(
    repository: repository,
    cutId: cut.id,
    name: 'Folder',
    memberLayerIds: [member.id],
    folderIdByCut: {cut.id: folderId},
    groupId: 'group-under-test',
  );

  test('execute puts a folder above the member and the member inside', () {
    command().execute();
    final layers = currentCut().layers;
    final folder = layers.firstWhere((layer) => layer.id == folderId);
    expect(folder.kind, LayerKind.folder);
    expect(folder.name, 'Folder');
    expect(
      layers.firstWhere((layer) => layer.id == member.id).folderId,
      folderId,
    );
    expect(
      layers.indexWhere((layer) => layer.id == folderId),
      greaterThan(layers.indexWhere((layer) => layer.id == member.id)),
      reason: 'the folder row sits after (above, in row order) its member',
    );
  });

  test('undo removes the folder and hands the member back', () {
    final create = command();
    create.execute();
    create.undo();
    final layers = currentCut().layers;
    expect(layers.any((layer) => layer.id == folderId), isFalse);
    expect(
      layers.firstWhere((layer) => layer.id == member.id).folderId,
      member.folderId,
    );
    expect(layers.length, cut.layers.length);
  });

  test('execute after undo builds the folder again', () {
    final create = command();
    create.execute();
    create.undo();
    create.execute();
    expect(currentCut().layers.any((layer) => layer.id == folderId), isTrue);
  });
}
