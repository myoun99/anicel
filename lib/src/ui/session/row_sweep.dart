import '../../models/layer.dart';
import '../../services/command.dart';
import '../../services/history_manager.dart';

/// THE ROW SWEEP: one legend action over every eligible row of the active
/// cut, landing as ONE undo entry.
///
/// Three sweeps wrote this envelope out — the timesheet flag, the fill
/// references and the layer marks — and two of their comments already
/// pointed at the third ("like the sheet sweep"), which is a copy naming
/// itself. What differs is the row list, the per-row command (whose
/// nullable return also carries the "is this row eligible" predicate, so
/// the filter and the command cannot disagree) and the undo description.
///
/// Answers whether anything was swept: an empty sweep writes no history
/// entry, so the caller has nothing to tell its listeners about either.
bool sweepRows({
  required HistoryManager history,
  required List<Layer> rows,
  required String description,
  required Command? Function(Layer layer) commandFor,
}) {
  final commands = <Command>[for (final layer in rows) ?commandFor(layer)];
  if (commands.isEmpty) {
    return false;
  }
  history.execute(
    CompositeCommand(description: description, commands: commands),
  );
  return true;
}
