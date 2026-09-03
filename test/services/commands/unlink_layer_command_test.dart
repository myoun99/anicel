// UNLINKING A LAYER ROUND-TRIPS: THE LAYER LEAVES ITS LINK GROUP (A GROUP
// LEFT WITH ONE MEMBER DISSOLVES), AND UNDO PUTS THE REGISTRY BACK.
//
// No test named this command file (audit 2026-09-03); the coordinator
// tests reach it through unlinkLayer. These pins drive it directly, with a
// link-duplicate as the fixture that makes a group to leave.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/commands/link_duplicate_layer_command.dart';
import 'package:anicel/src/services/commands/unlink_layer_command.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  const copyId = LayerId('copy-under-test');

  late ProjectRepository repository;
  late Cut cut;
  late Layer source;
  late int groupsBeforeLink;

  setUp(() {
    repository = ProjectRepository(initialProject: createDefaultProject());
    cut = repository.requireProject().tracks.first.cuts.first;
    source = cut.layers.first;
    groupsBeforeLink = repository.requireProject().linkRegistry.groups.length;
    LinkDuplicateLayerCommand(
      repository: repository,
      cutId: cut.id,
      sourceLayerId: source.id,
      layerIdMap: {source.id: copyId},
      newGroupIdBySource: {source.id: 'group-under-test'},
    ).execute();
  });

  bool linked(LayerId layerId) =>
      repository.requireProject().linkRegistry.groupOf(
        cutId: cut.id,
        layerId: layerId,
      ) !=
      null;

  UnlinkLayerCommand command() => UnlinkLayerCommand(
    repository: repository,
    brushFrameStore: BrushFrameStore(),
    cutId: cut.id,
    sourceLayerId: copyId,
  );

  test('fixture: the duplicate is linked to its source', () {
    expect(linked(copyId), isTrue);
    expect(linked(source.id), isTrue);
  });

  test('execute takes the layer out and dissolves the pair', () {
    command().execute();
    expect(linked(copyId), isFalse);
    expect(linked(source.id), isFalse, reason: 'a group of one dissolves');
    expect(
      repository.requireProject().linkRegistry.groups.length,
      groupsBeforeLink,
    );
  });

  test('undo restores the link', () {
    final unlink = command();
    unlink.execute();
    unlink.undo();
    expect(linked(copyId), isTrue);
    expect(linked(source.id), isTrue);
  });

  test('undo before execute is refused', () {
    expect(command().undo, throwsStateError);
  });
}
