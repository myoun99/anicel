part of '../editor_session_manager.dart';

/// The EDGE DRAGS — an exposure's comma grip, a cut's end grip and a
/// transition's edge, on the timeline and on the storyboard — as their own
/// object: what was grabbed, the snapshots the drag previews against, the
/// bulk and cut-sync captures, and the steps (begin, update, end, cancel)
/// of each.
///
/// 🚨The second collaborator carved out of `EditorSessionManager` (the
/// audit's SRP cut, 2026-09-02, after the frame-range move). Measured
/// before cutting: the family touched 24 session members and its eleven
/// `_edgeDrag*` fields were read from outside in one or two places each.
/// It reaches the session through `_session` — the same private seams it
/// always used, in the same library, so nothing became public to move.
class _EdgeDrag {
  _EdgeDrag(this._session);

  final EditorSessionManager _session;

  TransitionEdgeDrag? _transitionEdgeDrag;

  /// Grabs [edge] of the transition span starting at [spanStartIndex]
  /// (GLOBAL frame); false when no span starts there — see
  /// [TransitionEdgeDrag.begin] for the active-track scoping rule.
  bool beginTransitionEdgeDrag({
    required int spanStartIndex,
    required TimelineBlockEdge edge,
    LayerId? layerId,
  }) {
    final drag = TransitionEdgeDrag.begin(
      layer: _session.activeTrack.transitionLayer,
      spanStartIndex: spanStartIndex,
      edge: edge,
      layerId: layerId,
      preview: _session.transitionEdgeDragPreview,
      commitInstructions: _session.updateTransitionInstructions,
    );
    if (drag == null) {
      // A refused grip leaves an in-flight drag exactly as it was — the
      // slot is only ever cleared by the drag's own end/cancel.
      return false;
    }
    _transitionEdgeDrag = drag;
    return true;
  }

  void updateTransitionEdgeDrag(int cumulativeDelta) =>
      _transitionEdgeDrag?.update(cumulativeDelta);

  /// Commits the drag as ONE undo step through the row's own writer.
  void endTransitionEdgeDrag() {
    _transitionEdgeDrag?.commit();
    _transitionEdgeDrag = null;
  }

  void cancelTransitionEdgeDrag() {
    _transitionEdgeDrag?.cancel();
    _transitionEdgeDrag = null;
  }

  Layer? _edgeDragBefore;

  TimelineBlockEdge? _edgeDragEdge;

  int? _edgeDragBlockStart;

  /// UI-R17 #3/#8: when the dragged edge belongs to a block INSIDE the
  /// frame range selection, the drag retimes EVERY selected block on
  /// EVERY spanned layer together (null = single-block drag).
  Map<LayerId, List<int>>? _edgeDragBulkStartsByLayer;

  Map<LayerId, Layer>? _edgeDragBulkBefore;

  List<({Layer before, Layer after})>? _edgeDragBulkEdits;

  /// The drag's current result (GLOBAL layer for track SE): [dragPreview]
  /// carries the DISPLAY form, so the commit reads this instead.
  Layer? _edgeDragAfter;

  /// Non-null while a track-SE drag is in flight — previews window through
  /// it before publishing.
  TrackSeWindow? _edgeDragWindow;

  /// Non-null while the dragged (or bulk-spanned) row is a cut-owned
  /// STORYBOARD row (feedback #9): its stored extent and its cut's length
  /// are one thing, so a comma that moves the row's end moves the cut's
  /// end with it — previewed together, committed as ONE undo step.
  ({
    CutId cutId,
    LayerId layerId,
    int beforeDuration,
    int beforeRowEnd,
    CutId? nextCutId,
    int nextBeforeGap,
  })?
  _edgeDragCutSync;

  /// The synced cut resize the release commits (null while the row's end
  /// has not moved). Fields, never the preview channel: a consumer
  /// clearing [dragPreview] mid-drag must not void the commit.
  Map<CutId, int>? _edgeDragAfterDurations;

  Map<CutId, int>? _edgeDragAfterGaps;

  /// Where [layer]'s stored row ends — the cut-length twin the sync rule
  /// keeps the cut's duration equal to.
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

  /// Snapshots the cut-sync half of a storyboard row's comma drag.
  ({
    CutId cutId,
    LayerId layerId,
    int beforeDuration,
    int beforeRowEnd,
    CutId? nextCutId,
    int nextBeforeGap,
  })
  _cutSyncSnapshotFor({required Cut cut, required Layer row}) {
    final next = _nextCutInTrack(cut.id);
    return (
      cutId: cut.id,
      layerId: row.id,
      beforeDuration: cut.duration,
      beforeRowEnd: _storedRowEndOf(row),
      nextCutId: next?.id,
      nextBeforeGap: next?.leadingGapFrames ?? 0,
    );
  }

  /// The synced durations/gaps for the row's end having moved to
  /// [afterRowEnd], or null when it has not moved.
  ///
  /// The cut ENDS WHERE THE ROW ENDS — that is what "always synced" means,
  /// and taking it literally is also what makes the floor structural: a
  /// row's end is its last block's end, so the duration can never land
  /// before the last division (the `minimumCutDurationFor` guarantee the
  /// plain trim clamps for by hand). Deriving the duration from a DELTA
  /// instead would decouple the two the moment a stored row end differs
  /// from the cut duration, and then the row's last comma clamps at one
  /// frame while the duration keeps absorbing the whole delta.
  ({Map<CutId, int> durations, Map<CutId, int> gaps})? _cutSyncResizeFor(
    Layer afterRow,
  ) {
    final sync = _edgeDragCutSync;
    if (sync == null) {
      return null;
    }
    final afterRowEnd = _storedRowEndOf(afterRow);
    // Nothing moved on the row = nothing to sync (a drag that never left
    // its frame must not snap a mismatched pair on its own).
    if (afterRowEnd == sync.beforeRowEnd) {
      return null;
    }
    // The structural floor above holds when the sync row IS the
    // storyboard row. With a second covering kind (image) able to anchor
    // the sync, the storyboard row's divisions are somebody else's data —
    // clamp to their floor explicitly so shrinking through the IMAGE row
    // can never strand a division outside the cut.
    //
    // Whichever row holds the divisions, the floor must be read off the
    // form THIS DRAG is previewing, not off the repository's: the drag
    // never writes mid-gesture, so a repository read answers about the row
    // as it was when the pointer went down. Reading a stale floor against a
    // live row end is `max()` comparing two different rows, and it pinned
    // the duration above the row's end — the committed desync the user hit,
    // invisible on the strip (whose last cell stretches to the duration) and
    // a hole in the timeline (which paints the stored blocks).
    //
    // On the storyboard row this now collapses: a previewed row's end is its
    // last block's end, so `floor <= afterRowEnd` always and the duration
    // simply follows the row.
    final syncedCut = _session.cutById(sync.cutId);
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
        ?sync.nextCutId: _followingGapAfterEndMove(
          baseGap: sync.nextBeforeGap,
          growth: duration - sync.beforeDuration,
        ),
      },
    );
  }

  /// Starts the strip's trailing-edge drag on [cut]'s storyboard row: the
  /// LAST cell's comma, with the cut's length riding it (feedback #9 — the
  /// cut block's last edge is the ROW's edge when the row exists). Joins
  /// the ordinary exposure comma machinery, so the strip, the timeline row
  /// and the X-sheet are one verb.
  bool _beginStoryboardLastCommaDrag(Cut cut, Layer row) {
    int? lastKey;
    for (final entry in row.timeline.entries) {
      if (entry.value.isDrawing && !entry.value.ghost) {
        lastKey = entry.key;
      }
    }
    if (lastKey == null) {
      return false;
    }
    _seedStoryboardCommaDrag(cut, row, lastKey);
    return true;
  }

  /// Seeds the comma machinery for a drag on [row]'s block keyed
  /// [blockKey], with [cut]'s length riding the row end (feedback #9).
  ///
  /// Every field the comma machinery reads, set from scratch. A press
  /// that never moves commits whatever _edgeDragAfter holds, so a value
  /// left by an earlier drag would land on release without the pointer
  /// ever having asked for it.
  void _seedStoryboardCommaDrag(Cut cut, Layer row, int blockKey) {
    _clearEdgeDragFields();
    _edgeDragBefore = row;
    _edgeDragEdge = TimelineBlockEdge.end;
    _edgeDragBlockStart = blockKey;
    _edgeDragCutSync = _cutSyncSnapshotFor(cut: cut, row: row);
  }

  /// Every field a comma drag reads, back to nothing.
  ///
  /// The reason is above: a press that never moves commits whatever
  /// `_edgeDragAfter` holds, so a value an earlier drag left behind lands
  /// on release without the pointer ever asking for it.
  ///
  /// It lives HERE rather than being spelled out at each entry point
  /// because the two entry points had drifted — the storyboard's seed
  /// cleared all of them and [beginExposureEdgeDrag] cleared some, which
  /// is the shape of thing that is latent until an unrelated round adds a
  /// path where the terminators do not run.
  void _clearEdgeDragFields() {
    _edgeDragBefore = null;
    _edgeDragEdge = null;
    _edgeDragBlockStart = null;
    _edgeDragAfter = null;
    _edgeDragWindow = null;
    _edgeDragBulkStartsByLayer = null;
    _edgeDragBulkBefore = null;
    _edgeDragBulkEdits = null;
    _edgeDragAfterDurations = null;
    _edgeDragAfterGaps = null;
    _edgeDragCutSync = null;
  }

  /// Starts a comma drag on the block keyed [blockStartIndex] (cut-local)
  /// of [cutId]'s storyboard row — an INNER panel's trailing edge on the
  /// strip. The edge unification: every trailing edge on a storyboard row
  /// is the SAME comma verb, so the panel's comma resizes, the later
  /// panels ripple along glued, and the cut's length rides the row end
  /// (feedback #9) — where the retired division verb moved a boundary and
  /// pinned the length. Returns false when there is no such drawing block.
  ///
  /// Any cut's panels drag, not only the active cut's: the row is read
  /// through the cut, which is why this does NOT go through
  /// [beginExposureEdgeDrag] — that path resolves the layer and the cut
  /// sync through the ACTIVE cut and would sync the wrong one.
  bool beginStoryboardCommaDrag({
    required CutId cutId,
    required int blockStartIndex,
  }) {
    final cut = _session.cutById(cutId);
    final row = cut == null ? null : storyboardLayerForCut(cut);
    final entry = row?.timeline[blockStartIndex];
    // A negative key is junk data the coverage rule merely tolerates
    // (folded onto frame 0 for display) — resizing it would throw in the
    // comma shift's before-zero guard mid-drag, so refuse at begin.
    if (cut == null ||
        row == null ||
        entry == null ||
        !entry.isDrawing ||
        entry.ghost ||
        blockStartIndex < 0) {
      _cutEdgeDragVerb = null;
      return false;
    }
    _seedStoryboardCommaDrag(cut, row, blockStartIndex);
    // Joins the cut-edge continuations ([updateCutEdgeDrag] and friends):
    // the strip's grips share one set of hooks, and which verb a drag
    // belongs to is the session's to remember, not the host's.
    _cutEdgeDragVerb = _CutEdgeDragVerb.comma;
    return true;
  }

  /// Starts a comma drag on [edge] of the block starting at
  /// [blockStartIndex] (as DISPLAYED — cut-local); returns false when
  /// there is no such block. Instruction rows join the same pipeline —
  /// their spans live on Layer.instructions and shift without ripple.
  /// Track-SE rows convert to the global axis here; a spill-in block's
  /// start edge is rejected (its real start lives in an earlier cut).
  /// Track-global hosts (the storyboard SE strips) pass
  /// [blockStartIsGlobal] with TRUE global starts — any cut's block drags
  /// there (UI-R7 #5), no window conversion, no spill synthesis.
  bool beginExposureEdgeDrag({
    required LayerId layerId,
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    bool blockStartIsGlobal = false,
  }) {
    // SYNCED attach rows own no timing — no comma grips (the BASE's
    // grips move both, W5); free attach rows drag like normal (UI-R21).
    if (_session._folders.isSyncedAttachedLayerId(layerId)) {
      return false;
    }
    // From scratch, the way the storyboard's seed already did it. The two
    // entry points set overlapping halves of the same field set, and only
    // one of them cleared the rest.
    _clearEdgeDragFields();
    if (_session.isTrackSeLayerId(layerId)) {
      final global = _session.trackSeGlobalLayerById(layerId);
      if (global == null) {
        return false;
      }
      final window = _session.trackSeWindow;
      if (!blockStartIsGlobal &&
          edge == TimelineBlockEdge.start &&
          window.isSpillInStart(global, blockStartIndex)) {
        return false;
      }
      final globalStart = blockStartIsGlobal
          ? blockStartIndex
          : window.globalBlockStartFor(global, blockStartIndex);
      if (!(global.timeline[globalStart]?.isDrawing ?? false)) {
        return false;
      }
      _edgeDragBefore = global;
      _edgeDragEdge = edge;
      _edgeDragBlockStart = globalStart;
      _edgeDragWindow = window;
      _edgeDragCutSync = null;
      // SE rows join the selection bulk (UI-R18 #1) — display-local
      // starts only (the storyboard's global-keyed grips stand down).
      if (!blockStartIsGlobal) {
        _captureEdgeBulk(layerId, blockStartIndex, isDrawingBlock: true);
        // The bulk can reach DOWN to the cut's storyboard row, and that row
        // brings its cut's length with it wherever the drag was anchored
        // (feedback #9). The anchor's own kind must not be what decides:
        // an SE-anchored bulk used to retime the row and leave the cut
        // behind, which is the "drawing outside its cut" state this round
        // exists to make unreachable.
        _captureEdgeDragCutSync(null);
      }
      return true;
    }

    final layer = _session._layerById(layerId);
    if (layer == null) {
      return false;
    }
    final isInstructionSpan =
        layer.kind == LayerKind.instruction &&
        layer.instructions.containsKey(blockStartIndex);
    final isDrawingBlock =
        layerKindHoldsDrawings(layer.kind) &&
        // D22: the image row is edge-less (1 cell + fixed hold) — the
        // grips are gone from its chrome, and the session refuses too so
        // the gate and the dispatch stay one answer (T25).
        !layerKindHoldsSingleCel(layer.kind) &&
        (layer.timeline[blockStartIndex]?.isDrawing ?? false);
    if (!isInstructionSpan && !isDrawingBlock) {
      return false;
    }

    _edgeDragBefore = layer;
    _edgeDragEdge = edge;
    _edgeDragBlockStart = blockStartIndex;
    // Dragging an edge inside the selection retimes the WHOLE selection
    // (UI-R17 #3/#8) — every selected block on every spanned layer
    // follows the delta live, one undo step on release.
    _captureEdgeBulk(layerId, blockStartIndex, isDrawingBlock: isDrawingBlock);
    _captureEdgeDragCutSync(layer);
    return true;
  }

  /// Snapshots the cut-length half of an exposure comma drag (feedback #9).
  ///
  /// A storyboard row ANYWHERE in the drag brings its cut's length along —
  /// whether it is the row the pointer grabbed ([anchor]) or one the bulk
  /// selection reaches. Both entry paths call this so the anchor's kind
  /// cannot be what decides whether the pair stays synced.
  void _captureEdgeDragCutSync(Layer? anchor) {
    final bulkBefore = _edgeDragBulkBefore;
    Layer? syncRow;
    // D22: the image row is edge-less now, so it can no longer be the
    // cut-sync anchor either — the STORYBOARD row is the sole rider
    // (otherwise a bulk drag spanning an image row would silently switch
    // which row drives the cut resize).
    bool ridesCutLength(LayerKind kind) =>
        layerKindCoversWithoutGaps(kind) && !layerKindHoldsSingleCel(kind);
    if (bulkBefore != null) {
      for (final candidate in bulkBefore.values) {
        if (ridesCutLength(candidate.kind)) {
          syncRow = candidate;
          break;
        }
      }
    } else if (anchor != null && ridesCutLength(anchor.kind)) {
      syncRow = anchor;
    }
    final activeId = _session.activeCutId;
    final activeCut = syncRow == null || activeId == null
        ? null
        : _session.cutById(activeId);
    _edgeDragCutSync = syncRow == null || activeCut == null
        ? null
        : _cutSyncSnapshotFor(cut: activeCut, row: syncRow);
  }

  /// Captures the bulk-retime set when the dragged edge sits inside the
  /// live selection (UI-R17 #3 → UI-R18 #1: SE rows join through the
  /// commit-key seam — starts and before-layers are COMMIT forms).
  void _captureEdgeBulk(
    LayerId layerId,
    int displayBlockStart, {
    required bool isDrawingBlock,
  }) {
    _edgeDragBulkStartsByLayer = null;
    _edgeDragBulkBefore = null;
    final selection = _session.frameRangeSelection.value;
    if (!isDrawingBlock ||
        selection == null ||
        !selection.coversLayer(layerId) ||
        !selection.contains(displayBlockStart)) {
      return;
    }
    final startsByLayer = <LayerId, List<int>>{};
    final beforeByLayer = <LayerId, Layer>{};
    for (final id in selection.spanLayerIds) {
      // Rows whose timing is not their own stand down — see
      // [EditorSessionManager._standsDownFromRetime].
      if (_session._standsDownFromRetime(id)) {
        continue;
      }
      final display = _session._rangeLayerById(id);
      final commit = _session._commitLayerById(id);
      if (display == null || commit == null) {
        continue;
      }
      final starts = _session._rangeSelections._selectionBlockStarts(
        display,
        selection.startIndex,
        selection.endIndexExclusive,
      );
      if (starts.isEmpty) {
        continue;
      }
      startsByLayer[id] = [
        for (final start in starts) _session._commitBlockStart(id, start),
      ];
      beforeByLayer[id] = commit;
    }
    final multiBlock =
        startsByLayer.length > 1 || (startsByLayer[layerId]?.length ?? 0) > 1;
    if (multiBlock) {
      _edgeDragBulkStartsByLayer = startsByLayer;
      _edgeDragBulkBefore = beforeByLayer;
    }
  }

  Layer _edgeDraggedLayer({
    required Layer before,
    required int blockStart,
    required TimelineBlockEdge edge,
    required int delta,
  }) {
    if (before.kind == LayerKind.instruction) {
      final shifted = instructionMapWithEdgeShifted(
        before.instructions,
        spanStartIndex: blockStart,
        startEdge: edge == TimelineBlockEdge.start,
        delta: delta,
      );
      return shifted == null ? before : before.copyWith(instructions: shifted);
    }
    return _session._timelineController.shiftedLayerForEdge(
          layer: before,
          blockStartIndex: blockStart,
          edge: edge,
          delta: delta,
        ) ??
        before;
  }

  /// Applies the drag's current cumulative frame delta as a live preview
  /// on [_session.dragPreview] — the repository is NOT touched.
  void updateExposureEdgeDrag(int cumulativeDelta) {
    final before = _edgeDragBefore;
    final edge = _edgeDragEdge;
    final blockStart = _edgeDragBlockStart;
    if (before == null || edge == null || blockStart == null) {
      return;
    }

    // Bulk selection retime (UI-R17 #3/#8): the edge delta becomes a
    // LENGTH delta on every selected block of every spanned layer (end
    // edge: +delta, start edge: dragging right shrinks); the ripple
    // packs/pushes downstream per layer. One composite undo on release.
    final bulkStarts = _edgeDragBulkStartsByLayer;
    final bulkBefore = _edgeDragBulkBefore;
    if (bulkStarts != null && bulkBefore != null) {
      _updateBulkExposureEdgeDrag(edge, cumulativeDelta, bulkStarts, bulkBefore);
      return;
    }

    final after = _edgeDraggedLayer(
      before: before,
      blockStart: blockStart,
      edge: edge,
      delta: cumulativeDelta,
    );
    // No notifyEditActivity here: composites self-validate against the
    // committed edit, the drag-end warm request re-renders what changed,
    // and the idle gate's REAL-time delay would leave timers pending under
    // the fake test clock.
    _edgeDragAfter = after == before ? null : after;
    // A storyboard row's comma moves its cut's end with it (feedback #9):
    // the resize previews and commits WITH the row, never beside it.
    final resize = after == before ? null : _cutSyncResizeFor(after);
    _edgeDragAfterDurations = resize?.durations;
    _edgeDragAfterGaps = resize?.gaps;
    if (resize != null) {
      _session.dragPreview.value = CutTrimDragPreview(
        previewDurations: resize.durations,
        previewGaps: resize.gaps,
        previewLayers: {after.id: after},
      );
      return;
    }
    // Track-SE drags: the preview channel carries the DISPLAY form (the
    // row gates render cut-local clones) PLUS the global form for the
    // storyboard's track-global strips (UI-R7 #7); the commit uses
    // _edgeDragAfter.
    final window = _edgeDragWindow;
    _session.dragPreview.value = after == before
        ? null
        : ExposureEdgeDragPreview(
            previewLayer: window == null ? after : window.displayLayer(after),
            globalPreviewLayer: window == null ? null : after,
          );
  }

  void _updateBulkExposureEdgeDrag(TimelineBlockEdge edge, int cumulativeDelta, Map<LayerId, List<int>> bulkStarts, Map<LayerId, Layer> bulkBefore) {
    final lengthDelta = edge == TimelineBlockEdge.end
        ? cumulativeDelta
        : -cumulativeDelta;
    final edits = <({Layer before, Layer after})>[];
    final previews = <LayerId, Layer>{};
    for (final entry in bulkStarts.entries) {
      final beforeLayer = bulkBefore[entry.key];
      if (beforeLayer == null) {
        continue;
      }
      final after = _session._timelineController.retimedLayerForBlocks(
        layer: beforeLayer,
        newLengthByStart: {
          for (final start in entry.value)
            if (beforeLayer.timeline[start]?.isDrawing ?? false)
              start: beforeLayer.timeline[start]!.length! + lengthDelta,
        },
      );
      if (after != null && after != beforeLayer) {
        edits.add((before: beforeLayer, after: after));
        // Track-SE rows preview in their DISPLAY form (cut-local axis);
        // the commit keeps the global form (UI-R18 #1 seam).
        previews[entry.key] = _session.isTrackSeLayerId(entry.key)
            ? _session.trackSeWindow.displayLayer(after)
            : after;
      }
    }
    _edgeDragBulkEdits = edits.isEmpty ? null : edits;
    // A storyboard row in the bulk drags its cut's length along
    // (feedback #9) — one preview, one release.
    ({Map<CutId, int> durations, Map<CutId, int> gaps})? resize;
    final sync = _edgeDragCutSync;
    if (sync != null) {
      for (final edit in edits) {
        if (edit.after.id == sync.layerId) {
          resize = _cutSyncResizeFor(edit.after);
          break;
        }
      }
    }
    _edgeDragAfterDurations = resize?.durations;
    _edgeDragAfterGaps = resize?.gaps;
    _session.dragPreview.value = previews.isEmpty
        ? null
        : resize != null
        ? CutTrimDragPreview(
            previewDurations: resize.durations,
            previewGaps: resize.gaps,
            previewLayers: previews,
          )
        : previews.length == 1
        ? ExposureEdgeDragPreview(previewLayer: previews.values.single)
        : BlockMoveDragPreview(previewLayers: previews);
    return;
  }

  /// Commits the drag as a single undo step (no-op when nothing changed):
  /// the command's execute applies the final result to the repository —
  /// and, for a storyboard row, the cut resize its comma implied
  /// (feedback #9: one undo restores both or a drawing lands outside its
  /// cut).
  void endExposureEdgeDrag() {
    final before = _edgeDragBefore;
    final after = _edgeDragAfter;
    final bulkEdits = _edgeDragBulkEdits;
    final sync = _edgeDragCutSync;
    final afterDurations = _edgeDragAfterDurations;
    final afterGaps = _edgeDragAfterGaps;
    _edgeDragBefore = null;
    _edgeDragEdge = null;
    _edgeDragBlockStart = null;
    _edgeDragBulkStartsByLayer = null;
    _edgeDragBulkBefore = null;
    _edgeDragBulkEdits = null;
    _edgeDragAfter = null;
    _edgeDragWindow = null;
    _edgeDragCutSync = null;
    _edgeDragAfterDurations = null;
    _edgeDragAfterGaps = null;
    _session.dragPreview.value = null;
    if (bulkEdits != null) {
      // The selection covers the same cels after the retime (starts kept).
      _commitEdgeDragEdits(
        edits: bulkEdits,
        sync: sync,
        afterDurations: afterDurations,
        afterGaps: afterGaps,
      );
      return;
    }
    if (before == null) {
      return;
    }

    if (after == null || after == before) {
      return;
    }
    _commitEdgeDragEdits(
      edits: [(before: before, after: after)],
      sync: sync,
      afterDurations: afterDurations,
      afterGaps: afterGaps,
    );
  }

  /// One release, one undo step: the layer edits, plus the synced cut
  /// resize when a storyboard row's end moved.
  void _commitEdgeDragEdits({
    required List<({Layer before, Layer after})> edits,
    required ({
      CutId cutId,
      LayerId layerId,
      int beforeDuration,
      int beforeRowEnd,
      CutId? nextCutId,
      int nextBeforeGap,
    })?
    sync,
    required Map<CutId, int>? afterDurations,
    required Map<CutId, int>? afterGaps,
  }) {
    if (sync == null || afterDurations == null || afterGaps == null) {
      _session._timelineController.commitLayerTimelineDrags(edits);
      _session._warmActiveCut();
      _session._notifyChanged();
      return;
    }
    final beforeDurations = <CutId, int>{sync.cutId: sync.beforeDuration};
    // No re-tile here: "the row tiles its cut" is a WRITE-TIME invariant now
    // ([cutWithCoveringStoryboardRow]), so it holds for this commit, for the
    // undo replay, and for the verbs that never come through a drag at all.
    //
    // No fade re-anchor rides along any more (R4): the fade keys are the
    // TRACK's, on the global axis — a cut resize edits the cut, not them.
    _session._timelineController.commitLayerTimelineDragsWithCutDurations(
      edits: edits,
      beforeDurations: beforeDurations,
      afterDurations: afterDurations,
      beforeGaps: {
        if (sync.nextCutId != null && afterGaps.containsKey(sync.nextCutId))
          sync.nextCutId!: sync.nextBeforeGap,
      },
      afterGaps: afterGaps,
      description: 'Retime storyboard cells',
    );
    _session._refreshAfterCutCommand();
    _session._warmActiveCut();
    _session._notifyChanged();
  }

  Map<CutId, int>? _cutTrimBeforeDurations;

  Map<CutId, int>? _cutTrimBeforeGaps;

  Map<CutId, int>? _cutTrimAfterDurations;

  Map<CutId, int>? _cutTrimAfterGaps;

  CutId? _cutTrimCutId;

  CutId? _cutTrimNextCutId;

  TimelineBlockEdge? _cutTrimEdge;

  /// Track cut order + the dragged cut's slot, snapshotted for START-edge
  /// slides (the leftward cascade pushes predecessor gaps, R12-⑦).
  List<CutId>? _cutTrimOrder;

  int? _cutTrimIndex;

  /// Which conte PANEL a START-edge drag grabbed, cut-local. Every panel
  /// hangs a front grip on the strip (user's rule 2026-08-02), and the
  /// panel you grabbed is the one that loses commas — so the verb cannot be
  /// resolved from the cut alone. Taken at BEGIN and kept here for the same
  /// reason [_cutEdgeDragVerb] is.
  int? _cutTrimPanelIndex;

  /// The conte row as the in-flight LEAD drag would leave it, stashed for
  /// the release. The row rewrite is part of the SAME edit as the duration
  /// change — deriving it again at commit time would read the repository,
  /// which no longer says what the drag decided.
  List<({Layer before, Layer after})>? _cutTrimAfterRowEdits;

  /// Which verb the in-flight cut-edge drag belongs to. One shape of edge,
  /// and where it sits decides what it re-times — the answer is taken at
  /// BEGIN and kept HERE, in the session the continuations already reach,
  /// so a host rebuild mid-drag cannot re-route the release onto a verb
  /// whose fields were never set (the failure that sank the first #5
  /// attempt).
  _CutEdgeDragVerb? _cutEdgeDragVerb;

  /// Starts a cut edge drag on [cutId]'s [edge].
  ///
  /// - the LEAD edge is one verb for every cut (R10 R4): the cut loses
  ///   frames off its front, its END holds so the cuts behind never move,
  ///   the cut GLUED in front translates wholesale, and the difference
  ///   comes to rest at the head of the film ([planCutLeadEdge]). On a cut
  ///   WITH a conte row the frames come off [panelIndex] — the panel the
  ///   grip belongs to — and every other panel keeps its commas
  ///   ([storyboardTimelineWithPanelLeadRetimed], user's rule 2026-08-02).
  ///   The row is what floors the drag, and it floors the GRABBED panel,
  ///   not the last one;
  /// - the TRAILING edge still asks what it sits on (feedback #9): on a
  ///   cut with a storyboard row it is the LAST cell's comma and the cut's
  ///   length follows it (the always-synced pair); otherwise it trims the
  ///   duration, growth eating the following gap first.
  ///
  /// The continuations ([updateCutEdgeDrag], [endCutEdgeDrag],
  /// [cancelCutEdgeDrag]) follow whichever verb began — they carry a delta
  /// and nothing else.
  bool beginCutEdgeDrag({
    required CutId cutId,
    required TimelineBlockEdge edge,
    int panelIndex = 0,
  }) {
    final cut = _session.cutById(cutId);
    final row = cut == null ? null : storyboardLayerForCut(cut);
    if (cut != null && row != null) {
      // R10 R4: only the TRAILING edge still asks about the conte row, and
      // its two arms agree at the cut level. The LEAD edge does not ask
      // any more — one gesture, one meaning, whether or not the cut has
      // been drawn on. The row still bounds the drag, through
      // [minimumCutDurationFor]: you cannot trim past your own panels.
      if (edge == TimelineBlockEdge.end &&
          _beginStoryboardLastCommaDrag(cut, row)) {
        _cutEdgeDragVerb = _CutEdgeDragVerb.comma;
        return true;
      }
    }
    if (_beginCutTrimDrag(cutId: cutId, edge: edge, panelIndex: panelIndex)) {
      _cutEdgeDragVerb = _CutEdgeDragVerb.cutTrim;
      return true;
    }
    _cutEdgeDragVerb = null;
    return false;
  }

  /// Applies the drag's cumulative frame delta to whichever verb
  /// [beginCutEdgeDrag] (or [beginStoryboardCommaDrag]) chose.
  void updateCutEdgeDrag(int cumulativeDelta) {
    switch (_cutEdgeDragVerb) {
      case null:
        return;
      case _CutEdgeDragVerb.cutTrim:
        _updateCutTrimDrag(cumulativeDelta);
      case _CutEdgeDragVerb.comma:
        updateExposureEdgeDrag(cumulativeDelta);
    }
  }

  /// Commits whichever verb began, as a single undo step.
  void endCutEdgeDrag() {
    final verb = _cutEdgeDragVerb;
    _cutEdgeDragVerb = null;
    switch (verb) {
      case null:
        return;
      case _CutEdgeDragVerb.cutTrim:
        _endCutTrimDrag();
      case _CutEdgeDragVerb.comma:
        endExposureEdgeDrag();
    }
  }

  /// Drops whichever verb began without touching history.
  void cancelCutEdgeDrag() {
    final verb = _cutEdgeDragVerb;
    _cutEdgeDragVerb = null;
    switch (verb) {
      case null:
        return;
      case _CutEdgeDragVerb.cutTrim:
        _cancelCutTrimDrag();
      case _CutEdgeDragVerb.comma:
        cancelExposureEdgeDrag();
    }
  }

  bool _beginCutTrimDrag({
    required CutId cutId,
    required TimelineBlockEdge edge,
    int panelIndex = 0,
  }) {
    final layout = buildStoryboardTimelineLayout(
      _session._repository.requireProject(),
    );
    StoryboardTimelineLayoutEntry? entry;
    for (final candidate in layout) {
      if (candidate.cutId == cutId) {
        entry = candidate;
        break;
      }
    }
    if (entry == null) {
      return false;
    }
    StoryboardTimelineLayoutEntry? next;
    if (edge == TimelineBlockEdge.end) {
      for (final candidate in layout) {
        if (candidate.trackId == entry.trackId &&
            candidate.cutIndex == entry.cutIndex + 1) {
          next = candidate;
          break;
        }
      }
    }

    _cutTrimBeforeDurations = {entry.cutId: entry.cut.duration};
    if (edge == TimelineBlockEdge.start) {
      // The start TRIM's leftward growth cascades through the
      // PREDECESSORS' gaps, so the whole track's order and gaps join the
      // drag snapshot.
      final trackEntries = [
        for (final candidate in layout)
          if (candidate.trackId == entry.trackId) candidate,
      ];
      _cutTrimOrder = [for (final candidate in trackEntries) candidate.cutId];
      _cutTrimIndex = entry.cutIndex;
      _cutTrimBeforeGaps = {
        for (final candidate in trackEntries)
          candidate.cutId: candidate.cut.leadingGapFrames,
      };
    } else {
      _cutTrimBeforeGaps = {
        entry.cutId: entry.cut.leadingGapFrames,
        if (next != null) next.cutId: next.cut.leadingGapFrames,
      };
    }
    _cutTrimCutId = cutId;
    _cutTrimNextCutId = next?.cutId;
    _cutTrimEdge = edge;
    _cutTrimPanelIndex = panelIndex;
    // The release commits from these, so a new drag must not inherit the
    // previous one's result: a press that never moves would otherwise land
    // an edit the pointer never asked for.
    _cutTrimAfterDurations = null;
    _cutTrimAfterGaps = null;
    _cutTrimAfterRowEdits = null;
    return true;
  }

  /// How far a LEAD drag on [cutId]'s [panelIndex] may shrink the cut, as a
  /// minimum DURATION — the shape [planCutLeadEdge] wants.
  ///
  /// The floor belongs to the panel the grip is on: that panel keeps one
  /// frame, and since every other panel keeps its commas, the cut's floor is
  /// its current duration less that panel's room. A cut with no conte row
  /// (or a row a drag cannot address) keeps the plain one-frame floor.
  ///
  /// ⚠️ [minimumCutDurationFor] is the LAST panel's floor and is the right
  /// answer for the trailing edge only. Using it here let a drag ask the
  /// first cell for a negative length — the assert in
  /// [StoryboardCoverageCell] — whenever the grabbed panel was shorter than
  /// the last one.
  int _leadMinimumDurationFor(Cut cut, int panelIndex) {
    final row = storyboardLayerForCut(cut);
    if (row == null) {
      return 1;
    }
    final maxShrink = storyboardPanelLeadMaxShrink(
      timeline: row.timeline,
      cutDuration: cut.duration,
      panelIndex: panelIndex,
    );
    return maxShrink == null ? 1 : math.max(1, cut.duration - maxShrink);
  }

  /// Applies the drag's cumulative frame delta as a live preview on
  /// [_session.dragPreview] (the repository is NOT touched).
  ///
  /// END edge: the duration changes; growth consumes the FOLLOWING cut's
  /// leading gap first (that cut holds still until the gap is spent, then
  /// ripples). Shrinking follows the timeline's block language (R10-⑦):
  /// only an ATTACHED next cut rides the boundary — a detached one holds
  /// its global position (its gap grows by the shrink). START edge: the
  /// LEAD verb ([planCutLeadEdge], R10 R4) — the END stays put and the
  /// LENGTH changes, so nothing behind moves; a GLUED predecessor rides
  /// the boundary in either direction and a separated one lets its gap
  /// absorb the move; growth is walled by frame 0 and shrink by
  /// [minimumCutDurationFor].
  void _updateCutTrimDrag(int cumulativeDelta) {
    final beforeDurations = _cutTrimBeforeDurations;
    final beforeGaps = _cutTrimBeforeGaps;
    final cutId = _cutTrimCutId;
    final edge = _cutTrimEdge;
    if (beforeDurations == null ||
        beforeGaps == null ||
        cutId == null ||
        edge == null) {
      return;
    }

    final durations = <CutId, int>{};
    final gaps = <CutId, int>{};
    // The floor is the STORYBOARD row's extent, not one frame: its cells
    // are panels OF this cut, so an edge cannot be dragged past the panel it
    // belongs to (delete the cells to shrink further). Cuts without a
    // storyboard row keep the plain one-frame floor.
    //
    // WHICH panel is the floor differs by edge, and that is not a detail:
    // the trailing edge sits on the LAST panel, the leading edge on the one
    // it was grabbed from.
    final trimmedCut = _session.cutById(cutId);
    final minDuration = trimmedCut == null
        ? 1
        : edge == TimelineBlockEdge.end
        ? minimumCutDurationFor(trimmedCut)
        : _leadMinimumDurationFor(trimmedCut, _cutTrimPanelIndex ?? 0);
    if (edge == TimelineBlockEdge.end) {
      final newDuration = math.max(
        minDuration,
        beforeDurations[cutId]! + cumulativeDelta,
      );
      durations[cutId] = newDuration;
      final nextId = _cutTrimNextCutId;
      if (nextId != null) {
        gaps[nextId] = _followingGapAfterEndMove(
          baseGap: beforeGaps[nextId]!,
          growth: newDuration - beforeDurations[cutId]!,
        );
      }
    } else {
      // START edge = the LEAD edge, and R10 R4 made it the frame axis's
      // answer ([planCutLeadEdge] over the shared contact rule): the cut's
      // END stays put and its LENGTH changes, so followers never move; the
      // cut GLUED in front translates wholesale rather than having a gap
      // torn open between them, its own glued predecessor follows, and the
      // difference comes to rest at the head of the film.
      //
      // Two behaviours used to live here — this one's ancestor opened the
      // dragged cut's own leading gap, and a cut WITH a conte row went
      // somewhere else entirely (a lead retime that pinned the start and
      // pulled the followers in). Neither was what the timeline does, and
      // the fork is why the storyboard read as a different instrument.
      final order = _cutTrimOrder!;
      final plan = planCutLeadEdge(
        slots: [
          for (final id in order)
            (
              id: id,
              leadingGapFrames: beforeGaps[id]!,
              // Nothing but the dragged cut changes duration mid-drag, and
              // the preview never touches the repository, so a live read
              // IS the before-value for every slot.
              duration: _session.cutById(id)?.duration ?? 1,
            ),
        ],
        targetIndex: _cutTrimIndex!,
        frameDelta: cumulativeDelta,
        minDuration: minDuration,
      );
      durations.addAll(plan.durations);
      gaps.addAll(plan.gaps);
    }

    // The conte row is re-keyed by the SAME drag, and it is re-keyed HERE
    // rather than at the release: the strip and the timeline both re-derive
    // panels from (row, duration), so a preview that moved only the duration
    // showed the LAST panel shrinking for the whole gesture and then jumped
    // to the real answer on pointer-up.
    //
    // The shift is read off the plan's own result, never off
    // [cumulativeDelta] — the plan clamps, and the raw delta does not know
    // it did.
    final rowEdits = edge == TimelineBlockEdge.start
        ? _storyboardRowEditsForLeadDrag(
            cutId: cutId,
            panelIndex: _cutTrimPanelIndex ?? 0,
            applied: beforeDurations[cutId]! - (durations[cutId] ?? 0),
          )
        : const <({Layer before, Layer after})>[];

    final changed =
        durations[cutId] != beforeDurations[cutId] ||
        gaps.entries.any((entry) => beforeGaps[entry.key] != entry.value);
    // The release commits from THESE, never from the preview channel: a
    // consumer clearing [dragPreview] mid-drag must not be able to void
    // the commit.
    _cutTrimAfterDurations = changed ? durations : null;
    _cutTrimAfterGaps = changed ? gaps : null;
    _cutTrimAfterRowEdits = changed ? rowEdits : null;
    _session.dragPreview.value = changed
        ? CutTrimDragPreview(
            previewDurations: durations,
            previewGaps: gaps,
            previewLayers: {
              for (final edit in rowEdits) edit.after.id: edit.after,
            },
          )
        : null;
  }

  /// The conte-row rewrite a LEAD drag owes: the grabbed panel loses
  /// [applied] frames off its front and every other panel keeps its commas.
  ///
  /// Empty when the cut has no row, when the drag was clamped to nothing, or
  /// when the row cannot be addressed — in each of those the plain cut
  /// duration change is the whole edit.
  List<({Layer before, Layer after})> _storyboardRowEditsForLeadDrag({
    required CutId cutId,
    required int panelIndex,
    required int applied,
  }) {
    if (applied == 0) {
      return const [];
    }
    final cut = _session.cutById(cutId);
    final row = cut == null ? null : storyboardLayerForCut(cut);
    if (row == null) {
      return const [];
    }
    final retimed = storyboardTimelineWithPanelLeadRetimed(
      timeline: row.timeline,
      cutDuration: cut!.duration,
      panelIndex: panelIndex,
      delta: applied,
    );
    if (retimed == null || mapEquals(retimed, row.timeline)) {
      return const [];
    }
    return [(before: row, after: row.copyWith(timeline: retimed))];
  }

  /// Commits the drag as a single undo step (no-op when nothing changed):
  /// the command's execute applies the final durations AND gaps, plus the
  /// fade re-anchor (W4 fade durability) — a trimmed cut's CANONICAL fade
  /// envelope is rebuilt for the new duration so the fade-out keeps riding
  /// the cut's end. Hand-keyed opacity lanes are left untouched (the
  /// "Opacity lane = fade envelope" invariant only owns the canonical
  /// shape).
  void _endCutTrimDrag() {
    final beforeDurations = _cutTrimBeforeDurations;
    final beforeGaps = _cutTrimBeforeGaps;
    final afterDurations = _cutTrimAfterDurations;
    final afterGaps = _cutTrimAfterGaps;
    final leadRowEdits = _cutTrimAfterRowEdits;
    _cancelCutTrimDrag();
    if (beforeDurations == null ||
        beforeGaps == null ||
        afterDurations == null ||
        afterGaps == null) {
      return;
    }

    final scopedBeforeDurations = {
      for (final id in afterDurations.keys) id: beforeDurations[id]!,
    };
    final scopedBeforeGaps = {
      for (final id in afterGaps.keys) id: beforeGaps[id]!,
    };

    // "The cut ENDS WHERE THE ROW ENDS" (see [_cutSyncResizeFor]). A drag
    // that changes the duration without going near the row would leave a
    // conte cut's stored row ending somewhere the cut no longer does — and
    // the next end/comma drag, which derives the duration FROM the row end,
    // would snap the cut back to the stale one and shove the cuts behind it.
    //
    // The two edges pay that debt at opposite ends of the row. A LEAD drag
    // already decided which panel gives way, back when it knew the pointer's
    // grip. A TRAILING one has no such record, and its last panel simply
    // follows the new end.
    final rowEdits = leadRowEdits != null && leadRowEdits.isNotEmpty
        ? leadRowEdits
        : _storyboardRowEditsForResizedCuts(
            beforeDurations: scopedBeforeDurations,
            afterDurations: afterDurations,
          );
    if (rowEdits.isNotEmpty) {
      _session._timelineController.commitLayerTimelineDragsWithCutDurations(
        edits: rowEdits,
        beforeDurations: scopedBeforeDurations,
        afterDurations: afterDurations,
        beforeGaps: scopedBeforeGaps,
        afterGaps: afterGaps,
        description: 'Trim cut duration',
      );
      _session._refreshAfterCutCommand();
      _session._warmActiveCut();
      _session._notifyChanged();
      return;
    }

    _session._cutCommandCoordinator.commitCutDurationDrag(
      beforeDurations: scopedBeforeDurations,
      afterDurations: afterDurations,
      beforeGaps: scopedBeforeGaps,
      afterGaps: afterGaps,
    );
    _session._refreshAfterCutCommand();
    _session._notifyChanged();
  }

  /// The storyboard-row rewrites a duration change owes, one per resized
  /// cut that HAS a row: the row re-tiled to the cut's new length, so its
  /// last panel ends exactly where the cut now does.
  ///
  /// Empty when no resized cut has a row — the overwhelmingly common case,
  /// and the one that keeps the plain cut-duration command as the commit.
  List<({Layer before, Layer after})> _storyboardRowEditsForResizedCuts({
    required Map<CutId, int> beforeDurations,
    required Map<CutId, int> afterDurations,
  }) {
    final edits = <({Layer before, Layer after})>[];
    for (final entry in afterDurations.entries) {
      if (beforeDurations[entry.key] == entry.value) {
        continue;
      }
      final cut = _session.cutById(entry.key);
      final row = cut == null ? null : storyboardLayerForCut(cut);
      if (row == null) {
        continue;
      }
      final filled = storyboardTimelineFilledToCover(
        timeline: row.timeline,
        cutDuration: entry.value,
      );
      if (filled == null || mapEquals(filled, row.timeline)) {
        continue;
      }
      edits.add((before: row, after: row.copyWith(timeline: filled)));
    }
    return edits;
  }

  /// The END-boundary gap rule every verb that moves a cut's end shares.
  /// Growth: consume the following cut's gap, then push. Shrink: an
  /// ATTACHED next cut (gap 0 at drag start) rides the boundary; a
  /// DETACHED one holds its global position — the gap absorbs the shrink.
  int _followingGapAfterEndMove({required int baseGap, required int growth}) =>
      growth > 0
      ? math.max(0, baseGap - growth)
      : (baseGap > 0 ? baseGap - growth : 0);

  /// Drops an in-flight trim preview without touching history (the
  /// repository was never written during the drag).
  void _cancelCutTrimDrag() {
    _cutTrimBeforeDurations = null;
    _cutTrimBeforeGaps = null;
    _cutTrimAfterDurations = null;
    _cutTrimAfterGaps = null;
    _cutTrimCutId = null;
    _cutTrimNextCutId = null;
    _cutTrimEdge = null;
    _cutTrimOrder = null;
    _cutTrimIndex = null;
    _cutTrimPanelIndex = null;
    _cutTrimAfterRowEdits = null;
    _session.dragPreview.value = null;
  }

  /// The cut after [cutId] on its own track, or null at the track's end.
  Cut? _nextCutInTrack(CutId cutId) {
    for (final track in _session._repository.requireProject().tracks) {
      final cuts = track.cuts;
      for (var index = 0; index < cuts.length; index += 1) {
        if (cuts[index].id == cutId) {
          return index + 1 < cuts.length ? cuts[index + 1] : null;
        }
      }
    }
    return null;
  }

  /// Drops an in-flight drag preview without touching history (the
  /// repository was never written during the drag).
  void cancelExposureEdgeDrag() {
    _edgeDragBefore = null;
    _edgeDragEdge = null;
    _edgeDragBlockStart = null;
    _edgeDragBulkStartsByLayer = null;
    _edgeDragBulkBefore = null;
    _edgeDragBulkEdits = null;
    _edgeDragAfter = null;
    _edgeDragWindow = null;
    _edgeDragCutSync = null;
    _edgeDragAfterDurations = null;
    _edgeDragAfterGaps = null;
    _session.dragPreview.value = null;
  }

  /// The storyboard's comma press: the selection's blocks, else THE BLOCK
  /// UNDER THE CURSOR takes length [comma] — one rule for every block kind
  /// (B8: 「컷블록 위 4 = 컷길이 4」, superseded by D28 2026-08-18 exactly
  /// where the cut carries a storyboard layer — its PANEL takes the comma
  /// then), each kind through the SAME machinery its own grips already
  /// commit with:
  ///
  /// - a CUT block rides the trailing-edge drag verbs, so a conte row's
  ///   last comma and the following gap behave exactly as if the edge had
  ///   been dragged to frame [comma];
  /// - an SE block takes the timeline comma buttons' own retime
  ///   ([TimelineController.retimeBlocksForLayers]), stated in global keys;
  /// - a TRANSITION span rides its edge-drag verbs (the grips own length).
  void setCommaForStoryboardCursor(int comma) {
    if (comma < 1) {
      return;
    }
    // The strip's cut-local selection: the shared verb's selection branch,
    // verbatim. ⚠️Guarded so its active-layer fallback — the other panel's
    // subject — stays unreachable from this panel.
    final selection = _session.frameRangeSelection.value;
    if (selection != null) {
      // Single-cel rows never appear in the collector, so a non-null map
      // IS a retimable one.
      if (_session._rangeSelections._cutLocalSelectionBlockStartsByLayer() !=
          null) {
        _session.setCommaForSelectionOrCurrent(comma);
      }
      return;
    }
    // The S rows' track-axis selection: the same retime, already in global
    // commit keys (the shared verb never had this rung — its selection
    // branch reads the cut-local notifier alone).
    final trackTargets = _session._rangeSelections
        ._trackSelectionBlockStartsByLayer();
    if (trackTargets != null) {
      // ⛔No active-cut guard: these starts are ALREADY global keys and the
      // retime applies no lens, so a gap changes nothing about them (H11).
      _session._timelineController.retimeBlocksForLayers({
        for (final entry in trackTargets.entries)
          entry.key: {for (final start in entry.value) start: comma},
      });
      _session._warmActiveCut();
      _session._notifyChanged();
      return;
    }
    switch (_session._storyboardCursor._storyboardCursorBlockOrNull()) {
      case null:
        return;
      case _StoryboardCursorCutBlock(:final cut):
        if (comma == cut.duration) {
          return; // A no-move drag must not land an undo step.
        }
        if (!beginCutEdgeDrag(cutId: cut.id, edge: TimelineBlockEdge.end)) {
          return;
        }
        updateCutEdgeDrag(comma - cut.duration);
        endCutEdgeDrag();
      case _StoryboardCursorSeBlock(:final layerId, :final blockStartIndex):
        if (_session.activeCutOrNull == null) {
          return;
        }
        _session._timelineController.retimeBlocksForLayers({
          layerId: {blockStartIndex: comma},
        });
        _session._warmActiveCut();
        _session._notifyChanged();
      case _StoryboardCursorTransitionSpan(
        :final spanStartIndex,
        :final spanLength,
      ):
        if (comma == spanLength) {
          return;
        }
        if (!beginTransitionEdgeDrag(
          spanStartIndex: spanStartIndex,
          edge: TimelineBlockEdge.end,
        )) {
          return;
        }
        updateTransitionEdgeDrag(comma - spanLength);
        endTransitionEdgeDrag();
      case _StoryboardCursorStoryboardPanel(
        :final cut,
        :final panelStartIndex,
        :final panelLength,
      ):
        // D28: the panel rides the storyboard comma drag — ripple + the
        // cut length following the LAST panel's edge (feedback #9), one
        // drag = one undo, exactly as the strip's own grips commit.
        if (comma == panelLength) {
          return;
        }
        if (!beginStoryboardCommaDrag(
          cutId: cut.id,
          blockStartIndex: panelStartIndex,
        )) {
          return;
        }
        updateCutEdgeDrag(comma - panelLength);
        endCutEdgeDrag();
    }
  }
}
