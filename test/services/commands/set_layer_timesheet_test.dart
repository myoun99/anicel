// SETTING A LAYER'S TIMESHEET FLAG WRITES WHEN IT CHANGES AND STAYS QUIET
// WHEN IT DOES NOT.
//
// A survivor of the mutation campaign (2026-09-03): the early return's `==`
// became `!=`, so a real change was dropped and a no-op change wrote a
// history step, and nothing noticed. These pins do.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  late ProjectRepository repository;
  late HistoryManager history;
  late CutCommandCoordinator coordinator;
  late LayerId layerId;

  bool onTimesheet() => repository
      .currentProject!
      .tracks
      .single
      .cuts
      .single
      .layers
      .firstWhere((layer) => layer.id == layerId)
      .onTimesheet;

  setUp(() {
    repository = ProjectRepository(initialProject: createDefaultProject());
    history = HistoryManager();
    final cut = repository.currentProject!.tracks.single.cuts.single;
    layerId = cut.layers.first.id;
    coordinator = CutCommandCoordinator(
      repository: repository,
      editingSession: EditingSessionState(activeCutId: cut.id),
      historyManager: history,
    );
  });

  test('a change lands on the layer, as one undo step', () {
    expect(
      onTimesheet(),
      isTrue,
      reason: 'the default cut starts on the sheet',
    );
    coordinator.setLayerTimesheet(
      cutId: repository.currentProject!.tracks.single.cuts.single.id,
      layerId: layerId,
      onTimesheet: false,
    );
    expect(onTimesheet(), isFalse);
    expect(history.undoCount, 1);
  });

  test('setting the value it already has writes nothing', () {
    coordinator.setLayerTimesheet(
      cutId: repository.currentProject!.tracks.single.cuts.single.id,
      layerId: layerId,
      onTimesheet: true,
    );
    expect(onTimesheet(), isTrue);
    expect(history.undoCount, 0);
  });
}
