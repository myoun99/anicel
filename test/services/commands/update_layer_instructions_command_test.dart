// A LAYER'S INSTRUCTION EVENTS ROUND-TRIP THROUGH THEIR COMMAND.
//
// No test named this command file (audit 2026-09-04); the instruction row
// reached it through the session. These pins drive it directly: execute
// replaces the events, undo restores the map captured at the FIRST
// execute, and a layer that is not there is refused before anything is
// written.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/commands/update_layer_instructions_command.dart';
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

  Map<int, InstructionEvent> eventsOf() => requireLayer(
    repository.requireProject(),
    cutId: cutId,
    layerId: layerId,
  ).instructions;

  test('execute replaces the events, undo restores them, execute '
      're-applies', () {
    final before = Map<int, InstructionEvent>.of(eventsOf());
    final command = UpdateLayerInstructionsCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      instructions: const {2: InstructionEvent(instructionId: 'ol', length: 3)},
    );
    command.execute();
    expect(eventsOf().keys, [2]);
    expect(eventsOf()[2]!.length, 3);
    command.undo();
    expect(eventsOf(), before);
    command.execute();
    expect(eventsOf().keys, [2]);
  });

  test('undo restores what the first execute saw, not a later edit', () {
    final before = Map<int, InstructionEvent>.of(eventsOf());
    final command = UpdateLayerInstructionsCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      instructions: const {2: InstructionEvent(instructionId: 'ol', length: 3)},
    );
    command.execute();
    UpdateLayerInstructionsCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      instructions: const {5: InstructionEvent(instructionId: 'fi', length: 2)},
    ).execute();
    command.undo();
    expect(eventsOf(), before);
  });

  test('a layer that is not there is refused, and undo stays refused', () {
    final command = UpdateLayerInstructionsCommand(
      repository: repository,
      cutId: cutId,
      layerId: const LayerId('no-such-layer'),
      instructions: const {},
    );
    expect(command.execute, throwsA(isA<Error>()));
    expect(command.undo, throwsStateError);
  });
}
