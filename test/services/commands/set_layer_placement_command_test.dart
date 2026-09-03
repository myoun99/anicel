// A PLACEMENT EDIT ROUND-TRIPS: THE ORDER AND THE FOLDER MEMBERSHIPS IT
// NAMES CHANGE TOGETHER, AND UNDO PUTS BOTH BACK.
//
// No test named this command file (audit 2026-09-04); the row drags reached
// it through the session. These pins drive it directly on one cut: a
// folder made by CreateFolderCommand, then the command that reverses the
// rows and releases the member.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/commands/create_folder_command.dart';
import 'package:anicel/src/services/commands/set_layer_placement_command.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  const folderId = LayerId('folder-under-test');
  late ProjectRepository repository;
  late Cut cut;
  late Layer member;
  late List<LayerId> orderBefore;

  List<Layer> layers() => requireCut(repository.requireProject(), cut.id).layers;
  List<LayerId> idsNow() => [for (final layer in layers()) layer.id];
  Layer memberNow() => layers().firstWhere((layer) => layer.id == member.id);

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
    orderBefore = idsNow();
  });

  SetLayerPlacementCommand command() => SetLayerPlacementCommand(
    repository: repository,
    cutId: cut.id,
    order: orderBefore.reversed.toList(),
    folderIds: {member.id: null},
  );

  test('execute reverses the rows and releases the member', () {
    expect(memberNow().folderId, folderId, reason: 'fixture');
    command().execute();
    expect(idsNow(), orderBefore.reversed.toList());
    expect(memberNow().folderId, isNull);
  });

  test('undo restores the order and the membership; execute re-applies', () {
    final placement = command();
    placement.execute();
    placement.undo();
    expect(idsNow(), orderBefore);
    expect(memberNow().folderId, folderId);
    placement.execute();
    expect(idsNow(), orderBefore.reversed.toList());
    expect(memberNow().folderId, isNull);
  });

  test('undo before execute is refused', () {
    expect(command().undo, throwsStateError);
  });
}
