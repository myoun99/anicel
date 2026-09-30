import '../../models/cut_id.dart';
import '../command.dart';
import '../project_repository.dart';
import 'transitions_ride_the_cuts.dart';

/// One undoable cut edge-drag step (storyboard grips): applies a set of
/// cut durations AND leading gaps at once — an end trim can consume the
/// following cut's gap, a start slide edits only the gap. Execute is
/// idempotent.
///
/// The fade-durability transform maps (W4) are gone (R4): the V lanes'
/// transform keys live on the TRACK's global axis, and a cut trim is a cut
/// edit that moves no keys — the user's independence rule (2026-07-29).
///
/// ⚠️The transition row is a different law (유저 2026-08-10: 「움직일때만
/// 앵커로서 앞 컷에 앵커」): its spans ride their front cut, so a trim that
/// moves the cuts behind it carries the spans across with them
/// ([TransitionsRideTheCuts]) — and an O.L rides the boundary it crosses
/// (유저 2026-09-30, F-227-ol-trim-Q1: 「경계를 따라간다」), so trimming the
/// front cut's own end carries it too and its のりしろ stay as they were.
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

  late final TransitionsRideTheCuts _ride = TransitionsRideTheCuts(repository);

  @override
  void execute() => _ride.carry(() => _apply(after, afterGaps));

  @override
  void undo() => _ride.carryBack(() => _apply(before, beforeGaps));
}
