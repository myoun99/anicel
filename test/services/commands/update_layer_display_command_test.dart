// A DISPLAY EDIT ROUND-TRIPS: EXECUTE APPLIES, UNDO RESTORES EVERY DISPLAY
// FIELD IT SNAPSHOTTED, AND A SECOND EXECUTE (REDO) APPLIES AGAIN.
//
// No test named this command file (audit 2026-09-03); it was reached only
// through the controllers. These pins drive it directly, including the
// snapshot's reach: an `apply` that changes two fields at once is undone as
// a whole.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/services/commands/update_layer_display_command.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  late ProjectRepository repository;
  late Layer original;

  setUp(() {
    repository = ProjectRepository(initialProject: createDefaultProject());
    original = repository.requireProject().tracks.first.cuts.first.layers.first;
  });

  Layer current() =>
      requireLayerAnywhere(repository.requireProject(), original.id);

  test('execute applies, undo restores, execute again re-applies', () {
    final command = UpdateLayerDisplayCommand(
      repository: repository,
      layerId: original.id,
      apply: (layer) => layer.copyWith(opacity: 0.25, isVisible: false),
      debugLabel: 'Dim and hide',
    );
    expect(original.isVisible, isTrue, reason: 'fixture');
    expect(original.opacity, 1, reason: 'fixture');

    command.execute();
    expect(current().opacity, 0.25);
    expect(current().isVisible, isFalse);

    command.undo();
    expect(current().opacity, original.opacity);
    expect(current().isVisible, original.isVisible);

    command.execute();
    expect(current().opacity, 0.25);
    expect(current().isVisible, isFalse);
  });

  test('undo before execute is refused', () {
    final command = UpdateLayerDisplayCommand(
      repository: repository,
      layerId: original.id,
      apply: (layer) => layer,
      debugLabel: 'Nothing',
    );
    expect(command.undo, throwsStateError);
  });

  test('the description names the edit and the layer', () {
    final command = UpdateLayerDisplayCommand(
      repository: repository,
      layerId: original.id,
      apply: (layer) => layer,
      debugLabel: 'Set layer opacity',
    );
    expect(command.description, contains('Set layer opacity'));
    expect(command.description, contains(original.id.value));
  });
}
