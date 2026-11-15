// A PLACEMENT EDIT ROUND-TRIPS: THE ORDER AND THE FOLDER MEMBERSHIPS IT
// NAMES CHANGE TOGETHER, AND UNDO PUTS BOTH BACK.
//
// No test named this command file (audit 2026-09-04); the row drags reached
// it through the session. These pins drive it directly on one cut: a
// folder written in around one row, then the command that turns the
// drawing rows over and releases the member.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_sections.dart';
import 'package:anicel/src/services/commands/set_layer_placement_command.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';
import '../../helpers/a_folder_written_around_a_row.dart';

void main() {
  const folderId = LayerId('folder-under-test');
  late ProjectRepository repository;
  late Cut cut;
  late Layer member;
  late List<LayerId> orderBefore;
  late List<LayerId> turnedOver;

  List<Layer> layers() => requireCut(repository.requireProject(), cut.id).layers;
  List<LayerId> idsNow() => [for (final layer in layers()) layer.id];
  Layer memberNow() => layers().firstWhere((layer) => layer.id == member.id);

  setUp(() {
    repository = ProjectRepository(initialProject: createDefaultProject());
    cut = repository.requireProject().tracks.first.cuts.first;
    member = cut.layers.first;
    writeAFolderAround(
      repository,
      cutId: cut.id,
      member: member.id,
      folderId: folderId,
    );
    orderBefore = idsNow();
    // The drawing rows turned over, the rest where they stand: a cut keeps
    // its rows in section order (F-596), so that is the turn a placement
    // can make of them.
    final drawing = [
      for (final layer in layers())
        if (timelineSectionForLayerKind(layer.kind) == TimelineSection.drawing)
          layer.id,
    ];
    turnedOver = [...drawing.reversed, ...orderBefore.skip(drawing.length)];
  });

  SetLayerPlacementCommand command() => SetLayerPlacementCommand(
    repository: repository,
    cutId: cut.id,
    order: turnedOver,
    folderIds: {member.id: null},
  );

  test('execute turns the drawing rows over and releases the member', () {
    expect(memberNow().folderId, folderId, reason: 'fixture');
    expect(turnedOver, isNot(orderBefore), reason: '⛔premise: a turn');
    command().execute();
    expect(idsNow(), turnedOver);
    expect(memberNow().folderId, isNull);
  });

  test('undo restores the order and the membership; execute re-applies', () {
    final placement = command();
    placement.execute();
    placement.undo();
    expect(idsNow(), orderBefore);
    expect(memberNow().folderId, folderId);
    placement.execute();
    expect(idsNow(), turnedOver);
    expect(memberNow().folderId, isNull);
  });

  test('undo before execute is refused', () {
    expect(command().undo, throwsStateError);
  });
}
