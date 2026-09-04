import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../project_repository.dart';
import 'layer_field_command.dart';

/// Flips a layer's timesheet-column flag — one undo step.
class UpdateLayerTimesheetCommand extends LayerFieldCommand<bool> {
  /// [cutId] is bookkeeping only — the write is layer-addressed (anywhere
  /// lookup); null when the flip lands from a gap (no active cut, B5③
  /// 2026-08-17: the storyboard rail flips TRACK fixtures' flags).
  UpdateLayerTimesheetCommand({
    required ProjectRepository repository,
    required CutId? cutId,
    required LayerId layerId,
    required bool onTimesheet,
  }) : super(
         repository: repository,
         layerId: layerId,
         value: onTimesheet,
         field: (
           name: 'timesheet flag',
           label: null,
           read: (layer) => layer.onTimesheet,
           write: (value) => repository.updateLayerTimesheet(
             cutId: cutId,
             layerId: layerId,
             onTimesheet: value,
           ),
         ),
       );
}
