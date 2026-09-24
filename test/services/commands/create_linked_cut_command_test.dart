// CREATING A LINKED CUT ROUND-TRIPS: THE NEW CUT LANDS AFTER ITS SOURCE
// WITH EACH PLANNED LAYER LINKED TO ITS ORIGINAL, THE SESSION MOVES ONTO
// IT, AND UNDO TAKES ALL THREE BACK.
//
// No test named this command file (audit 2026-09-03); the coordinator
// tests reach it through createLinkedCut. These pins drive it directly.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/services/commands/create_linked_cut_command.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  const newCutId = CutId('linked-cut-under-test');
  const linkedLayerId = LayerId('linked-layer-under-test');

  late ProjectRepository repository;
  late EditingSessionState editingSession;
  late Cut source;
  late Layer sourceLayer;

  setUp(() {
    repository = ProjectRepository(initialProject: createDefaultProject());
    source = repository.requireProject().tracks.first.cuts.first;
    sourceLayer = source.layers.first;
    editingSession = EditingSessionState(activeCutId: source.id);
  });

  Track track() => repository.requireProject().tracks.first;

  CreateLinkedCutCommand command() => CreateLinkedCutCommand(
    repository: repository,
    editingSession: editingSession,
    sourceCutId: source.id,
    newCutId: newCutId,
    newName: 'Linked',
    layerIdMap: {sourceLayer.id: linkedLayerId},
    newGroupIdBySource: {sourceLayer.id: 'group-under-test'},
    coveringFrameIdBySource: const {},
  );

  test('execute lands the linked cut after its source and moves onto it', () {
    command().execute();
    final cuts = track().cuts;
    final sourceIndex = cuts.indexWhere((cut) => cut.id == source.id);
    final newIndex = cuts.indexWhere((cut) => cut.id == newCutId);
    expect(newIndex, sourceIndex + 1);
    final linked = cuts[newIndex];
    expect(linked.name, 'Linked');
    expect(
      linked.duration,
      defaultCutDuration,
      reason: '↩️F-97: as long as a new cut, not as its source',
    );
    expect(linked.layers.any((layer) => layer.id == linkedLayerId), isTrue);
    expect(editingSession.activeCutId, newCutId);

    final registry = repository.requireProject().linkRegistry;
    final group = registry.groupOf(cutId: newCutId, layerId: linkedLayerId);
    expect(group, isNotNull);
    expect(
      group!.contains(cutId: source.id, layerId: sourceLayer.id),
      isTrue,
      reason: 'the copy is linked to its original',
    );
  });

  test('undo removes the cut, the link, and returns to the source cut', () {
    final groupsBefore = repository.requireProject().linkRegistry.groups.length;
    final cutsBefore = track().cuts.length;
    final create = command();
    create.execute();
    create.undo();
    expect(track().cuts.length, cutsBefore);
    expect(track().cuts.any((cut) => cut.id == newCutId), isFalse);
    expect(
      repository.requireProject().linkRegistry.groups.length,
      groupsBefore,
    );
    expect(editingSession.activeCutId, source.id);
  });

  test('undo before execute is refused', () {
    expect(command().undo, throwsStateError);
  });
}
