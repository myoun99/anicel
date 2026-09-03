// DISSOLVING A FOLDER ROUND-TRIPS: THE FOLDER ROW GOES AND ITS MEMBERS ARE
// RELEASED; UNDO PUTS THE ROW BACK WHERE IT WAS WITH THE MEMBERS INSIDE.
//
// No test named this command file (audit 2026-09-04); the folder menu
// reached it through the session. These pins drive it directly on one cut,
// on a folder CreateFolderCommand just made.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/commands/create_folder_command.dart';
import 'package:anicel/src/services/commands/dissolve_folder_command.dart';
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
    CreateFolderCommand(
      repository: repository,
      cutId: cut.id,
      name: 'Folder',
      memberLayerIds: [member.id],
      folderIdByCut: {cut.id: folderId},
      groupId: 'group-under-test',
    ).execute();
  });

  List<Layer> layers() => requireCut(repository.requireProject(), cut.id).layers;
  Layer memberNow() => layers().firstWhere((layer) => layer.id == member.id);
  int folderIndex() => layers().indexWhere((layer) => layer.id == folderId);

  DissolveFolderCommand command() => DissolveFolderCommand(
    repository: repository,
    cutId: cut.id,
    folderId: folderId,
  );

  test('execute removes the folder row and releases the member', () {
    expect(folderIndex(), greaterThanOrEqualTo(0), reason: 'fixture');
    expect(memberNow().folderId, folderId, reason: 'fixture');
    command().execute();
    expect(folderIndex(), -1);
    expect(memberNow().folderId, isNull);
  });

  test('undo puts the folder back at its index with the member inside; '
      'execute again dissolves it again', () {
    final indexBefore = folderIndex();
    final dissolve = command();
    dissolve.execute();
    dissolve.undo();
    expect(folderIndex(), indexBefore);
    expect(memberNow().folderId, folderId);
    dissolve.execute();
    expect(folderIndex(), -1);
    expect(memberNow().folderId, isNull);
  });

  test('undo before execute is refused', () {
    expect(command().undo, throwsStateError);
  });
}
