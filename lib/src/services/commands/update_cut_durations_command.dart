import '../../models/cut_id.dart';
import '../command.dart';
import '../project_repository.dart';

/// One undoable cut edge-drag step (storyboard grips): applies a set of
/// cut durations AND leading gaps at once — an end trim can consume the
/// following cut's gap, a start slide edits only the gap. Execute is
/// idempotent.
///
/// The fade-durability transform maps (W4) are gone (R4): the fade keys
/// live on the TRACK's global axis now, and a cut trim is a cut edit that
/// moves no keys — the user's independence rule.
class UpdateCutDurationsCommand implements Command {
  UpdateCutDurationsCommand({
    required this.repository,
    required this.before,
    required this.after,
    this.beforeGaps = const {},
    this.afterGaps = const {},
  }) : assert(before.keys.length == after.keys.length),
       assert(beforeGaps.keys.length == afterGaps.keys.length);

  final ProjectRepository repository;
  final Map<CutId, int> before;
  final Map<CutId, int> after;
  final Map<CutId, int> beforeGaps;
  final Map<CutId, int> afterGaps;

  @override
  String get description => 'Trim cut duration';

  void _apply(Map<CutId, int> durations, Map<CutId, int> gaps) {
    for (final entry in durations.entries) {
      repository.updateCutDuration(cutId: entry.key, duration: entry.value);
    }
    for (final entry in gaps.entries) {
      repository.updateCutLeadingGap(
        cutId: entry.key,
        leadingGapFrames: entry.value,
      );
    }
  }

  @override
  void execute() => _apply(after, afterGaps);

  @override
  void undo() => _apply(before, beforeGaps);
}
