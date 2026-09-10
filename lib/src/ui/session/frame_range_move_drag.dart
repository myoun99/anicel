import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_frame_range.dart';
import '../../models/timeline_repeat.dart';
import 'active_cut_controllers.dart';
import 'camera.dart';
import 'drags/frame_range_move_drag.dart';
import 'drawing_block_move_drag.dart';
import 'folders_and_attachments.dart';
import 'range_selections.dart';
import 'render_caches.dart';
import 'row_spans.dart';
import 'session_roles.dart';
import 'track_se_display.dart';
import 'transitions.dart';

/// The frame-range move drag's VERBS — the session-side door to
/// [FrameRangeMoveDrag] — plus the run-edge property verb that shares its
/// lattice.
///
/// 🚨The first collaborator carved out of `EditorSessionManager`
/// (2026-09-02, the audit's SRP cut). Measured before cutting: the family
/// touched 46 session members; the twenty `_rangeMove*` fields were read
/// from outside it in twenty places, which now read `rangeMove.x`.
///
/// 🚨What it does NOT keep is those fields. Round G5 (2026-09-10) gave the
/// drag the shape its six siblings in `drags/` already had: a factory that
/// answers null when the move is refused, and an object that holds the
/// mid-drag state for the drag's lifetime only. This class keeps exactly
/// one thing about a drag — whether there is one.
class FrameRangeMoveDragVerbs {
  FrameRangeMoveDragVerbs({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required ActiveCutControllers controllers,
    required SessionInternals internals,
    required RowSpans rowSpans,
    required DrawingBlockMoveDragVerbs blockMove,
    required RenderCaches renderCaches,
    required Camera camera,
    required FoldersAndAttachments folders,
    required RangeSelections rangeSelections,
    required Transitions transitions,
    required TrackSeDisplay trackSe,
  }) : _roles = (
         project: project,
         selection: selection,
         changes: changes,
         controllers: controllers,
         internals: internals,
         blockMove: blockMove,
         renderCaches: renderCaches,
         camera: camera,
         transitions: transitions,
         trackSe: trackSe,
       ),
       _project = project,
       _selection = selection,
       _changes = changes,
       _controllers = controllers,
       _internals = internals,
       _rowSpans = rowSpans,
       _folders = folders,
       _rangeSelections = rangeSelections;

  /// What a drag in flight is handed (see [FrameRangeMoveRoles]).
  final FrameRangeMoveRoles _roles;

  /// The three the BEGIN asks and a flying drag never does — whether the
  /// row stands down, whether its blocks are borrowed, which rows of the
  /// span can be retimed at all. They stay here for the same reason the
  /// lane move's subject resolver did: they are this class's map of the
  /// project, not a gesture's.
  final RowSpans _rowSpans;
  final FoldersAndAttachments _folders;
  final RangeSelections _rangeSelections;

  /// What [setRunEdgeBehavior] reads.
  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final ActiveCutControllers _controllers;
  final SessionInternals _internals;

  /// The frame-range move in flight, or null. ⛔The only thing this class
  /// keeps about one: the drag-start capture, the last valid plans and the
  /// axis live on the object and die with the gesture.
  FrameRangeMoveDrag? _drag;

  /// Takes the drag a factory answered, or reports the refusal.
  ///
  /// ⚠️Assigned only on SUCCESS: a refused begin must not touch a drag
  /// already in flight, and — the reason the axis used to be a field here
  /// — must not leave the NEXT press reading the wrong rail.
  bool _take(FrameRangeMoveDrag? drag) {
    if (drag == null) {
      return false;
    }
    _drag = drag;
    return true;
  }

  /// A range-move drag on the TRACK axis — the storyboard's S rows.
  /// [grabLayerId] = the row the pointer went down on (R27 #8).
  bool beginTrackRangeMoveDrag([LayerId? grabLayerId]) => _take(
    FrameRangeMoveDrag.beginOnTrackAxis(
      roles: _roles,
      grabLayerId: grabLayerId,
    ),
  );

  /// Starts moving the CURRENT cut-local frame-range selection; false when
  /// there is none (or its row stands down, or the span holds nothing but
  /// empty cells).
  bool beginFrameRangeMoveDrag([LayerId? grabLayerId]) => _take(
    FrameRangeMoveDrag.begin(
      roles: _roles,
      rowSpans: _rowSpans,
      folders: _folders,
      rangeSelections: _rangeSelections,
      grabLayerId: grabLayerId,
    ),
  );

  /// A range-move drag step: live preview (repository untouched), the
  /// selection outline riding the previewed landing.
  void updateFrameRangeMoveDrag({
    required int frameDelta,
    LayerId? targetLayerId,
  }) => _drag?.update(frameDelta: frameDelta, targetLayerId: targetLayerId);

  /// Commits the range move as ONE undo step (layer updates + the brush
  /// re-key on cross-layer carries), mirroring the block-move commit.
  void endFrameRangeMoveDrag() {
    final drag = _drag;
    _drag = null;
    drag?.commit();
  }

  /// Drops an in-flight range-move preview, restoring the selection.
  void cancelFrameRangeMoveDrag() {
    final drag = _drag;
    _drag = null;
    drag?.cancel();
  }

  /// Sets or clears the [side] edge property of the glued run containing
  /// [blockStartIndex] (UI-R9 #10): `mode` null = None. With
  /// [scopeToSelection] (the flyout's explicit "Repeat selection" entry,
  /// UI-R19 #2), Repeat captures the current frame-range selection as its
  /// pattern when the selection covers the run's edge block (end side:
  /// selection start → run end; start side: run start → selection end);
  /// otherwise — and always when [scopeToSelection] is false — the whole
  /// run cycles. Ghosts always fill to the cut boundary. One undo step,
  /// committed immediately.
  void setRunEdgeBehavior({
    required LayerId layerId,
    required int blockStartIndex,
    required TimelineRunEdgeSide side,
    TimelineRunEdgeMode? mode,
    bool scopeToSelection = true,
  }) {
    if (!_internals.blockMoveEligible(layerId)) {
      return;
    }
    final before = _project.layerById(layerId);
    if (before == null) {
      return;
    }
    // Design E: the storyboard row refuses repeat/hold regions outright —
    // a derived instance would look exactly like a panel while owning no
    // memo of its own. Copy the frames instead.
    if (!before.kind.acceptsRepeatRegions) {
      return;
    }
    final run = gluedRunAt(before, blockStartIndex);
    if (run == null) {
      return;
    }

    final patternAnchor = _repeatPatternAnchor(
      mode,
      scopeToSelection,
      layerId,
      side,
      run,
      before,
    );

    // The behavior anchors to its EDGE block (UI-R10 #4): the end side to
    // the run's LAST block, the start side to the FIRST — splitting the
    // run keeps the property with the fragment that owns that edge.
    final edgeAnchor = _edgeAnchorOf(run, side, before);
    final behaviors = [
      for (final behavior in before.runBehaviors)
        if (!_behaviorOwnsEdge(behavior, side, run, before)) behavior,
      if (mode != null)
        TimelineRunBehavior(
          anchorFrameId: edgeAnchor,
          side: side,
          mode: mode,
          patternAnchorFrameId: patternAnchor,
        ),
    ];
    final after = rederiveRunBehaviors(
      before.copyWith(runBehaviors: behaviors),
      cutFrameCount: _project.activeCutFrameCount,
    );
    if (after == before) {
      return;
    }
    _controllers.timelineController.commitLayerTimelineDrag(
      before: before,
      after: after,
    );
    _changes.warmActiveCut();
    _changes.notifyChanged();
  }

  /// Whether [behavior] already sits on this [side] of [run] — the one a
  /// new setting replaces.
  bool _behaviorOwnsEdge(
    TimelineRunBehavior behavior,
    TimelineRunEdgeSide side,
    ({FrameId anchorFrameId, int endIndexExclusive, int startIndex}) run,
    Layer before,
  ) {
    if (behavior.side != side) {
      return false;
    }
    for (final entry in before.timeline.entries) {
      if (entry.value.ghost || entry.value.frameId != behavior.anchorFrameId) {
        continue;
      }
      return entry.key >= run.startIndex && entry.key < run.endIndexExclusive;
    }
    return false;
  }

  FrameId _edgeAnchorOf(
    ({FrameId anchorFrameId, int endIndexExclusive, int startIndex}) run,
    TimelineRunEdgeSide side,
    Layer before,
  ) {
    if (side != TimelineRunEdgeSide.end) {
      return run.anchorFrameId;
    }
    return _lastFrameIdIn(before, run.startIndex, run.endIndexExclusive) ??
        run.anchorFrameId;
  }

  /// The LAST real (non-ghost) block's frame in `[startIndex,
  /// endExclusive)` on [before], or null when the window holds none.
  ///
  /// The window's end is the whole difference between the three walks
  /// that ask this — a run's end or a selection's end.
  FrameId? _lastFrameIdIn(Layer before, int startIndex, int endExclusive) {
    FrameId? found;
    for (final entry in before.timeline.entries) {
      if (entry.value.ghost ||
          entry.key < startIndex ||
          entry.key >= endExclusive) {
        continue;
      }
      found = entry.value.frameId ?? found;
    }
    return found;
  }

  /// The FIRST real (non-ghost) block's frame in `[startIndex,
  /// endExclusive)` on [before], or null when the window holds none.
  FrameId? _firstFrameIdIn(Layer before, int startIndex, int endExclusive) {
    for (final entry in before.timeline.entries) {
      if (entry.value.ghost ||
          entry.key < startIndex ||
          entry.key >= endExclusive) {
        continue;
      }
      if (entry.value.frameId case final frameId?) {
        return frameId;
      }
    }
    return null;
  }

  /// The pattern anchor a Repeat edge takes from the frame-range selection
  /// (UI-R19 #2, "Repeat selection"): null unless the mode is Repeat, the
  /// flyout asked for the selection, and the selection sits on this row and
  /// covers the run's edge block.
  FrameId? _repeatPatternAnchor(
    TimelineRunEdgeMode? mode,
    bool scopeToSelection,
    LayerId layerId,
    TimelineRunEdgeSide side,
    ({FrameId anchorFrameId, int endIndexExclusive, int startIndex}) run,
    Layer before,
  ) {
    if (mode != TimelineRunEdgeMode.repeat || !scopeToSelection) {
      return null;
    }
    final selection = _selection.frameRangeSelection.value;
    if (selection == null || selection.layerId != layerId) {
      return null;
    }
    return switch (side) {
      TimelineRunEdgeSide.end => _patternFromSelectionStart(
        selection,
        run,
        before,
      ),
      TimelineRunEdgeSide.start => _patternToSelectionEnd(
        selection,
        run,
        before,
      ),
    };
  }

  /// End side: the pattern runs from the first block at/after the selection
  /// start to the run's end — when the selection covers the run's last
  /// block and starts inside the run.
  FrameId? _patternFromSelectionStart(
    TimelineFrameRangeSelection selection,
    ({FrameId anchorFrameId, int endIndexExclusive, int startIndex}) run,
    Layer before,
  ) {
    if (!selection.contains(run.endIndexExclusive - 1) ||
        selection.startIndex <= run.startIndex) {
      return null;
    }
    return _firstFrameIdIn(before, selection.startIndex, run.endIndexExclusive);
  }

  /// Start side: the pattern runs from the run's start to the last block
  /// ending by the selection's end — when the selection covers the run's
  /// first block and ends inside the run.
  FrameId? _patternToSelectionEnd(
    TimelineFrameRangeSelection selection,
    ({FrameId anchorFrameId, int endIndexExclusive, int startIndex}) run,
    Layer before,
  ) {
    if (!selection.contains(run.startIndex) ||
        selection.endIndexExclusive >= run.endIndexExclusive) {
      return null;
    }
    return _lastFrameIdIn(before, run.startIndex, selection.endIndexExclusive);
  }
}
