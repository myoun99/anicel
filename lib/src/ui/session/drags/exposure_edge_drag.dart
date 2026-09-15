import 'dart:math' as math;

import '../../../controllers/timeline_controller.dart';
import '../../../models/cut.dart';
import '../../../models/cut_end_gap.dart';
import '../../../models/cut_id.dart';
import '../../../models/layer.dart';
import '../../../models/layer_id.dart';
import '../../../models/layer_kind.dart';
import '../../../models/timeline_coverage.dart' show TimelineBlockEdge;
import '../../../models/track_se_window.dart';
import '../../storyboard_layer_policy.dart';
import '../../timeline/instruction_span_editing.dart';
import '../../timeline/timeline_drag_preview.dart';
import '../folders_and_attachments.dart';
import '../range_selections.dart';
import '../session_roles.dart';
import '../track_se_display.dart';
import 'edge_drag_roles.dart';
import 'editor_drag_session.dart';

/// The cut-length half of a storyboard row's comma drag, snapshotted at the
/// press: the cut whose length rides the row's end, the row it rides, and
/// what both — plus the following cut's gap — measured before the gesture.
typedef CutSyncCapture = ({
  CutId cutId,
  LayerId layerId,
  int beforeDuration,
  int beforeRowEnd,
  CutId? nextCutId,
  int nextBeforeGap,
});

/// A synced cut resize: the durations and the gaps one release commits with
/// the layer edits.
typedef CutResize = ({Map<CutId, int> durations, Map<CutId, int> gaps});

/// What an exposure comma BEGIN is handed beyond [EdgeDragRoles]: the
/// cut-local SE lens — the one of these the drag keeps — and the three it
/// asks ONCE and never again (does this row own its own timing, what does
/// the live selection cover, which of its rows may a retime touch).
typedef ExposureBeginRoles = ({
  TrackSeDisplay trackSe,
  FoldersAndAttachments folders,
  SelectionAccess selection,
  RangeSelections rangeSelections,
});

/// Captures the bulk-retime set when the dragged edge sits inside the live
/// selection (UI-R17 #3 → UI-R18 #1: SE rows join through the commit-key
/// seam — starts and before-layers are COMMIT forms). Null when this is a
/// single-block drag.
Map<LayerId, BulkRetimeRow>? _captureBulk({
  required EdgeDragRoles roles,
  required ExposureBeginRoles beginRoles,
  required ExposureGrip grip,
  required bool isDrawingBlock,
}) {
  final live = beginRoles.selection.frameRangeSelection.value;
  if (!isDrawingBlock ||
      live == null ||
      // A row that reshapes never — a movie kept as a reference — is left
      // out of the selection's retime, so a grip on it trims its own block
      // alone rather than retiming every other row and not it.
      roles.changes.standsDownFromRetime(grip.layerId) ||
      !live.coversLayer(grip.layerId) ||
      !live.contains(grip.blockStartIndex)) {
    return null;
  }
  final rows = <LayerId, BulkRetimeRow>{};
  for (final row in beginRoles.rangeSelections.retimableSpanRows(live)) {
    final starts = beginRoles.rangeSelections.selectionBlockStarts(
      row.display,
      live.startIndex,
      live.endIndexExclusive,
    );
    if (starts.isEmpty) {
      continue;
    }
    rows[row.id] = (
      starts: [
        for (final start in starts)
          roles.internals.commitBlockStart(row.id, start),
      ],
      before: row.commit,
    );
  }
  final multiBlock =
      rows.length > 1 || (rows[grip.layerId]?.starts.length ?? 0) > 1;
  return multiBlock ? rows : null;
}

/// Snapshots the cut-length half of an exposure comma drag (feedback #9).
///
/// A storyboard row ANYWHERE in the drag brings its cut's length along —
/// whether it is the row the pointer grabbed ([anchor]) or one the bulk
/// selection reaches. Both entry paths ask this, so the anchor's kind cannot
/// be what decides whether the pair stays synced.
CutSyncCapture? _captureCutSync({
  required EdgeDragRoles roles,
  required Map<LayerId, BulkRetimeRow>? bulk,
  required Layer? anchor,
}) {
  Layer? syncRow;
  if (bulk != null) {
    for (final candidate in bulk.values) {
      if (ridesCutLength(candidate.before.kind)) {
        syncRow = candidate.before;
        break;
      }
    }
  } else if (anchor != null && ridesCutLength(anchor.kind)) {
    syncRow = anchor;
  }
  final activeId = roles.project.activeCutId;
  final activeCut = syncRow == null || activeId == null
      ? null
      : roles.project.cutById(activeId);
  if (syncRow == null || activeCut == null) {
    return null;
  }
  return cutSyncSnapshotFor(
    project: roles.project,
    cut: activeCut,
    row: syncRow,
  );
}

/// D22: the image row is edge-less now, so it can no longer be the cut-sync
/// anchor either — the STORYBOARD row is the sole rider (otherwise a bulk
/// drag spanning an image row would silently switch which row drives the cut
/// resize).
bool ridesCutLength(LayerKind kind) =>
    kind.coversWithoutGaps && !kind.holdsSingleCel;

CutSyncCapture cutSyncSnapshotFor({
  required ProjectAccess project,
  required Cut cut,
  required Layer row,
}) {
  final next = _nextCutInTrack(project, cut.id);
  return (
    cutId: cut.id,
    layerId: row.id,
    beforeDuration: cut.duration,
    beforeRowEnd: _storedRowEndOf(row),
    nextCutId: next?.id,
    nextBeforeGap: next?.leadingGapFrames ?? 0,
  );
}

/// The cut after [cutId] on its own track, or null at the track's end.
Cut? _nextCutInTrack(ProjectAccess project, CutId cutId) {
  for (final track in project.repository.requireProject().tracks) {
    final cuts = track.cuts;
    for (var index = 0; index < cuts.length; index += 1) {
      if (cuts[index].id == cutId) {
        return index + 1 < cuts.length ? cuts[index + 1] : null;
      }
    }
  }
  return null;
}

/// Where [layer]'s stored row ends — the cut-length twin the sync rule keeps
/// the cut's duration equal to.
int _storedRowEndOf(Layer layer) {
  var end = 0;
  for (final entry in layer.timeline.entries) {
    if (!entry.value.isDrawing || entry.value.ghost) {
      continue;
    }
    final blockEnd = entry.key + (entry.value.length ?? 1);
    if (blockEnd > end) {
      end = blockEnd;
    }
  }
  return end;
}

/// What the press grabbed: the row, the block's start key and which edge.
///
/// [startIsGlobal] states which AXIS that key is in — cut-local as
/// displayed, or a TRUE global frame (the storyboard's track-global SE
/// strips, UI-R7 #5). One argument because it is one fact: the grip's own
/// answer to "what did the pointer go down on", passed unchanged from the
/// host through the verb to the factory that judges it.
typedef ExposureGrip = ({
  LayerId layerId,
  int blockStartIndex,
  TimelineBlockEdge edge,
  bool startIsGlobal,
});

/// One row's share of a BULK retime: its selected blocks' COMMIT-form start
/// keys, and the COMMIT form of the row those keys address.
///
/// ONE entry per row, not two maps keyed alike. The update used to look the
/// row up in a second map and `continue` when it was missing — a branch that
/// existed only because two maps could disagree about who is in the bulk.
typedef BulkRetimeRow = ({List<int> starts, Layer before});

/// The EXPOSURE COMMA drag — a block's edge on the timeline, the x-sheet or
/// the storyboard strip — as its own object: what the press grabbed, the
/// snapshots it previews against, its bulk and cut-sync captures, and the
/// one result the release commits.
///
/// 🚨Round G5-2 (2026-09-10) gave it the shape its siblings in `drags/`
/// already had. It was eleven `_edgeDrag*` fields on the long-lived
/// [EdgeDragVerbs], so they existed with no drag in flight and a press that
/// never moved could commit whatever an earlier one had left — which is why
/// two entry points each had to blank the whole set first, and why one of
/// them blanked it BEFORE it knew whether it could accept. A refusal is now
/// a factory answering null, and the "forget everything" list is gone
/// because dropping the object is the forgetting.
class ExposureEdgeDrag implements EditorDragSession {
  ExposureEdgeDrag._({
    required EdgeDragRoles roles,
    required TrackSeDisplay trackSe,
    required Layer before,
    required TimelineBlockEdge edge,
    required int blockStart,
    required TrackSeWindow? window,
    required Map<LayerId, BulkRetimeRow>? bulk,
    required CutSyncCapture? cutSync,
  }) : _roles = roles,
       _trackSe = trackSe,
       _before = before,
       _edge = edge,
       _blockStart = blockStart,
       _window = window,
       _bulk = bulk,
       _cutSync = cutSync;

  /// Grabs the [grip]'s edge; null when there is no such block. Instruction
  /// rows join the same pipeline — their spans live on Layer.instructions
  /// and shift without ripple. Track-SE rows convert to the global axis
  /// here; a spill-in block's start edge is rejected (its real start lives
  /// in an earlier cut). A grip that already states a TRUE global start
  /// needs no window conversion and no spill synthesis.
  static ExposureEdgeDrag? begin({
    required EdgeDragRoles roles,
    required ExposureBeginRoles beginRoles,
    required ExposureGrip grip,
  }) {
    // SYNCED attach rows own no timing — no comma grips (the BASE's grips
    // move both, W5); free attach rows drag like normal (UI-R21).
    if (beginRoles.folders.isSyncedAttachedLayerId(grip.layerId)) {
      return null;
    }
    if (roles.project.isTrackSeLayerId(grip.layerId)) {
      return _beginOnTrackSeRow(
        roles: roles,
        beginRoles: beginRoles,
        grip: grip,
      );
    }

    final layer = roles.project.layerById(grip.layerId);
    if (layer == null) {
      return null;
    }
    final isInstructionSpan =
        layer.kind == LayerKind.instruction &&
        layer.instructions.containsKey(grip.blockStartIndex);
    final isDrawingBlock =
        layer.kind.holdsDrawings &&
        // D22: the image row is edge-less (1 cell + fixed hold) — the grips
        // are gone from its chrome, and the session refuses too so the gate
        // and the dispatch stay one answer (T25).
        !layer.kind.holdsSingleCel &&
        (layer.timeline[grip.blockStartIndex]?.isDrawing ?? false);
    if (!isInstructionSpan && !isDrawingBlock) {
      return null;
    }

    // Dragging an edge inside the selection retimes the WHOLE selection
    // (UI-R17 #3/#8) — every selected block on every spanned layer follows
    // the delta live, one undo step on release.
    final bulk = _captureBulk(
      roles: roles,
      beginRoles: beginRoles,
      grip: grip,
      isDrawingBlock: isDrawingBlock,
    );
    return ExposureEdgeDrag._(
      roles: roles,
      trackSe: beginRoles.trackSe,
      before: layer,
      edge: grip.edge,
      blockStart: grip.blockStartIndex,
      window: null,
      bulk: bulk,
      cutSync: _captureCutSync(roles: roles, bulk: bulk, anchor: layer),
    );
  }

  /// The same grip on a TRACK-SE row: the block is addressed on the global
  /// axis, so the row and the start key convert before anything is captured.
  static ExposureEdgeDrag? _beginOnTrackSeRow({
    required EdgeDragRoles roles,
    required ExposureBeginRoles beginRoles,
    required ExposureGrip grip,
  }) {
    final global = roles.project.trackSeGlobalLayerById(grip.layerId);
    if (global == null) {
      return null;
    }
    final window = beginRoles.trackSe.trackSeWindow;
    if (!grip.startIsGlobal &&
        grip.edge == TimelineBlockEdge.start &&
        window.isSpillInStart(global, grip.blockStartIndex)) {
      return null;
    }
    final globalStart = grip.startIsGlobal
        ? grip.blockStartIndex
        : window.globalBlockStartFor(global, grip.blockStartIndex);
    if (!(global.timeline[globalStart]?.isDrawing ?? false)) {
      return null;
    }
    // SE rows join the selection bulk (UI-R18 #1) — display-local starts
    // only (the storyboard's global-keyed grips stand down).
    final bulk = grip.startIsGlobal
        ? null
        : _captureBulk(
            roles: roles,
            beginRoles: beginRoles,
            grip: grip,
            isDrawingBlock: true,
          );
    return ExposureEdgeDrag._(
      roles: roles,
      trackSe: beginRoles.trackSe,
      before: global,
      edge: grip.edge,
      blockStart: globalStart,
      window: window,
      bulk: bulk,
      // The bulk can reach DOWN to the cut's storyboard row, and that row
      // brings its cut's length with it wherever the drag was anchored
      // (feedback #9). The anchor's own kind must not be what decides: an
      // SE-anchored bulk used to retime the row and leave the cut behind,
      // which is the "drawing outside its cut" state that round exists to
      // make unreachable. A GLOBAL-keyed grip has no bulk and no sync — the
      // storyboard's SE strips address another cut's frames.
      cutSync: grip.startIsGlobal
          ? null
          : _captureCutSync(roles: roles, bulk: bulk, anchor: null),
    );
  }

  /// Starts a comma drag on the block keyed [blockStartIndex] (cut-local) of
  /// [cut]'s storyboard row — an INNER panel's trailing edge on the strip.
  /// The edge unification: every trailing edge on a storyboard row is the
  /// SAME comma verb, so the panel's comma resizes, the later panels ripple
  /// along glued, and the cut's length rides the row end (feedback #9) —
  /// where the retired division verb moved a boundary and pinned the length.
  /// Null when the cut has no storyboard row, or no such drawing block.
  ///
  /// Any cut's panels drag, not only the active cut's: the row comes in
  /// through the cut, which is why this is NOT [begin] — that path resolves
  /// the layer and the cut sync through the ACTIVE cut and would sync the
  /// wrong one.
  static ExposureEdgeDrag? beginStoryboardComma({
    required EdgeDragRoles roles,
    required TrackSeDisplay trackSe,
    required Cut cut,
    required int blockStartIndex,
  }) {
    final row = storyboardLayerForCut(cut);
    final entry = row?.timeline[blockStartIndex];
    // A negative key is junk data the coverage rule merely tolerates (folded
    // onto frame 0 for display) — resizing it would throw in the comma
    // shift's before-zero guard mid-drag, so refuse at begin.
    if (row == null ||
        entry == null ||
        !entry.isDrawing ||
        entry.ghost ||
        blockStartIndex < 0) {
      return null;
    }
    return ExposureEdgeDrag._(
      roles: roles,
      trackSe: trackSe,
      before: row,
      edge: TimelineBlockEdge.end,
      blockStart: blockStartIndex,
      window: null,
      bulk: null,
      cutSync: cutSyncSnapshotFor(
        project: roles.project,
        cut: cut,
        row: row,
      ),
    );
  }

  /// The strip's trailing-edge drag on [cut]'s storyboard row: the LAST
  /// cell's comma, with the cut's length riding it (feedback #9 — the cut
  /// block's last edge is the ROW's edge when the row exists). Joins the
  /// ordinary exposure comma machinery, so the strip, the timeline row and
  /// the X-sheet are one verb.
  static ExposureEdgeDrag? beginStoryboardLastComma({
    required EdgeDragRoles roles,
    required TrackSeDisplay trackSe,
    required Cut cut,
  }) {
    final row = storyboardLayerForCut(cut);
    if (row == null) {
      return null;
    }
    int? lastKey;
    for (final entry in row.timeline.entries) {
      if (entry.value.isDrawing && !entry.value.ghost) {
        lastKey = entry.key;
      }
    }
    if (lastKey == null) {
      return null;
    }
    return beginStoryboardComma(
      roles: roles,
      trackSe: trackSe,
      cut: cut,
      blockStartIndex: lastKey,
    );
  }

  final EdgeDragRoles _roles;

  /// The CURRENT cut-local lens, asked per row: a bulk drag can carry SE
  /// rows the press did not grab, and those preview through the window of
  /// whatever cut is active — [_window] is the one the press itself grabbed.
  final TrackSeDisplay _trackSe;

  /// What the press grabbed — the row (GLOBAL form for track SE), the edge
  /// and the block's start key in that row's own axis. Final: a drag
  /// without them cannot be constructed, so nothing downstream re-asks
  /// whether there is one.
  final Layer _before;
  final TimelineBlockEdge _edge;
  final int _blockStart;

  /// The cut-local lens this drag was begun through, or null off a track-SE
  /// row — previews window through it before publishing.
  final TrackSeWindow? _window;

  /// UI-R17 #3/#8: when the dragged edge belongs to a block INSIDE the frame
  /// range selection, the drag retimes EVERY selected block on EVERY spanned
  /// layer together (null = single-block drag).
  final Map<LayerId, BulkRetimeRow>? _bulk;

  /// Non-null while the dragged (or bulk-spanned) row is a cut-owned
  /// STORYBOARD row (feedback #9): its stored extent and its cut's length
  /// are one thing, so a comma that moves the row's end moves the cut's end
  /// with it — previewed together, committed as ONE undo step.
  final CutSyncCapture? _cutSync;

  /// What the release would commit: the layer edits and, when a storyboard
  /// row's end moved with them, the synced cut resize. Null while the delta
  /// lands on "no change".
  ///
  /// ⛔Fields, never the preview channel: a consumer clearing [dragPreview]
  /// mid-drag must not void the commit. And ONE field where there were
  /// three — the single-block result, the bulk result and the resize — which
  /// took the commit two branches and three null checks to reunite. A resize
  /// riding no edits was never a state; now it cannot be written down.
  ({List<({Layer before, Layer after})> edits, CutResize? resize})? _result;

  /// Applies the drag's current cumulative frame delta as a live preview on
  /// [SessionInternals.dragPreview] — the repository is NOT touched.
  @override
  void update(int cumulativeDelta) {
    // Bulk selection retime (UI-R17 #3/#8): the edge delta becomes a LENGTH
    // delta on every selected block of every spanned layer (end edge:
    // +delta, start edge: dragging right shrinks); the ripple packs/pushes
    // downstream per layer. One composite undo on release.
    final bulk = _bulk;
    if (bulk != null) {
      _updateBulk(cumulativeDelta, bulk);
      return;
    }

    final after = _draggedLayer(cumulativeDelta);
    // No notifyEditActivity here: composites self-validate against the
    // committed edit, the drag-end warm request re-renders what changed, and
    // the idle gate's REAL-time delay would leave timers pending under the
    // fake test clock.
    if (after == _before) {
      _result = null;
      _roles.internals.dragPreview.value = null;
      return;
    }
    // A storyboard row's comma moves its cut's end with it (feedback #9):
    // the resize previews and commits WITH the row, never beside it.
    final resize = _cutSyncResizeFor(after);
    _result = (edits: [(before: _before, after: after)], resize: resize);
    if (resize != null) {
      _roles.internals.dragPreview.value = CutTrimDragPreview(
        previewDurations: resize.durations,
        previewGaps: resize.gaps,
        previewLayers: {after.id: after},
      );
      return;
    }
    // Track-SE drags: the preview channel carries the DISPLAY form (the row
    // gates render cut-local clones) PLUS the global form for the
    // storyboard's track-global strips (UI-R7 #7); the commit uses
    // [_result].
    final window = _window;
    _roles.internals.dragPreview.value = ExposureEdgeDragPreview(
      previewLayer: window == null ? after : window.displayLayer(after),
      globalPreviewLayer: window == null ? null : after,
    );
  }

  void _updateBulk(int cumulativeDelta, Map<LayerId, BulkRetimeRow> bulk) {
    final edits = <({Layer before, Layer after})>[];
    final previews = <LayerId, Layer>{};
    for (final entry in bulk.entries) {
      final beforeLayer = entry.value.before;
      final after = _edge == TimelineBlockEdge.start
          ? _bulkLeadEdgeLayer(beforeLayer, entry.value, cumulativeDelta)
          : _roles.controllers.timelineController.retimedLayerForBlocks(
              layer: beforeLayer,
              newLengthByStart: {
                for (final start in entry.value.starts)
                  if (beforeLayer.timeline[start]?.isDrawing ?? false)
                    start:
                        beforeLayer.timeline[start]!.length! + cumulativeDelta,
              },
            );
      if (after != null && after != beforeLayer) {
        edits.add((before: beforeLayer, after: after));
        // Track-SE rows preview in their DISPLAY form (cut-local axis); the
        // commit keeps the global form (UI-R18 #1 seam).
        previews[entry.key] = _roles.project.isTrackSeLayerId(entry.key)
            ? _trackSe.trackSeWindow.displayLayer(after)
            : after;
      }
    }
    if (edits.isEmpty) {
      _result = null;
      _roles.internals.dragPreview.value = null;
      return;
    }
    // A storyboard row in the bulk drags its cut's length along (feedback
    // #9) — one preview, one release.
    final resize = _bulkCutSyncResize(edits);
    _result = (edits: edits, resize: resize);
    _roles.internals.dragPreview.value = resize != null
        ? CutTrimDragPreview(
            previewDurations: resize.durations,
            previewGaps: resize.gaps,
            previewLayers: previews,
          )
        : previews.length == 1
        ? ExposureEdgeDragPreview(previewLayer: previews.values.single)
        : BlockMoveDragPreview(previewLayers: previews);
  }

  /// A bulk LEAD-edge step for one row — the same law a single grip
  /// follows, reaching as far as the SELECTION does (I-21, 유저
  /// 2026-09-12: 「선택한 블록의 앞에 있는 선택된 모든 블록을 차례대로
  /// 1코마될때까지 밀고, 그 다음도 … 불도저로 쭉 미는느낌. 마지막 선택된
  /// 블록의 헤드에서 멈추도록」).
  ///
  /// ⛔The TRAILING edge keeps the uniform retime above: a bulk trailing
  /// drag re-times every selected block by the same amount, which is the
  /// verb that has always been there and is not what this feedback was
  /// about.
  ///
  /// The row's own dragged block is the one under the pointer where the
  /// pointer is; on the OTHER rows of the selection it is the last selected
  /// block, because that is the one whose front edge faces the same
  /// direction the hand is pulling.
  Layer? _bulkLeadEdgeLayer(
    Layer before,
    BulkRetimeRow row,
    int cumulativeDelta,
  ) {
    final starts = [...row.starts]..sort();
    if (starts.isEmpty) {
      return null;
    }
    final anchor = before.id == _before.id ? _blockStart : starts.last;
    final targetStart = starts.contains(anchor) ? anchor : starts.last;
    // Everything selected IN FRONT of it is what the bulldozer may reach.
    final reach = starts.where((start) => start < targetStart).length;
    return _roles.controllers.timelineController.leadEdgeLayerForBlock(
      layer: before,
      blockStartIndex: targetStart,
      delta: cumulativeDelta,
      reach: math.max(1, reach),
    );
  }

  /// The synced resize a BULK drag owes: the sync row's own edit decides it,
  /// and a bulk that never touched that row owes nothing.
  CutResize? _bulkCutSyncResize(List<({Layer before, Layer after})> edits) {
    final sync = _cutSync;
    if (sync == null) {
      return null;
    }
    for (final edit in edits) {
      if (edit.after.id == sync.layerId) {
        return _cutSyncResizeFor(edit.after);
      }
    }
    return null;
  }

  Layer _draggedLayer(int delta) {
    if (_before.kind == LayerKind.instruction) {
      final shifted = instructionMapWithEdgeShifted(
        _before.instructions,
        spanStartIndex: _blockStart,
        startEdge: _edge == TimelineBlockEdge.start,
        delta: delta,
      );
      return shifted == null ? _before : _before.copyWith(instructions: shifted);
    }
    return _roles.controllers.timelineController.shiftedLayerForEdge(
          layer: _before,
          blockStartIndex: _blockStart,
          edge: _edge,
          delta: delta,
        ) ??
        _before;
  }

  /// The synced resize for [afterRow], or null when this drag carries no cut —
  /// [cutSyncResizeFor], the law the comma buttons commit by too.
  CutResize? _cutSyncResizeFor(Layer afterRow) {
    final sync = _cutSync;
    return sync == null
        ? null
        : cutSyncResizeFor(
            project: _roles.project,
            sync: sync,
            afterRow: afterRow,
          );
  }

  /// Commits the drag as a single undo step (no-op when nothing changed):
  /// the command's execute applies the final result to the repository — and,
  /// for a storyboard row, the cut resize its comma implied (feedback #9:
  /// one undo restores both or a drawing lands outside its cut).
  @override
  void commit() {
    final result = _result;
    _roles.internals.dragPreview.value = null;
    if (result == null) {
      return;
    }
    final sync = _cutSync;
    final resize = result.resize;
    if (sync == null || resize == null) {
      _roles.controllers.timelineController.commitLayerTimelineDrags(
        result.edits,
      );
      _roles.changes.warmActiveCut();
      _roles.changes.notifyChanged();
      return;
    }
    // No re-tile here: "the row tiles its cut" is a WRITE-TIME invariant now
    // ([cutWithCoveringStoryboardRow]), so it holds for this commit, for the
    // undo replay, and for the verbs that never come through a drag at all.
    //
    // No fade re-anchor rides along any more (R4): the fade keys are the
    // TRACK's, on the global axis — a cut resize edits the cut, not them.
    commitWithCutSync(
      controller: _roles.controllers.timelineController,
      edits: result.edits,
      sync: sync,
      resize: resize,
      description: 'Retime storyboard cells',
    );
    _roles.changes.refreshAfterCutCommand();
    _roles.changes.warmActiveCut();
    _roles.changes.notifyChanged();
  }

  /// Drops an in-flight drag preview without touching history (the
  /// repository was never written during the drag).
  @override
  void cancel() {
    _roles.internals.dragPreview.value = null;
  }
}

/// Commits [edits] with the cut resize [sync] and [resize] imply, as ONE undo
/// step (feedback #9: one undo restores both, or a drawing lands outside its
/// cut) — the comma drag's release and the comma buttons' press.
void commitWithCutSync({
  required TimelineController controller,
  required List<({Layer before, Layer after})> edits,
  required CutSyncCapture sync,
  required CutResize resize,
  required String description,
}) => controller.commitLayerTimelineDragsWithCutDurations(
  edits: edits,
  beforeDurations: {sync.cutId: sync.beforeDuration},
  afterDurations: resize.durations,
  beforeGaps: {
    if (sync.nextCutId != null && resize.gaps.containsKey(sync.nextCutId))
      sync.nextCutId!: sync.nextBeforeGap,
  },
  afterGaps: resize.gaps,
  description: description,
);

/// The synced durations/gaps for the row's end having moved to
/// [afterRow]'s end, or null when it has not moved.
///
/// The cut ENDS WHERE THE ROW ENDS — that is what "always synced" means,
/// and taking it literally is also what makes the floor structural: a
/// row's end is its last block's end, so the duration can never land
/// before the last division (the `minimumCutDurationFor` guarantee the
/// plain trim clamps for by hand). Deriving the duration from a DELTA
/// instead would decouple the two the moment a stored row end differs
/// from the cut duration, and then the row's last comma clamps at one
/// frame while the duration keeps absorbing the whole delta.
///
/// 🚨F-91 · F-100: the comma BUTTONS commit by this too — one law for the
/// drag and the press ([commitWithCutSync]).
CutResize? cutSyncResizeFor({
  required ProjectAccess project,
  required CutSyncCapture sync,
  required Layer afterRow,
}) {
  final afterRowEnd = _storedRowEndOf(afterRow);
  // Nothing moved on the row = nothing to sync (a drag that never left
  // its frame must not snap a mismatched pair on its own).
  if (afterRowEnd == sync.beforeRowEnd) {
    return null;
  }
  // The structural floor above holds when the sync row IS the storyboard
  // row. With a second covering kind (image) able to anchor the sync, the
  // storyboard row's divisions are somebody else's data — clamp to their
  // floor explicitly so shrinking through the IMAGE row can never strand a
  // division outside the cut.
  //
  // Whichever row holds the divisions, the floor must be read off the form
  // THIS DRAG is previewing, not off the repository's: the drag never
  // writes mid-gesture, so a repository read answers about the row as it
  // was when the pointer went down. Reading a stale floor against a live
  // row end is `max()` comparing two different rows, and it pinned the
  // duration above the row's end — the committed desync the user hit,
  // invisible on the strip (whose last cell stretches to the duration) and
  // a hole in the timeline (which paints the stored blocks).
  //
  // On the storyboard row this now collapses: a previewed row's end is its
  // last block's end, so `floor <= afterRowEnd` always and the duration
  // simply follows the row.
  final syncedCut = project.cutById(sync.cutId);
  final divisionRow = syncedCut == null
      ? null
      : storyboardLayerForCut(syncedCut);
  final floor = divisionRow == null
      ? 1
      : minimumCutDurationForStoryboardRow(
          divisionRow.id == afterRow.id ? afterRow : divisionRow,
        );
  final duration = math.max(floor, afterRowEnd);
  return (
    durations: {sync.cutId: duration},
    gaps: {
      // The FOLLOWING cut rides the cut's end, so its gap answers to how
      // far that end actually moved — not to how far the row's did.
      ?sync.nextCutId: followingGapAfterEndMove(
        baseGap: sync.nextBeforeGap,
        growth: duration - sync.beforeDuration,
      ),
    },
  );
}
