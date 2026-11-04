import '../../models/cut_id.dart';
import '../../models/layer_link_registry.dart';
import '../../models/project_timeline.dart';
import '../../models/timeline_id.dart';
import '../brush_frame_store.dart';
import '../command.dart';
import '../editing/editing_session_state.dart';
import '../editing/links_without_cuts.dart'
    show CelRekey, SheetInkMove, moveSheetInk, sheetInkMovesBack;
import '../project_repository.dart';

/// A change of the project's TIMELINES (I-150) — one made, copied, named or
/// deleted, or another opened — as ONE undo step, and where the user stands
/// with it: opening another stands on its first cut, and the undo stands
/// back where the change found them. The track selected is the session's
/// to reconcile: a timeline holds one V track, the one it falls back to.
///
/// The link table goes with the timelines: a copy's groups come in, and a
/// deleted one's members go (`linksWithoutCuts`) — its canonical cels
/// re-keyed onto the survivors first ([rekeys]), as a deleted cut's are.
///
/// 🗣️I-150-Q1 (recommended a; the user's answer pending): opening another
/// timeline is a step of its own. An undo after it opens the one before
/// first, so the edit the next undo takes back is the one on screen.
class ChangeTimelinesCommand implements Command {
  ChangeTimelinesCommand({
    required this.repository,
    required this.editingSession,
    required this.description,
    required this.timelines,
    required this.current,
    this.links,
    this.rekeys = const [],
    this.brushFrameStore,
    this.inkMoves = const [],
    this.sheetInkStores = const [],
  });

  final ProjectRepository repository;
  final EditingSessionState editingSession;

  @override
  final String description;

  /// The list after the step: its order, and each one's name.
  final List<ProjectTimeline> timelines;

  /// The timeline open after the step.
  final TimelineId current;

  /// The link table after the step — null where the step leaves it.
  final LayerLinkRegistry? links;

  /// The stored cels the step moves, each from where it was kept.
  final List<CelRekey> rekeys;

  /// Where [rekeys] move.
  final BrushFrameStore? brushFrameStore;

  /// The 동기컷 sheets the step hands over, each from its gone canonical
  /// ([moveSheetInk]).
  final List<SheetInkMove> inkMoves;

  /// Where [inkMoves] move.
  final List<BrushFrameStore> sheetInkStores;

  _Standing? _before;

  @override
  void execute() {
    final project = repository.requireProject();
    _before ??= (
      timelines: project.timelines,
      current: project.currentTimelineId,
      links: project.linkRegistry,
      cut: editingSession.activeCutId,
      gap: editingSession.gapGlobalFrame,
    );
    if (rekeys.isNotEmpty) {
      brushFrameStore?.rekeyFrames(rekeys);
    }
    moveSheetInk(sheetInkStores, inkMoves);
    _lay(timelines, current, links ?? project.linkRegistry);
    if (current == project.currentTimelineId) {
      return;
    }
    final opened = repository.requireProject().tracks;
    _stand(
      cut: opened.expand((track) => track.cuts).firstOrNull?.id,
      gap: null,
    );
  }

  @override
  void undo() {
    final before =
        _before ?? (throw StateError('Command has not been executed.'));
    _lay(before.timelines, before.current, before.links);
    if (rekeys.isNotEmpty) {
      brushFrameStore?.rekeyFrames([
        for (final (from, to) in rekeys) (to, from),
      ]);
    }
    moveSheetInk(sheetInkStores, sheetInkMovesBack(inkMoves));
    _stand(cut: before.cut, gap: before.gap);
  }

  void _lay(
    List<ProjectTimeline> timelines,
    TimelineId current,
    LayerLinkRegistry links,
  ) => repository.updateProject(
    (project) => project.copyWith(
      timelines: timelines,
      currentTimelineId: current,
      linkRegistry: links,
    ),
  );

  void _stand({required CutId? cut, required int? gap}) => editingSession
    ..setActiveCutId(cut)
    ..gapGlobalFrame = gap;
}

typedef _Standing = ({
  List<ProjectTimeline> timelines,
  TimelineId current,
  LayerLinkRegistry links,
  CutId? cut,
  int? gap,
});
