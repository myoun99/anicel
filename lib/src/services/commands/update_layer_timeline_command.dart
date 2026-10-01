import '../../core/collection_equality.dart';
import '../../models/layer.dart';
import '../../models/timeline_repeat.dart';
import '../../models/track_transitions.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

/// The timeline/frame-bank edit funnel: swaps a layer's before/after
/// states — and, when the layer is LINKED and the edit changed its FRAME
/// BANK (cel added/removed/renamed), mirrors the bank onto every member
/// in the same command.
///
/// "레인만 각자, 나머지는 하나": timelines are per-use lanes and never
/// mirror; the bank is the shared entity, so members simply ADOPT the
/// edited layer's frames list wholesale (the invariant says the lists
/// were identical before the edit — no delta math needed). Exposures of
/// a member that referenced a now-removed cel are swept: the cel ceased
/// to exist everywhere ("한 실체"). One undo restores every member.
class UpdateLayerTimelineCommand implements Command {
  UpdateLayerTimelineCommand({
    required this.repository,
    required this.before,
    required this.after,
  });

  final ProjectRepository repository;
  final Layer before;
  final Layer after;

  List<({Layer before, Layer after})>? _mirrorPairs;

  @override
  String get description => 'Update layer timeline ${after.id}';

  @override
  void execute() {
    _mirrorPairs ??= _computeMirrorPairs();
    repository.replaceLayer(layer: after);
    for (final pair in _mirrorPairs!) {
      repository.replaceLayer(layer: pair.after);
    }
  }

  @override
  void undo() {
    repository.replaceLayer(layer: before);
    for (final pair in _mirrorPairs ?? const <({Layer before, Layer after})>[]) {
      repository.replaceLayer(layer: pair.before);
    }
  }

  List<({Layer before, Layer after})> _computeMirrorPairs() {
    // Lane-only edits (exposure moves, holds — the overwhelming
    // majority) leave the bank untouched: no mirror, no overhead beyond
    // this list compare.
    if (listEquals(before.frames, after.frames)) {
      return const [];
    }
    final project = repository.requireProject();
    final cutId = cutIdOfLayer(project, after.id);
    if (cutId == null) {
      return const []; // Track-owned SE rows are never linked.
    }
    final group = project.linkRegistry.groupOf(
      cutId: cutId,
      layerId: after.id,
    );
    if (group == null) {
      return const [];
    }

    final bankFrameIds = {for (final frame in after.frames) frame.id};
    final pairs = <({Layer before, Layer after})>[];
    for (final member in group.members) {
      if (member.cutId == cutId && member.layerId == after.id) {
        continue;
      }
      final memberBefore = requireLayer(
        project,
        cutId: member.cutId,
        layerId: member.layerId,
      );
      var memberAfter = memberBefore.copyWith(
        // Adopt the canonical bank (order and metadata included).
        frames: after.frames,
        // Sweep exposures of cels that left the bank — their own lanes
        // stay untouched otherwise.
        timeline: {
          for (final entry in memberBefore.timeline.entries)
            if (entry.value.frameId == null ||
                bankFrameIds.contains(entry.value.frameId))
              entry.key: entry.value,
        },
      );
      memberAfter = rederiveRunBehaviors(
        memberAfter,
        drawnFrameCount: cutDrawnFrameCount(project, member.cutId)!,
      );
      if (memberAfter == memberBefore) {
        continue;
      }
      pairs.add((before: memberBefore, after: memberAfter));
    }
    return pairs;
  }
}
