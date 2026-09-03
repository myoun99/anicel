// A LAYER'S EFFECT CHAIN ROUND-TRIPS THROUGH ITS COMMAND.
//
// No test named this command file (audit 2026-09-04); the effects panel
// reached it through the session. These pins drive it directly: execute
// replaces the chain, undo restores the chain captured at the FIRST
// execute, and a layer that is not there is refused before anything is
// written.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/commands/update_layer_effects_command.dart';
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

  Iterable<EffectId> effectIds() =>
      requireLayerAnywhere(repository.requireProject(), layerId).effects
          .map((effect) => effect.id);

  test('execute replaces the chain, undo restores it, execute re-applies', () {
    final before = effectIds().toList();
    final command = UpdateLayerEffectsCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      effects: [
        LayerEffect.defaults(id: const EffectId('e1'), kind: EffectKind.blur),
      ],
    );
    command.execute();
    expect(effectIds(), [const EffectId('e1')]);
    command.undo();
    expect(effectIds(), before);
    command.execute();
    expect(effectIds(), [const EffectId('e1')]);
  });

  test('undo restores what the first execute saw, not a later edit', () {
    final before = effectIds().toList();
    final command = UpdateLayerEffectsCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      effects: [
        LayerEffect.defaults(id: const EffectId('e1'), kind: EffectKind.blur),
      ],
    );
    command.execute();
    UpdateLayerEffectsCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      effects: [
        LayerEffect.defaults(
          id: const EffectId('e2'),
          kind: EffectKind.brightnessContrast,
        ),
      ],
    ).execute();
    command.undo();
    expect(effectIds(), before);
  });

  test('a layer that is not there is refused, and undo stays refused', () {
    final command = UpdateLayerEffectsCommand(
      repository: repository,
      cutId: cutId,
      layerId: const LayerId('no-such-layer'),
      effects: const [],
    );
    expect(command.execute, throwsA(isA<Error>()));
    expect(command.undo, throwsStateError);
  });
}
