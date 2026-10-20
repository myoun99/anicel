import 'package:flutter/foundation.dart' show ValueNotifier;
import '../timeline/timeline_drag_preview.dart'
    show BlockMoveDragPreview, TimelineDragPreview;
import 'dart:collection';

import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_exposure.dart';
import '../../models/timeline_frame_range.dart';
import '../../models/timeline_repeat.dart';
import 'active_cut_controllers.dart';
import 'camera.dart';
import 'drags/frame_range_move_drag.dart';
import 'drawing_block_move_drag.dart';
import 'folders_and_attachments.dart';
import 'independent_clip_mint.dart' show celsHeldUnderTheirNames;
import 'range_selections.dart';
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
    required RetimeLaw retime,
    required ValueNotifier<TimelineDragPreview?> dragPreview,
    required RowSpans rowSpans,
    required DrawingBlockMoveDragVerbs blockMove,
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
         retime: retime,
         dragPreview: dragPreview,
         blockMove: blockMove,
         camera: camera,
         transitions: transitions,
         trackSe: trackSe,
       ),
       _project = project,
       _selection = selection,
       _changes = changes,
       _controllers = controllers,
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

  /// Whether a drag that starts on [grabLayerId] INSIDE the selection is
  /// nobody's: the row is one whose blocks cannot move — an image row, its
  /// one picture pinned over the cut ([RowSpans.isSingleCelLayerId], the
  /// reason a move leaves that row's block where it is).
  ///
  /// 🗣️F-263 (유저 2026-10-02): 「선택된곳 어디든 클릭하면 이동시작하도록.
  /// 물론 클릭한게 이미지레이어같은 이동불가한 대상이면 못하게 하는게 나을까
  /// 싶긴함」, and F-263-Q1 (2026-10-07): 「옮길 수 없는 행을 누르면 아무
  /// 일도 안 일어난다」 — neither the move the other rows would make nor a
  /// new selection, and the selection stays. ↩️It began the move: the cel
  /// rows' blocks went with a hand that was holding a picture that stayed.
  ///
  /// ⛔Asked of the ROW, not of what else is selected: an image row grabbed
  /// in a selection of image rows alone answers the same (↩️that drag swept
  /// a new selection). ⛔And not of a synced attach row: its blocks are its
  /// base's, and grabbed beside its base it carries them (F-276).
  bool grabHolds(LayerId grabLayerId) =>
      _rowSpans.isSingleCelLayerId(grabLayerId);

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
  ///
  /// 🚨F-413 (유저 2026-10-19): 「A의 1,2라는 프레임이있고, B의 3,1이라는
  /// 프레임있을때, A1,A2를 B행으로 옮기면 1이라는 이름의 그림이 두개존재함.
  /// 그래서 B행에 이동하고 손 뗄 때 링크프레임 창 작동시키도록」. A drawing
  /// carried onto a row that already holds its name would be the row's
  /// second drawing of one name — so where the drag would land one and
  /// [joinTakenNames] was not given, this writes NOTHING, keeps the drag in
  /// flight for the answer, and hands back what it would join: the linked
  /// paste's contract (I-71). Joined, each carried drawing's blocks show the
  /// row's own drawing of its name — the rename's join
  /// ([TimelineController.nameFramesForLayer]) — in the move's one step.
  CarriedNameJoins? endFrameRangeMoveDrag({bool joinTakenNames = false}) {
    final drag = _drag;
    if (drag == null) {
      return null;
    }
    final joins = _carriedNamesHeld(_roles.dragPreview.value);
    if (joins.isNotEmpty && !joinTakenNames) {
      return joins;
    }
    _drag = null;
    _project.historyManager.runAsOneStep('Move frame range', () {
      drag.commit();
      for (final row in joins) {
        _controllers.timelineController.nameFramesForLayer(
          layerId: row.onto,
          joins: row.held,
        );
      }
    });
    if (joins.isNotEmpty) {
      _changes.notifyChanged();
    }
    return null;
  }

  /// Drops an in-flight range-move preview, restoring the selection.
  void cancelFrameRangeMoveDrag() {
    final drag = _drag;
    _drag = null;
    drag?.cancel();
  }

  /// Sets or clears the [side] edge property of the glued runs a press on
  /// the run containing [blockStartIndex] acts on (UI-R9 #10): `mode` null
  /// = None. The runs are [RangeSelections.runsActedOnBy]'s — every run the
  /// live band holds when the pressed one is among them, that one alone
  /// when it is not (F-410). With [scopeToSelection] (the flyout's explicit
  /// "Repeat selection" entry, UI-R19 #2), Repeat captures the current
  /// frame-range selection as each run's pattern when the selection covers
  /// the run's edge block (end side: selection start → run end; start side:
  /// run start → selection end); otherwise — and always when
  /// [scopeToSelection] is false — the whole run cycles. Ghosts always fill
  /// to the cut boundary. One undo step, committed immediately.
  void setRunEdgeBehavior({
    required LayerId layerId,
    required int blockStartIndex,
    required TimelineRunEdgeSide side,
    TimelineRunEdgeMode? mode,
    bool scopeToSelection = true,
  }) {
    final edits = <({Layer before, Layer after})>[];
    for (final MapEntry(key: id, value: runStarts) in _rangeSelections
        .runsActedOnBy(layerId, blockStartIndex)
        .entries) {
      final before = _project.layerById(id);
      if (before == null) {
        continue;
      }
      final timeline = SplayTreeMap<int, TimelineExposure>.of(before.timeline);
      for (final start in runStarts) {
        if (gluedRunAt(before, start) case final run?) {
          // Only a Repeat the flyout asked to scope ("Repeat selection",
          // UI-R19 #2) takes its pattern from the selection.
          final bound = mode == TimelineRunEdgeMode.repeat && scopeToSelection
              ? _selectionPatternBound(id, side, run)
              : null;
          _markRunEdge(timeline, run, side, mode, bound: bound);
        }
      }
      final after = rederiveRunBehaviors(
        before.copyWith(timeline: timeline),
        drawnFrameCount: _project.activeCutDrawnFrameCount,
      );
      if (after != before) {
        edits.add((before: before, after: after));
      }
    }
    if (edits.isEmpty) {
      return;
    }
    _controllers.timelineController.commitLayerTimelineDrags(edits);
    _changes.warmActiveCut();
    _changes.notifyChanged();
  }

  /// Writes [mode] on [side] of [run] into [timeline], [bound] bounding a
  /// Repeat's pattern.
  ///
  /// The property sits on its EDGE block (UI-R10 #4): the end side on the
  /// run's LAST block, the start side on the FIRST — splitting the run
  /// keeps the property with the fragment that owns that edge. Every other
  /// block of the run gives this side's mark up, so the setting replaces
  /// whatever carried it before (F-134, see [TimelineRunEdgeMark]).
  static void _markRunEdge(
    SplayTreeMap<int, TimelineExposure> timeline,
    TimelineGluedRun run,
    TimelineRunEdgeSide side,
    TimelineRunEdgeMode? mode, {
    required int? bound,
  }) {
    final edgeBlock = side == TimelineRunEdgeSide.end
        ? run.blockStarts.last
        : run.blockStarts.first;
    for (final start in run.blockStarts) {
      timeline[start] = timeline[start]!.withEdgeMark(
        side,
        TimelineRunEdgeMark(
          mode: start == edgeBlock ? mode : null,
          bound: mode == TimelineRunEdgeMode.repeat && start == bound,
        ),
      );
    }
  }

  /// The block a Repeat edge's pattern takes from the frame-range selection
  /// as its bound (UI-R19 #2, "Repeat selection"): null unless the selection
  /// spans this row and covers the run's edge block. Whether the mode is a
  /// Repeat the flyout asked to scope is the caller's question.
  ///
  /// ↩️F-410: it asked whether the band's ANCHOR row was this one, so a
  /// band over two rows scoped the pattern on the row it was started from
  /// and cycled the other's whole run — the one rule read two ways by
  /// which row a drag began on (CLAUDE.md 절대명령 2).
  int? _selectionPatternBound(
    LayerId layerId,
    TimelineRunEdgeSide side,
    TimelineGluedRun run,
  ) {
    final selection = _selection.frameRangeSelection.value;
    if (selection == null || !selection.coversLayer(layerId)) {
      return null;
    }
    return switch (side) {
      TimelineRunEdgeSide.end => _patternFromSelectionStart(selection, run),
      TimelineRunEdgeSide.start => _patternToSelectionEnd(selection, run),
    };
  }

  /// End side: the pattern runs from the first block at/after the selection
  /// start to the run's end — when the selection covers the run's last
  /// block and starts inside the run.
  int? _patternFromSelectionStart(
    TimelineFrameRangeSelection selection,
    TimelineGluedRun run,
  ) {
    if (!selection.contains(run.endIndexExclusive - 1) ||
        selection.startIndex <= run.startIndex) {
      return null;
    }
    for (final start in run.blockStarts) {
      if (start >= selection.startIndex) {
        return start;
      }
    }
    return null;
  }

  /// Start side: the pattern runs from the run's start to the last block
  /// ending by the selection's end — when the selection covers the run's
  /// first block and ends inside the run.
  int? _patternToSelectionEnd(
    TimelineFrameRangeSelection selection,
    TimelineGluedRun run,
  ) {
    if (!selection.contains(run.startIndex) ||
        selection.endIndexExclusive >= run.endIndexExclusive) {
      return null;
    }
    int? found;
    for (final start in run.blockStarts) {
      if (start < selection.endIndexExclusive) {
        found = start;
      }
    }
    return found;
  }
}

/// What a range move would JOIN on letting go, by the row each drawing is
/// carried from and the row it lands on: each carried drawing to the one of
/// its name the landing row already holds
/// ([FrameRangeMoveDragVerbs.endFrameRangeMoveDrag]).
typedef CarriedNameJoins =
    List<({LayerId from, LayerId onto, Map<FrameId, FrameId> held})>;

/// [CarriedNameJoins] of the move [preview] shows — the drawings its
/// release carries onto another row ([BlockMoveDragPreview.rekeys]) where
/// that row's names are its drawings' identities and already hold theirs.
/// Empty when it carries none so.
///
/// Asked of the PREVIEW because the preview is what lands: the release
/// re-keys the very list it shows.
CarriedNameJoins _carriedNamesHeld(TimelineDragPreview? preview) {
  if (preview is! BlockMoveDragPreview) {
    return const [];
  }
  final carried = <(LayerId, LayerId), Set<FrameId>>{};
  for (final rekey in preview.rekeys) {
    (carried[(rekey.from, rekey.to)] ??= {}).add(rekey.frameId);
  }
  return [
    for (final MapEntry(key: (from, onto), value: ids) in carried.entries)
      if (preview.previewLayers[onto] case final landed?
          when landed.kind.celNameIsIdentity)
        if (celsHeldUnderTheirNames(
              [
                for (final frame in landed.frames)
                  if (!ids.contains(frame.id)) frame,
              ],
              [
                for (final frame in landed.frames)
                  if (ids.contains(frame.id)) frame,
              ],
            )
            case final held when held.isNotEmpty)
          (from: from, onto: onto, held: held),
  ];
}
