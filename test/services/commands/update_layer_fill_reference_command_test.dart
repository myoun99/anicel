// THE FILL-REFERENCE FLAG ROUND-TRIPS THROUGH ITS COMMAND.
//
// No test named this command file (audit 2026-09-04); the layer row's
// button reached it through the session. These pins drive it directly.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/commands/update_layer_fill_reference_command.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  late ProjectRepository repository;
  late CutId cutId;
  late LayerId layerId;

  setUp(() {
    repository = ProjectRepository(initialProject: createDefaultProject());
    final cut = repository.requireProject().tracks.first.cuts.first;
    cutId = cut.id;
    layerId = cut.layers.first.id;
  });

  bool flag() =>
      requireLayerAnywhere(repository.requireProject(), layerId).isFillReference;

  test('execute sets the flag, undo restores it, execute re-applies', () {
    final before = flag();
    final command = UpdateLayerFillReferenceCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      isFillReference: !before,
    );
    command.execute();
    expect(flag(), !before);
    command.undo();
    expect(flag(), before);
    command.execute();
    expect(flag(), !before);
  });

  test('undo restores what the first execute saw, not a later edit', () {
    final before = flag();
    final command = UpdateLayerFillReferenceCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      isFillReference: !before,
    );
    command.execute();
    UpdateLayerFillReferenceCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      isFillReference: before,
    ).execute();
    command.execute();
    command.undo();
    expect(flag(), before);
  });

  test('undo before execute is refused', () {
    expect(
      UpdateLayerFillReferenceCommand(
        repository: repository,
        cutId: cutId,
        layerId: layerId,
        isFillReference: true,
      ).undo,
      throwsStateError,
    );
  });
}
