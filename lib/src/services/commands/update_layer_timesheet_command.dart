import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

class UpdateLayerTimesheetCommand implements Command {
  UpdateLayerTimesheetCommand({
    required this.repository,
    required this.cutId,
    required this.layerId,
    required this.onTimesheet,
  });

  final ProjectRepository repository;

  /// Bookkeeping only — the write is layer-addressed (anywhere lookup);
  /// null when the flip lands from a gap (no active cut, B5③ 2026-08-17:
  /// the storyboard rail flips TRACK fixtures' flags).
  final CutId? cutId;
  final LayerId layerId;
  final bool onTimesheet;

  bool? _previousOnTimesheet;
  bool _hasExecuted = false;

  @override
  String get description => 'Update layer timesheet flag $layerId';

  @override
  void execute() {
    // Anywhere lookup: track-owned SE rows are not in the cut's layer list
    // but gate their sheet columns like every row (unified layer controls).
    final layer = requireLayerAnywhere(repository.requireProject(), layerId);
    _previousOnTimesheet ??= layer.onTimesheet;

    repository.updateLayerTimesheet(
      cutId: cutId,
      layerId: layerId,
      onTimesheet: onTimesheet,
    );
    _hasExecuted = true;
  }

  @override
  void undo() {
    final previousOnTimesheet = _previousOnTimesheet;
    if (!_hasExecuted || previousOnTimesheet == null) {
      throw StateError('Command has not been executed.');
    }

    requireLayerAnywhere(repository.requireProject(), layerId);
    repository.updateLayerTimesheet(
      cutId: cutId,
      layerId: layerId,
      onTimesheet: previousOnTimesheet,
    );
  }
}
