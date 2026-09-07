import 'dart:math' as math;
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/range_snap.dart';
import '../../models/timeline_selection_kind.dart';
import '../../models/timeline_frame_range.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track_frame_range.dart';
import '../../models/track_id.dart';
import '../../models/track_transform_lane_carrier.dart';
import '../timeline/timeline_row_span_resolver.dart'
    show resolveSelectionSpanRows;
import '../timeline/timeline_section_policy.dart';
import '../timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane, transformLaneDisplayOrder, transformLaneSpan;
import 'playback_rig.dart';
import 'session_roles.dart';
import 'track_se_display.dart';
import 'storyboard_rows.dart';

/// The RANGE SELECTIONS — the frame, track and lane range sweeps, what a
/// selection spans, which block starts it names, standing inside it,
/// claiming, revealing and clearing it, and the interaction holds — as
/// their own object. The selections themselves stay on the session: the
/// UI reads them.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: one field of its own and thirty
/// session members touched; the rest reads it in six places (the cell and
/// comma verbs asking what is selected). It names the roles it needs
/// in its constructor.
class RangeSelections {
  RangeSelections({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required SessionInternals internals,
    required PlaybackRig playbackRig,
    required StoryboardRows storyboardRows,
    required TrackSeDisplay trackSe,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _internals = internals,
       _playbackRig = playbackRig,
       _storyboardRows = storyboardRows,
       _trackSe = trackSe;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final SessionInternals _internals;
  final PlaybackRig _playbackRig;
  final StoryboardRows _storyboardRows;
  final TrackSeDisplay _trackSe;

  /// 🚨T10 — whether standing on ([row], [frameIndex]) lands INSIDE whatever
  /// is currently selected.
  ///
  /// The one question [_internals.standOnRow] asks before it clears. 유저 확정
  /// 2026-08-14: 「탭다운 하면 **먼저 기존 선택된거 삭제**하게 하면, 바꾸면
  /// 선택삭제고 거기서 이동하면 선택 새로 추가니까 문제없을거같은데」 — a
  /// press clears when it moves you somewhere else, and holds when it is the
  /// beginning of a MOVE of what is already selected.
  ///
  /// ★Asked HERE rather than threaded in from each surface. Handing every
  /// surface the same predicate and trusting each to use it is the shape T5
  /// and T13 spent a round deleting from the selection model — the next
  /// surface forgets, and the bug is invisible until someone drags on it.
  ///
  /// ★Every KIND is asked, and 「선택한 상태라는건 한 종류만 존재하도록」
  /// means at most one can answer yes anyway. A kind added later joins by
  /// being named here, exactly like [claimSelection]'s switch.
  ///
  /// ⚠️A null [frameIndex] means "no cell is in question", so only the ROW
  /// selection can answer. [_internals.standOnRow] does not pass null — it substitutes
  /// the playhead, because standing on a row without naming a frame IS
  /// standing there at the playhead.
  bool standingInsideSelection(
    TimelineRowAddress row, [
    int? frameIndex,
    bool frameIsGlobal = false,
  ]) {
    if (_internals.rowIsSelected(row)) {
      return true;
    }
    final cells = _selection.frameRangeSelection.value;
    if (cells != null &&
        frameIndex != null &&
        !frameIsGlobal &&
        cells.coversRow(row) &&
        frameIndex >= cells.startIndex &&
        frameIndex < cells.endIndexExclusive) {
      return true;
    }
    // ⚠️A lane selection has no `coversRow` — it names its rows by LANE
    // (`coversLane`), which is why this arm reads differently from the one
    // above rather than sharing it.
    //
    // C6 (2026-08-17): asked on the AXIS the span lives on. A track-SE
    // row's lane span is stored GLOBAL ([updateLaneRangeSelectionDrag]'s
    // own translation), while the cut panel presses in window frames — so
    // a window frame converts exactly as the drag's did, or a press inside
    // the very selection it made reads as outside and the standing clear
    // (now on the DOWN) would wipe the move it was starting.
    final lanes = _selection.laneRangeSelection.value;
    if (lanes != null && frameIndex != null && row is LaneRowAddress) {
      final laneAxisFrame =
          !frameIsGlobal && _project.isTrackSeLayerId(row.layerId)
          ? frameIndex + _project.activeCutGlobalStartFrame
          : frameIndex;
      if (lanes.coversLane(row.layerId, row.laneId) &&
          laneAxisFrame >= lanes.startIndex &&
          laneAxisFrame < lanes.endIndexExclusive) {
        return true;
      }
    }
    // The TRACK-axis selection (the storyboard's rows) answers for the
    // global-frame callers the same way the cut-local ones answer above.
    final trackSpan = _selection.trackFrameRangeSelection.value;
    if (trackSpan != null &&
        frameIndex != null &&
        frameIsGlobal &&
        trackSpan.coversRow(row) &&
        frameIndex >= trackSpan.startFrame &&
        frameIndex < trackSpan.endFrameExclusive) {
      return true;
    }
    return false;
  }

  /// 🚨A CLICK CLEARS (유저 확정 2026-08-12): 「어딘가 클릭하면 사라지도록.
  /// 프레임셀처럼 다른곳 클릭하거나. 다른레이어 클릭하거나. **근데 선택된 내
  /// 물건 클릭해도 사라지도록** 하고싶어. 선택레이어로 ABC선택하고, C 클릭하면
  /// 사라지도록. **프레임셀쪽도 마찬가지**」.
  ///
  /// ★TAP clears, DRAG does not — the whole distinction, and the reason
  /// this hangs off the surfaces' SELECT callbacks rather than off
  /// pointer-down: a press the pan recognizer claims never reaches them, so
  /// a drag starting inside a selection still MOVES it (⑨'s second phase)
  /// while a tap on that same row lets it go.
  ///
  /// Clicking INSIDE the selection clears it too. That is the user's own
  /// call, and it is written out here because it is the surprising half —
  /// the ordinary desktop idiom keeps a selection you click into.
  /// Whether [clearAllSelections] has anything to clear — the deselect
  /// button's gate, and its verb's own question (T25: one answer behind
  /// both).
  ///
  /// 🚨deselect-button (유저): 「선택해제 버튼 — 태블릿엔 키보드가 없다」. Esc
  /// is not reachable on a tablet, and every other way out of a selection is
  /// a TAP somewhere, which also moves the playhead or the standing row. This
  /// is the one that only lets go.
  ///
  /// ⚠️It asks all four TIMELINE kinds because the ONE-SELECTION LAW means at
  /// most one of them is live — so "is anything selected" is one question
  /// wherever it is asked from.
  ///
  /// 🚨AND THE FIFTH KIND: the marquee on the artwork. It is deliberately NOT
  /// in [claimSelection]'s switch — space and time are different axes and the
  /// pixel verbs need both at once — but 「지금 뭔가 선택됐나」 has to count it,
  /// or a button saying 선택 해제 leaves a selection sitting on screen.
  bool get hasAnySelection =>
      _selection.frameRangeSelection.value != null ||
      _selection.laneRangeSelection.value != null ||
      _selection.trackFrameRangeSelection.value != null ||
      _selection.rowSelection.value.isNotEmpty ||
      (_internals.canvasHasSelection?.call() ?? false);

  void clearAllSelections() {
    clearFrameRangeSelection();
    clearLaneRangeSelection();
    _selection.clearStoryboardCutSelection();
    _selection.clearRowSelection();
    // ⛔ALL of them, the marquee included. 유저 2026-08-27 found two buttons
    // both called 선택 해제, both wearing `Icons.deselect`, each letting go of
    // a different half — the rail's cleared the marquee, the timeline's
    // cleared the timeline, and nothing on screen said which was which.
    // 「Let go」 means let go.
    _internals.clearCanvasSelection?.call();
  }

  /// 🚨THE ONE-SELECTION LAW (유저 확정 2026-08-12): 「선택범위는 하나만
  /// 작동하도록. 프레임셀 선택범위 작동시키고 레이어쪽 선택범위 작동하면
  /// 기존 프레임셀쪽 사라지게. 반대도 마찬가지 (…) 즉 **선택한 상태라는건
  /// 한 종류만 존재하도록**」.
  ///
  /// Whichever selection is STARTING, the others go.
  ///
  /// The rule already existed in pieces — the track axis cleared the
  /// cut-local one, cells and lanes cleared each other — each stated at its
  /// own call site with its own words. Three kinds is where pairwise still
  /// reads; ⑨ made a fourth, and n² sentences is where it stops. Written
  /// once, a fifth kind joins by being named in this switch.
  void claimSelection(TimelineSelectionKind kind) {
    if (kind != TimelineSelectionKind.cells) {
      clearFrameRangeSelection();
    }
    if (kind != TimelineSelectionKind.lanes) {
      clearLaneRangeSelection();
    }
    if (kind != TimelineSelectionKind.cuts) {
      _selection.clearStoryboardCutSelection();
    }
    if (kind != TimelineSelectionKind.rows) {
      _selection.clearRowSelection();
    }
  }

  /// Asks the rails to scroll whatever is selected back into view.
  void revealSelection() => _internals.revealSelectionTick.value += 1;

  /// A span's real (non-ghost) drawing-block start keys on [layer], in
  /// order. Axis-free on purpose: the caller states the span in whichever
  /// axis its layer is keyed by, which is what lets the cut-local and the
  /// track-global selections share this.
  List<int> selectionBlockStarts(
    Layer layer,
    int startIndex,
    int endIndexExclusive,
  ) => [
    for (final entry in layer.timeline.entries)
      if (entry.key >= startIndex &&
          entry.key < endIndexExclusive &&
          entry.value.isDrawing &&
          !entry.value.ghost)
        entry.key,
  ];

  /// Which rows of a live span a retime may touch, in BOTH the forms a
  /// retime needs — the display form it reads timing off and the COMMIT
  /// form it writes back to (UI-R18 #1: SE rows join through the
  /// commit-key seam). A row missing either form is not retimable.
  ///
  /// The comma edge and the frame-axis slide ask this one question; the
  /// delete/comma collector does NOT (it resolves the display form only
  /// and keeps a row whose commit form is null) — see
  /// [cutLocalSelectionBlockStartsByLayer].
  List<({LayerId id, Layer display, Layer commit})> retimableSpanRows(
    TimelineFrameRangeSelection selection,
  ) {
    final rows = <({LayerId id, Layer display, Layer commit})>[];
    for (final id in selection.spanLayerIds) {
      // Rows whose timing is not their own stand down — see
      // [EditorSessionManager.standsDownFromRetime].
      if (_changes.standsDownFromRetime(id)) {
        continue;
      }
      final display = _project.rangeLayerById(id);
      final commit = _project.commitLayerById(id);
      if (display == null || commit == null) {
        continue;
      }
      rows.add((id: id, display: display, commit: commit));
    }
    return rows;
  }

  /// A cut-select drag step stated on the track's GLOBAL FRAME axis — the
  /// timeline's range grammar, cuts as the blocks. Dragging from anywhere
  /// inside one cut to anywhere inside another selects both whole, and a
  /// span that only crosses a gap selects nothing there.
  ///
  /// This is the ONLY cut-select entry point: the storyboard's cut row now
  /// mounts the shared range gesture, which speaks frames, so the ordinal
  /// form it used to need is gone.
  ///
  /// [trackId] names the row the drag is on; omitting it means the selected
  /// track (the panel always knows, the session's own callers rarely do).
  void updateStoryboardCutSelectionByFrame({
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    TrackId? trackId,
    TimelineRowAddress? headRow,
  }) {
    final row = trackId ?? _selection.selectedTrackId;
    updateTrackRangeSelection(
      trackId: row,
      anchorRow: TrackRowAddress(row),
      anchorGlobalFrame: anchorGlobalFrame,
      headGlobalFrame: headGlobalFrame,
      headRow: headRow,
    );
  }

  /// THE track-axis select-drag step, whichever storyboard row started it.
  ///
  /// The span snaps against EVERY row it covers at once (the union snap):
  /// reaching a cut row expands the range to whole cuts, reaching an SE row
  /// expands it to whole sounds, and a drag across both gets the union —
  /// which is what makes "the selection covers these rows" a single fact
  /// rather than one per row.
  void updateTrackRangeSelection({
    required TrackId trackId,
    required TimelineRowAddress anchorRow,
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    required TimelineRowAddress? headRow,
    List<TimelineRowAddress> spanRows = const [],
  }) {
    final railRows = _storyboardRows.storyboardRailRows(trackId);
    final anchorIndex = railRows.indexOf(anchorRow);
    final List<TimelineRowAddress> spanned;
    if (spanRows.isNotEmpty) {
      // C②: the escalated lane-anchor form — the span IS the display
      // slice the panel handed over (lane rows included; the session's
      // model-only rail list cannot name them, the same reason the
      // timeline's spanRows channel exists).
      spanned = spanRows;
    } else if (anchorIndex < 0 || railRows.length < 2) {
      spanned = [anchorRow];
    } else {
      // R9 #25: the head arrives as an ADDRESS, resolved by the panel
      // against the heights it paints. It used to arrive as a row DELTA
      // computed from one row's height, which under-counted every row that
      // was a different size — the whole of the "V행에서 위로 끌면 S1에서
      // 막힘" report. A row this rail does not hold (or none at all) simply
      // leaves the anchor alone: what is not on the list is unreachable,
      // which is the same guard the clamp used to be.
      final headIndex = headRow == null
          ? anchorIndex
          : railRows.indexOf(headRow);
      final resolvedHead = headIndex < 0 ? anchorIndex : headIndex;
      final first = math.min(anchorIndex, resolvedHead);
      final last = math.max(anchorIndex, resolvedHead);
      spanned = railRows.sublist(first, last + 1);
    }

    final axis = _timeline.axisForTrack(trackId);
    final lanes = <RangeBlock? Function(int)>[
      for (final row in spanned) ?_internals.trackRowSnapLane(row, axis),
    ];
    // 🚨No `lanes.isEmpty ? null` short-circuit. A span made only of LANE
    // rows has no block lane to snap against — the lane domain's own rule
    // is raw cells — and treating "nothing to snap to" as "nothing to
    // select" made a selection that stayed inside one fx group vanish as
    // it was drawn. [snapSpanToBlocks] with no lanes IS the raw span,
    // which is exactly the right answer here.
    final span = snapSpanToBlocks(
      lanes: lanes,
      anchorIndex: anchorGlobalFrame,
      headIndex: headGlobalFrame,
    );
    // A span that only crosses a GAP still selects: these are frame-block
    // rows like any other, and an empty cell is selectable on every one of
    // them. It simply covers no blocks, so the verbs that act on them find
    // nothing to act on — what an empty selection means everywhere else.
    if (span == null) {
      _selection.trackFrameRangeSelection.value = null;
      return;
    }
    // THE ONE-SELECTION LAW — see [claimSelection].
    claimSelection(TimelineSelectionKind.cuts);
    _selection.trackFrameRangeSelection.value = TrackFrameRangeSelection(
      trackId: trackId,
      anchorRow: anchorRow,
      // Single-row drags leave this empty, which is what `spanRows` reads
      // as "the anchor alone" — no caller has to special-case the common
      // case.
      rows: spanned.length > 1 ? spanned : const [],
      startFrame: span.startIndex,
      endFrameExclusive: span.endIndexExclusive,
    );
  }

  /// A select-drag step on a TRACK-OWNED rail row of the storyboard — an SE
  /// lane or the transition row — stated on the track's GLOBAL frame axis.
  ///
  /// The SAME selection the cut row paints — one axis, several rows. It
  /// cannot be the timeline's cut-local selection: the display clone the
  /// timeline shows is WINDOWED to the active cut, so a sound two cuts away
  /// has no cut-local address to be selected by. The snap runs on the
  /// GLOBAL layer, which is also the layer any edit would commit against.
  ///
  /// 🚨The owner lookup asks [_trackSe.isTrackOwnedRailLayerId]'s question, not "is it
  /// an SE row" — that substitution is what left the transition row the one row
  /// of this rail a range drag could not touch (user 2026-08-11:
  /// 「선택범위… 트랜지션레이어만 작동안하니까 공통 규칙 그대로」). Selecting is
  /// reading; the read-only rule bites on the verbs that CHANGE a row, and the
  /// transition row simply mounts no move half.
  void updateTrackRowRangeSelectionByFrame({
    required LayerId layerId,
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    TimelineRowAddress? headRow,
    TimelineRowAddress? anchorRow,
    List<TimelineRowAddress> spanRows = const [],
  }) {
    // The anchor row names its own track: gating on the ACTIVE track's row
    // list (and stating the selection on [selectedTrackId]) killed every
    // drag that anchored on an unselected track's row — the rail lookup
    // missed, so a cross-row reach collapsed to the anchor alone.
    final owner = _trackSe.trackOwnedRailOwner(layerId);
    if (owner == null) {
      return;
    }
    // The SAME path the cut row takes — one select-drag step for the rail,
    // not one per row kind. [anchorRow]/[spanRows] are the escalated
    // lane-anchor form (C②): the PANEL hands the sliced span of the rows
    // it drew, exactly as the timeline's grids hand theirs.
    updateTrackRangeSelection(
      trackId: owner.id,
      anchorRow: anchorRow ?? LayerRowAddress(layerId),
      anchorGlobalFrame: anchorGlobalFrame,
      headGlobalFrame: headGlobalFrame,
      headRow: headRow,
      spanRows: spanRows,
    );
  }

  /// A lane-band select-drag step (raw cells — lane keys are points, no
  /// block snap). Starting a lane selection clears the cell selection
  /// (mutual exclusion, the F4 rule).
  ///
  /// R26 #3 — the cells' grammar on lane rows: [headLaneId] (the lane row
  /// under the pointer) spans the selection across the layer's lane group
  /// in display order; the group HEADER as anchor selects every member
  /// lane. Starting on ANOTHER layer's lanes activates that layer
  /// (선택하면 액티브 레이어가 바뀜); lanes of the active layer leave it
  /// unchanged — the fx-row selection rides ALONGSIDE the active layer.
  /// [framesAreGlobal] says which axis the surface counted in — the same
  /// question [_internals.shiftAnchorFor] asks for the frame-shift verbs. The
  /// storyboard's strips ARE the track's global axis; a cut panel's are
  /// its window, and a track-SE row's span is translated onto the global
  /// axis on the way in, because that is where the selection lives.
  void updateLaneRangeSelectionDrag({
    required LayerId layerId,
    required String laneId,
    required int anchorIndex,
    required int headIndex,
    String? headLaneId,
    required List<String> spanLaneIds,
    bool framesAreGlobal = false,
  }) {
    final carrierTrackId = trackIdOfTransformLaneCarrier(layerId);
    if (carrierTrackId != null) {
      // The V track's lanes (R4b): the carrier id routes the selection
      // onto the TRACK's lanes — global frame indexes, no layer to
      // activate. Selecting the row keeps the rail's answer honest,
      // without promoting a cut (the drag is about keys, not cuts).
      if (_project.trackById(carrierTrackId) == null) {
        return;
      }
      _internals.selectTrackRow(carrierTrackId);
    } else {
      if (_project.layerById(layerId) == null) {
        // A REAL track row that just is not the ACTIVE track's (its lane
        // law cannot hold the span here — the pre-existing gate): an
        // escalated track-axis selection this drag painted must not
        // FREEZE on the retreat, so the honest step still drops it (C②
        // review; the same press-drops-selection rule as R5 #12).
        if (_trackSe.trackSeAnywhere(layerId) != null) {
          _selection.clearStoryboardCutSelection();
        }
        return;
      }
      if (_selection.activeLayerId != layerId) {
        // selectLayer first: it drops the OLD selection (a different
        // layer's), then the fresh span lands for the new active layer.
        _internals.selectLayer(layerId);
      }
    }
    // THE ONE-SELECTION LAW — see [claimSelection].
    claimSelection(TimelineSelectionKind.lanes);
    final toGlobal = !framesAreGlobal && _project.isTrackSeLayerId(layerId)
        ? _project.activeCutGlobalStartFrame
        : 0;
    final start = math.max(0, math.min(anchorIndex, headIndex)) + toGlobal;
    final endExclusive = math.max(anchorIndex, headIndex) + 1 + toGlobal;
    if (endExclusive <= start) {
      return;
    }
    // 🚨★★★THE SPAN COMES FROM THE RAIL, NOT FROM A FAMILY.
    //
    // 절대명령 2 (유저, 반복): 「**선택범위는 레이어 불문 자유롭게**. 행의
    // 종류로 막지 않는다」.
    //
    // ⛔This used to try three per-family walks in a `??` chain —
    // `effectLaneSpan`, then `seNameTagLaneSpan`, then `transformLaneSpan`.
    // Each knew only its own order list, so a drag whose ends sat in
    // DIFFERENT groups matched none and collapsed to the anchor alone: the
    // selection stopped at a boundary the user never drew. They were also
    // the same code three times (get an order, index both ends, slice).
    //
    // ⇒ The rail slices the span out of the rows it ACTUALLY DREW
    // ([laneSpanOverDrawnRows]) and hands it here. A collapsed group draws
    // no members so they cannot be swept, and a group opened between two
    // others joins without this method learning its name.
    final span = spanLaneIds;
    _selection.laneRangeSelection.value = TimelineLaneSelection(
      layerId: layerId,
      laneId: laneId,
      startIndex: start,
      endIndexExclusive: endExclusive,
      laneIds: span.length <= 1 ? const [] : span,
    );
  }

  void clearLaneRangeSelection() {
    if (_selection.laneRangeSelection.value != null) {
      _selection.laneRangeSelection.value = null;
    }
  }

  /// Whether [layerId] can take part in a RANGE selection (UI-R20 #2:
  /// cells are cells — EVERY layer row selects, camera and instruction
  /// included; what a selection can DO stays kind-gated at each op's
  /// seam). Attach rows stand down until the ghost-snap rework lets
  /// their all-ghost mirrors join (P3b).
  bool rangeSelectionEligible(LayerId layerId) {
    // EVERY row selects now — synced attach mirrors included (P3b: the
    // ghost snap covers them; their mirror snaps to the base's blocks).
    if (_project.isTrackSeLayerId(layerId)) {
      return _project.trackSeGlobalLayerById(layerId) != null;
    }
    return _project.layerById(layerId) != null;
  }

  /// 🚨★★★ [spanRows] — what the drag SWEPT, straight off the rail's own row
  /// list ([resolveSelectionSpanRows]).
  ///
  /// The span used to be re-derived here, out of `cut.layers + seLayers`, and
  /// three kinds of on-screen row are not in that walk: the track-owned
  /// transition clone, lane rows, group headers. So an anchor on one of them
  /// missed and the span collapsed to a single row, while crossing one
  /// stepped over it. ⛔**Do not reintroduce a model walk here.** The surface
  /// that DRAWS the rows is the only thing that knows what is on screen; if
  /// this list is empty the caller had no rows in reach (the storyboard cut
  /// axis), and the anchor row alone is the honest answer.
  void updateFrameRangeSelectionDrag({
    required LayerId layerId,
    required int anchorIndex,
    required int headIndex,
    LayerId? headLayerId,
    String? headLaneId,
    List<TimelineRowAddress> spanRows = const [],
  }) {
    if (!rangeSelectionEligible(layerId)) {
      return;
    }
    final layer = _project.rangeLayerById(layerId);
    if (layer == null) {
      return;
    }
    // A lane TAIL only exists on the anchor layer's own group: the lane
    // domain is one layer's keys (R26 #3), and a span reaching a further
    // layer's lanes is that layer's cells being selected, not its keys.
    final laneTail = headLaneId != null && (headLayerId ?? layerId) == layerId
        ? headLaneId
        : null;
    // THE ONE-SELECTION LAW — see [claimSelection]. The lane clear is not
    // final for THIS drag: a mixed span below re-sets it, which is the one
    // case where a cell drag ends up owning lane state too.
    claimSelection(TimelineSelectionKind.cells);
    final base = snapFrameRangeToBlocks(
      layer: layer,
      anchorIndex: anchorIndex,
      headIndex: headIndex,
      aggregateRuns: _internals.aggregateRunsForRow(layer),
    );
    if (base == null) {
      _selection.frameRangeSelection.value = null;
      return;
    }
    // The layer half of what was swept, in display order — derived from the
    // rows rather than rebuilt, so the two can never disagree.
    // Deduped in display order: a layer row and its own lane rows are
    // several rows of ONE layer. Asking the ADDRESS which layer it belongs
    // to (rather than testing its type) is what keeps a span that runs
    // cell → lane → lane → cell from losing the rows in the middle.
    final spanIds = spanRows.isEmpty
        ? _selectionSpanLayerIds(layerId, headLayerId ?? layerId)
        : <LayerId>[
            ...{for (final row in spanRows) ?row.owningLayerId},
          ];
    if (spanIds.length <= 1) {
      _selection.frameRangeSelection.value = spanRows.isEmpty
          ? base
          : TimelineFrameRangeSelection(
              layerId: base.layerId,
              startIndex: base.startIndex,
              endIndexExclusive: base.endIndexExclusive,
              rows: spanRows,
            );
      _applySelectionLaneTail(
        layerId: layerId,
        headLaneId: laneTail,
        startIndex: base.startIndex,
        endIndexExclusive: base.endIndexExclusive,
      );
      return;
    }
    // Union-snap: expand until no spanned layer's block is cut. Each pass
    // can only grow the range, so the loop terminates.
    var start = base.startIndex;
    var end = base.endIndexExclusive;
    var changed = true;
    while (changed) {
      changed = false;
      for (final id in spanIds) {
        final spanned = _project.rangeLayerById(id);
        if (spanned == null) {
          continue;
        }
        final snapped = snapFrameRangeToBlocks(
          layer: spanned,
          anchorIndex: start,
          headIndex: end - 1,
          aggregateRuns: _internals.aggregateRunsForRow(spanned),
        );
        if (snapped == null) {
          continue;
        }
        if (snapped.startIndex < start || snapped.endIndexExclusive > end) {
          start = math.min(start, snapped.startIndex);
          end = math.max(end, snapped.endIndexExclusive);
          changed = true;
        }
      }
    }
    _selection.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: layerId,
      startIndex: start,
      endIndexExclusive: end,
      layerIds: spanIds,
      rows: spanRows,
    );
    _applySelectionLaneTail(
      layerId: layerId,
      headLaneId: laneTail,
      startIndex: start,
      endIndexExclusive: end,
    );
  }

  /// R27 #14: publishes the LANE half of a mixed cell→lane drag — the
  /// layer's lane group from its FIRST lane down to the hovered one, over
  /// the same frame range the cells settled on, so the two halves read as
  /// one rectangle. No-op (and no clear — the caller already cleared) when
  /// the drag never reached a lane row.
  ///
  /// The active layer does NOT move here: a cell drag has never changed
  /// it, and reaching into that layer's own lanes is the same gesture.
  void _applySelectionLaneTail({
    required LayerId layerId,
    required String? headLaneId,
    required int startIndex,
    required int endIndexExclusive,
  }) {
    if (headLaneId == null) {
      return;
    }
    // The tail always anchors on the FIRST transform lane, so only a
    // transform row can be its head. A drag ending on some other lane kind
    // — an SE audio lane, or (R6) an effect parameter lane — has no
    // representable span from that anchor: [transformLaneSpan] falls back
    // to the anchor alone, and publishing that would put the selection on
    // Anchor Point, where the next Add would write keys the user never
    // asked for. Nothing published, cell selection kept.
    if (headLaneId != transformGroupHeaderLane.laneId &&
        !transformLaneDisplayOrder.contains(headLaneId)) {
      return;
    }
    final span = transformLaneSpan(transformLaneDisplayOrder.first, headLaneId);
    _selection.laneRangeSelection.value = TimelineLaneSelection(
      layerId: layerId,
      laneId: transformLaneDisplayOrder.first,
      startIndex: startIndex,
      endIndexExclusive: endIndexExclusive,
      laneIds: span.length <= 1 ? const [] : span,
    );
  }

  /// The display-ordered ELIGIBLE layers between [anchor] and [head]
  /// (inclusive) — the SECTIONED order the grids render (drawing rows,
  /// then the SE section with the track rows, then camera/instruction),
  /// so a cross-row drag spans exactly the rows it visually crosses.
  /// Ineligible rows inside the span are skipped; cross-KIND moves stay
  /// blocked at the move seam (UI-R18 #1 safety).
  List<LayerId> _selectionSpanLayerIds(LayerId anchor, LayerId head) {
    final ordered = sectionedLayerOrder([
      ..._project.activeCutOrNull?.layers ?? const <Layer>[],
      ..._selection.activeTrack.seLayers,
    ]);
    final eligible = [
      for (final layer in ordered)
        if (rangeSelectionEligible(layer.id)) layer.id,
    ];
    final anchorIndex = eligible.indexOf(anchor);
    final headIndex = eligible.indexOf(head);
    if (anchorIndex == -1 || headIndex == -1) {
      return [anchor];
    }
    final low = math.min(anchorIndex, headIndex);
    final high = math.max(anchorIndex, headIndex);
    return eligible.sublist(low, high + 1);
  }

  void clearFrameRangeSelection() {
    if (_selection.frameRangeSelection.value != null) {
      _selection.frameRangeSelection.value = null;
    }
  }

  /// THE selection resolved to real block starts per layer, in COMMIT
  /// keys; null when neither selection holds real blocks anywhere.
  ///
  /// Whichever axis the live selection is in: the cut-local one maps its
  /// display starts onto the global axis for track-SE rows (UI-R18 #1),
  /// the track-global one is already stated in commit keys. The two are
  /// mutually exclusive, so at most one answers.
  Map<LayerId, List<int>>? selectionBlockStartsByLayer() =>
      cutLocalSelectionBlockStartsByLayer() ??
      trackSelectionBlockStartsByLayer();

  Map<LayerId, List<int>>? cutLocalSelectionBlockStartsByLayer() {
    final selection = _selection.frameRangeSelection.value;
    if (selection == null) {
      return null;
    }
    final byLayer = <LayerId, List<int>>{};
    for (final id in selection.spanLayerIds) {
      // SYNCED attach rows hold no editable blocks of their own — their
      // mirror blocks are non-ghost now (the synced-block UI), so without
      // this gate a mirror-only selection would light up delete/comma
      // verbs that then no-op against the stored-empty row.
      //
      // and SINGLE-CEL (image) rows with them — see
      // [EditorSessionManager.standsDownFromRetime].
      if (_changes.standsDownFromRetime(id)) {
        continue;
      }
      final layer = _project.rangeLayerById(id);
      if (layer == null) {
        continue;
      }
      final starts = selectionBlockStarts(
        layer,
        selection.startIndex,
        selection.endIndexExclusive,
      );
      if (starts.isNotEmpty) {
        byLayer[id] = [
          for (final start in starts) _internals.commitBlockStart(id, start),
        ];
      }
    }
    return byLayer.isEmpty ? null : byLayer;
  }

  /// The storyboard's selection resolved the same way. Its LAYER rows are
  /// the track-SE rows, whose global layer is the commit layer AND the one
  /// the range is stated against — so there is nothing to translate here.
  /// (Its track row's blocks are cuts; deleting those is
  /// [CutVerbs.deleteSelectedCuts]'s job, not a layer edit.)
  Map<LayerId, List<int>>? trackSelectionBlockStartsByLayer() {
    final selection = _selection.trackFrameRangeSelection.value;
    if (selection == null) {
      return null;
    }
    final byLayer = <LayerId, List<int>>{};
    for (final row in selection.spanRows) {
      // The row's OWNING layer (C3-lane-move): a lane row is one of its
      // layer's rows, and the map keys by layer anyway, so a repeat is a
      // no-op rather than something to filter out by type.
      final rowLayerId = row.owningLayerId;
      if (rowLayerId == null) {
        continue;
      }
      final layer = _project.trackSeGlobalLayerById(rowLayerId);
      if (layer == null) {
        continue;
      }
      final starts = selectionBlockStarts(
        layer,
        selection.startFrame,
        selection.endFrameExclusive,
      );
      if (starts.isNotEmpty) {
        byLayer[rowLayerId] = starts;
      }
    }
    return byLayer.isEmpty ? null : byLayer;
  }

  /// Re-snaps the selection to the SAME cels after a retime: each layer's
  /// first retimed block kept its start; the span now ends where the last
  /// of its retimed blocks ends (max across layers).
  void reselectRetimedSelection(
    TimelineFrameRangeSelection selection,
    Map<LayerId, List<int>> startsByLayer,
  ) {
    int? end;
    for (final entry in startsByLayer.entries) {
      final layer = _project.layerById(entry.key);
      if (layer == null) {
        continue;
      }
      var remaining = entry.value.length;
      for (final timelineEntry in layer.timeline.entries) {
        if (timelineEntry.key < entry.value.first ||
            !timelineEntry.value.isDrawing ||
            timelineEntry.value.ghost) {
          continue;
        }
        final blockEnd = timelineEntry.key + timelineEntry.value.length!;
        end = end == null ? blockEnd : math.max(end, blockEnd);
        remaining -= 1;
        if (remaining == 0) {
          break;
        }
      }
    }
    _selection.frameRangeSelection.value = end == null
        ? null
        : TimelineFrameRangeSelection(
            layerId: selection.layerId,
            startIndex: selection.startIndex,
            endIndexExclusive: end,
            layerIds: selection.layerIds,
          );
  }

  int _selectionInteractionHolds = 0;

  void beginSelectionInteraction() {
    _selectionInteractionHolds += 1;
    _internals.selectionInteractionActive.value = true;
    _playbackRig.prerenderScheduler.beginInputHold();
  }

  void endSelectionInteraction() {
    if (_selectionInteractionHolds > 0) {
      _selectionInteractionHolds -= 1;
      _playbackRig.prerenderScheduler.endInputHold();
    }
    _internals.selectionInteractionActive.value =
        _selectionInteractionHolds > 0;
  }
}
