// LINK-DUPLICATING A LAYER ROUND-TRIPS: THE COPY LANDS RIGHT AFTER ITS
// SOURCE AND JOINS IT IN ONE LINK GROUP; UNDO REMOVES THE COPY AND THE
// GROUP.
//
// No test named this command file (audit 2026-09-03); the coordinator
// tests reach it through linkDuplicateLayer. These pins drive it directly.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
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
}
