import '../../models/cut.dart';
import '../../models/layer.dart';
import '../../services/command.dart';
import 'session_roles.dart';

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
/// ⛔The GAP GUARD is part of the envelope, not of each sweep. All three
/// opened with the same four lines — read the active cut, stand down when
/// there is none, keep its id for the commands — and a sweep that forgot
/// them would throw from a gap instead of doing nothing (the audit's clone
/// scan named the third copy, 2026-09-07).
///
/// Answers whether anything was swept: an empty sweep writes no history
/// entry, so the caller has nothing to tell its listeners about either.
bool sweepActiveCutRows({
  required ProjectAccess project,
  required String description,
  required List<Layer> Function(Cut cut) rows,
  required Command? Function(Cut cut, Layer layer) commandFor,
}) {
  final cut = project.activeCutOrNull;
  if (cut == null) {
    return false;
  }
  final commands = <Command>[
    for (final layer in rows(cut)) ?commandFor(cut, layer),
  ];
  if (commands.isEmpty) {
    return false;
  }
  project.historyManager.execute(
    CompositeCommand(description: description, commands: commands),
  );
  return true;
}
