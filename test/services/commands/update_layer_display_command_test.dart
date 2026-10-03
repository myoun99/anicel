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
import 'package:anicel/src/models/layer_blend_mode.dart';
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
    // ↩️The two fields were the opacity and the eye. The static opacity is
    // the link group's since F-278 (`UpdateLayerOpacityCommand`) and left
    // this command's snapshot; the twirl is the second field it owns here.
    final command = UpdateLayerDisplayCommand(
      repository: repository,
      layerId: original.id,
      apply: (layer) => layer.copyWith(collapsed: true, isVisible: false),
      debugLabel: 'Fold and hide',
    );
    expect(original.isVisible, isTrue, reason: 'fixture');
    expect(original.collapsed, isFalse, reason: 'fixture');

    command.execute();
    expect(current().collapsed, isTrue);
    expect(current().isVisible, isFalse);

    command.undo();
    expect(current().collapsed, original.collapsed);
    expect(current().isVisible, original.isVisible);

    command.execute();
    expect(current().collapsed, isTrue);
    expect(current().isVisible, isFalse);
  });

  test('⛔it refuses an edit of what the link group owns — the blend and '
      'the static opacity have commands of their own, and this one\'s undo '
      'would not put them back', () {
    for (final apply in <Layer Function(Layer)>[
      (layer) => layer.copyWith(opacity: 0.25),
      (layer) => layer.copyWith(blendMode: LayerBlendMode.multiply),
    ]) {
      final command = UpdateLayerDisplayCommand(
        repository: repository,
        layerId: original.id,
        apply: apply,
        debugLabel: 'Not this command\'s',
      );
      expect(command.execute, throwsAssertionError);
      expect(current().opacity, original.opacity);
      expect(current().blendMode, original.blendMode);
    }
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
