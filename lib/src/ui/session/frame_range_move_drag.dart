part of '../editor_session_manager.dart';

/// The frame-range MOVE DRAG — a selection of cells picked up and put
/// down on the frame axis, previewed live and committed once — as its
/// own object: its state (what was picked up, the plans, the previews)
/// and its steps (begin, update, end, cancel, and the run-edge verb
/// that shares its lattice).
///
/// 🚨The first collaborator carved out of `EditorSessionManager`
/// (2026-09-02, the audit's SRP cut). Measured before cutting: the family
/// touched 46 session members; the twenty `_rangeMove*` fields were read
/// from outside it in twenty places, which now read `_rangeMove.x`. It
/// reaches the session through `_session` — the same private seams it
/// always used, in the same library, so nothing became public to move.
class _FrameRangeMoveDrag {
  _FrameRangeMoveDrag(this._session);

  final EditorSessionManager _session;

  /// Whether the drag in flight belongs to the TRACK-axis selection (the
  /// storyboard's rows) rather than the cut-local one.
  ///
  /// The machine itself is axis-free: it plans on its sources' COMMIT
  /// forms, which for a track-SE row is the global layer either way. Only
  /// two things depend on the axis — which selection object the live and
  /// landed spans are published to, and which one a cancel restores — and
  /// both go through [_rangeMoveSelection].
  bool _rangeMoveOnTrackAxis = false;

  /// THE selection this move reads and publishes, in the axis its sources
  /// are keyed by. Every step of the drag writes through here instead of
  /// touching a notifier directly, so the machine never has to know which
  /// object owns it.
  TimelineFrameRangeSelection? get _rangeMoveSelection {
    if (!_rangeMoveOnTrackAxis) {
      return _session.frameRangeSelection.value;
    }
    final live = _session.trackFrameRangeSelection.value;
    // C②: an ESCALATED span anchors on a LANE row — its owning layer is
    // the machine's anchor layer, so the span the band advertises is the
    // span the move machine accepts.
    //
    // 🚨C3-lane-move: this used to switch on the address TYPE and fall to
    // null on anything else, and the `layerIds` below dropped every row
    // that was not a `LayerRowAddress`. Both are the same mistake stated
    // twice: a lane row HAS an owning layer, so asking the address for it
    // ([TimelineRowAddress.owningLayerId]) is the whole answer. Without it
    // a band that advertised a move quietly became a re-select — the move
    // machine got a null span and the press fell through to the select
    // path, with nothing on screen to say so.
    final anchorLayerId = live?.anchorRow.owningLayerId;
    if (live == null || anchorLayerId == null) {
      return null;
    }
    return TimelineFrameRangeSelection(
      layerId: anchorLayerId,
      startIndex: live.startFrame,
      endIndexExclusive: live.endFrameExclusive,
      // Deduped in display order: a layer row and its own lane rows are
      // several rows of ONE layer, and the move machine plans per layer.
      layerIds: {for (final row in live.spanRows) ?row.owningLayerId}.toList(),
    );
  }

  set _rangeMoveSelection(TimelineFrameRangeSelection? span) {
    if (!_rangeMoveOnTrackAxis) {
      _session.frameRangeSelection.value = span;
      return;
    }
    if (span == null) {
      _session.trackFrameRangeSelection.value = null;
      return;
    }
    // The axis's own facts ride from the drag-start capture: the anchor
    // names its OWN track (the select path's law — re-keying to
    // [selectedTrackId] here hid the band for the whole drag on any other
    // track and left the landed selection keyed to the wrong one), and a
    // non-layer row in a mixed span is not something the layer-stated span
    // can re-derive.
    final before = _rangeMoveTrackSelectionBefore;
    _session.trackFrameRangeSelection.value = TrackFrameRangeSelection(
      trackId: before?.trackId ?? _session.selectedTrackId,
      anchorRow: LayerRowAddress(span.layerId),
      rows: [
        for (final id in span.spanLayerIds) LayerRowAddress(id),
        if (before != null)
          for (final row in before.rows)
            if (row is! LayerRowAddress) row,
      ],
      startFrame: span.startIndex,
      endFrameExclusive: span.endIndexExclusive,
    );
  }

  /// The display→commit offset the move applies to [layerId]'s span. ZERO
  /// on the track axis: the span is already stated in commit keys, and
  /// translating it again would address another cut's frames.
  int _rangeMoveCommitOffset(LayerId layerId, int spanStart) =>
      _rangeMoveOnTrackAxis
      ? 0
      : _session._commitBlockStart(layerId, spanStart) - spanStart;

  Layer? _rangeMoveSourceBefore;

  /// The move's subject span as it stood at drag start, stated in the axis
  /// its sources commit in (see [_rangeMoveSelection]).
  TimelineFrameRangeSelection? _rangeMoveSelectionBefore;

  /// The TRACK-axis selection as it stood at drag start — the setter reads
  /// the track id and the non-layer rows from here, because the machine's
  /// layer-stated span cannot carry them and the LIVE value is the very
  /// thing the setter is overwriting.
  TrackFrameRangeSelection? _rangeMoveTrackSelectionBefore;

  int? _rangeMoveGroupStart;

  DrawingBlockMovePlan? _rangeMovePlan;

  /// Cross-layer selections (UI-R18 #1): every spanned layer's drag-start
  /// snapshot in COMMIT form (+ the display→commit index offset for
  /// track-SE rows); the move slides them together along the FRAME axis
  /// (row changes stay single-layer anim-only — the kind guard would make
  /// partial rect drops ambiguous).
  List<({Layer commit, int offset})>? _rangeMoveMultiSources;

  List<DrawingBlockMovePlan>? _rangeMoveMultiPlans;

  /// The in-flight MULTI-ROW range move (UI-R23 #9): a multi-layer drawing
  /// selection dragged onto a different row shifts every selected row
  /// rigidly. Set only while a valid rigid landing is previewed; an illegal
  /// step leaves the last valid plan in place (UI-R23 #10).
  MultiRowRangeMovePlan? _rangeMoveMultiRowPlan;

  /// R27 #8: the row the move drag GRABBED — the hop origin. The
  /// selection's anchor row is a different thing (selecting upward makes
  /// them differ), and using it made "this block lands on that row" come
  /// out shifted by however far the two were apart.
  LayerId? _rangeMoveGrabLayerId;

  /// KEY sources riding the range move (P3b-2, #2 second half): the
  /// camera row's keyframe snapshot and the spanned instruction rows —
  /// their keys shift with the same delta the blocks slide.
  Map<int, CameraPose>? _rangeMoveCameraBefore;

  LayerId? _rangeMoveCameraLayerId;

  List<Layer>? _rangeMoveInstructionSources;

  Map<int, CameraPose>? _rangeMoveCameraShifted;

  Map<LayerId, Map<int, InstructionEvent>>? _rangeMoveInstructionShifted;

  /// A ROW-CHANGE drop in flight within the SE / camera sections (P3b-4,
  /// 같은 섹션 행이동): the planned GLOBAL layer pair for an SE→SE drop,
  /// or the instruction-map pair for instruction→instruction.
  ({
    LayerId sourceId,
    LayerId targetId,
    Layer sourceBefore,
    Layer sourceAfter,
    Layer targetBefore,
    Layer targetAfter,
  })?
  _rangeMoveSeRowChange;

  /// The SE rows riding a MULTI-ROW rigid move (R26 #2): a span that also
  /// covers a track-SE row moves that row's blocks by the same row delta
  /// within the SE lattice — "if a block is movable, it moves no matter
  /// how many rows you select" applies to SE rows too.
  List<SeRowMovePair>? _rangeMoveMultiSeRowChanges;

  ({
    LayerId sourceId,
    LayerId targetId,
    Map<int, InstructionEvent> sourceAfter,
    Map<int, InstructionEvent> targetAfter,
  })?
  _rangeMoveInstructionRowChange;

  /// Starts moving the CURRENT frame-range selection; returns false when
  /// there is none (or its row stands down).
  ///
  /// Cross-layer selections (UI-R18 #1) move too: every spanned layer's
  /// selected blocks slide together along the frame axis, one composite
  /// undo on release. Row-changing drops stay single-layer (the kind
  /// guard would make partial rect drops ambiguous).
  /// [grabLayerId] = the row the pointer went down on (R27 #8); null falls
  /// back to the selection's anchor row (the callers that have no pointer,
  /// e.g. tests of a single-row move).
  /// A range-move drag on the TRACK axis — the storyboard's S rows.
  ///
  /// The same machine: it plans on its sources' COMMIT forms, and a
  /// track-SE row's commit form is the global layer whichever rail asked.
  /// What is different is only the axis the span is stated in, so the
  /// sources take offset 0 (the range is ALREADY in their keys) where a
  /// cut-local drag would carry the cut's start.
  ///
  /// Track rows are not movable subjects here: a cut row's blocks are cuts
  /// and sliding those is the cut drag's job, which the storyboard's own V
  /// row already mounts.
  bool beginTrackRangeMoveDrag([LayerId? grabLayerId]) {
    _rangeMoveOnTrackAxis = true;
    final live = _session.trackFrameRangeSelection.value;
    if (live == null) {
      return false;
    }
    _rangeMoveTrackSelectionBefore = live;
    final sources = <({Layer commit, int offset})>[];
    // C1 (2026-08-17): the TRANSITION row is a movable subject on THIS
    // axis — its spans live global, and this rail is their one author
    // (the cut timeline's clone stays the read-only projection). It rides
    // the move machine's existing INSTRUCTION-source arm, exactly as the
    // cut-local instruction rows do in [beginFrameRangeMoveDrag].
    final instructionSources = <Layer>[];
    // 🚨C3-lane-move: keyed by the row's OWNING layer, not by the row's
    // TYPE. A lane row is one of its layer's rows — skipping it here is
    // what made a band anchored on an fx row refuse to move and fall
    // through to a silent re-select. The `seen` set is the other half: a
    // layer row and its own lane rows are several rows of ONE layer, and
    // sourcing that layer twice would plan its slide twice.
    final seen = <LayerId>{};
    for (final row in live.spanRows) {
      final rowLayerId = row.owningLayerId;
      if (rowLayerId == null || !seen.add(rowLayerId)) {
        continue;
      }
      final transition = _session._transitions
          .trackTransitionOwner(rowLayerId)
          ?.transitionLayer;
      if (transition != null) {
        final hasSpan = transition.instructions.keys.any(
          (key) => key >= live.startFrame && key < live.endFrameExclusive,
        );
        if (hasSpan) {
          instructionSources.add(transition);
        }
        continue;
      }
      final commit = _session.trackSeGlobalLayerById(rowLayerId);
      if (commit == null) {
        continue;
      }
      // Only rows that actually carry a WHOLE block inside the range move
      // — the cross-layer slide's rule, unchanged.
      final hasBlock = drawingBlocks(commit.timeline).any(
        (block) =>
            !block.entry.ghost &&
            block.startIndex >= live.startFrame &&
            block.endIndexExclusive <= live.endFrameExclusive,
      );
      if (hasBlock) {
        sources.add((commit: commit, offset: 0));
      }
    }
    if (sources.isEmpty && instructionSources.isEmpty) {
      return false;
    }
    _rangeMoveGrabLayerId = grabLayerId;
    _rangeMoveSourceBefore = null;
    _rangeMoveGroupStart = null;
    _rangeMovePlan = null;
    _rangeMoveMultiPlans = null;
    _rangeMoveMultiRowPlan = null;
    _rangeMoveMultiSeRowChanges = null;
    _rangeMoveCameraBefore = null;
    _rangeMoveCameraLayerId = null;
    _rangeMoveInstructionSources = instructionSources.isEmpty
        ? null
        : instructionSources;
    _rangeMoveCameraShifted = null;
    _rangeMoveInstructionShifted = null;
    _rangeMoveSeRowChange = null;
    _rangeMoveInstructionRowChange = null;
    _rangeMoveMultiSources = sources;
    _rangeMoveSelectionBefore = _rangeMoveSelection;
    return _rangeMoveSelectionBefore != null;
  }

  bool beginFrameRangeMoveDrag([LayerId? grabLayerId]) {
    // The axis is decided HERE and nowhere else: every begin states it, so
    // no path can inherit the previous drag's answer.
    _rangeMoveOnTrackAxis = false;
    _rangeMoveTrackSelectionBefore = null;
    final selection = _rangeMoveSelection;
    if (selection == null ||
        !_session._rangeSelections.rangeSelectionEligible(selection.layerId)) {
      return false;
    }
    _rangeMoveGrabLayerId = grabLayerId ?? selection.layerId;
    _rangeMoveMultiSources = null;
    _rangeMoveMultiPlans = null;
    _rangeMoveMultiRowPlan = null;
    _rangeMoveMultiSeRowChanges = null;
    _rangeMoveCameraBefore = null;
    _rangeMoveCameraLayerId = null;
    _rangeMoveInstructionSources = null;
    _rangeMoveCameraShifted = null;
    _rangeMoveInstructionShifted = null;
    _rangeMoveSeRowChange = null;
    _rangeMoveInstructionRowChange = null;
    // KEY sources (P3b-2, #2 second half): camera keys, instruction
    // spans AND the layers' own transform-track keys (P3c, #13) inside
    // the selection move with the blocks — same delta, one rigid group.
    // SYNCED attach mirrors stay PASSENGERS (P3b-1): the base's slide
    // carries them by derivation.
    Map<int, CameraPose>? cameraBefore;
    LayerId? cameraLayerId;
    final instructionSources = <Layer>[];
    bool anyKeyIn(Iterable<int> keys) => keys.any(
      (key) => key >= selection.startIndex && key < selection.endIndexExclusive,
    );
    for (final id in selection.spanLayerIds) {
      final layer = _session._layerById(id);
      if (layer == null) {
        continue;
      }
      if (layer.kind == LayerKind.camera) {
        final keyframes = _session.activeCutOrNull?.camera.keyframes;
        if (keyframes != null && anyKeyIn(keyframes.keys)) {
          cameraBefore = Map<int, CameraPose>.of(keyframes);
          cameraLayerId = id;
        }
        continue;
      }
      if (layer.kind == LayerKind.instruction &&
          anyKeyIn(layer.instructions.keys)) {
        instructionSources.add(layer);
      }
      // UI-R23 #3: a frame-range selection NO LONGER carries the layer's
      // own transform keys — frame selection ⊥ transform keys. The
      // transform lanes own their keys through their own lane-scoped
      // selection domain; camera keys and instruction spans (a camera /
      // instruction row's OWN content) still ride below.
    }
    // Multi-layer spans, SE rows and KEY sources route through the
    // frame-axis slide (UI-R18 #1): per-layer plans on the COMMIT forms;
    // row-change drops stay the single-anim path below.
    if (selection.spanLayerIds.length > 1 ||
        _session.isTrackSeLayerId(selection.layerId) ||
        cameraBefore != null ||
        instructionSources.isNotEmpty) {
      final sources = <({Layer commit, int offset})>[];
      for (final id in selection.spanLayerIds) {
        // SYNCED attach rows never source a move (their commit form owns
        // no timing) — they stay PASSENGERS, carried by the base's slide
        // through derivation. Id-gated: the synced-block UI stopped
        // marking mirror entries ghost, so the block filter below no
        // longer excludes them. SINGLE-CEL (image) rows stand down too:
        // their covering block is pinned by the write normalization.
        if (_session._isSyncedAttachedLayerId(id) ||
            _session._isSingleCelLayerId(id)) {
          continue;
        }
        final display = _session._rangeLayerById(id);
        final commit = _session._commitLayerById(id);
        if (display == null || commit == null) {
          continue;
        }
        final hasBlock = drawingBlocks(display.timeline).any(
          (block) =>
              !block.entry.ghost &&
              block.startIndex >= selection.startIndex &&
              block.endIndexExclusive <= selection.endIndexExclusive,
        );
        if (hasBlock) {
          sources.add((
            commit: commit,
            offset: _rangeMoveCommitOffset(id, selection.startIndex),
          ));
        }
      }
      if (sources.isEmpty &&
          cameraBefore == null &&
          instructionSources.isEmpty) {
        // An all-synced span dies here — say why at the cursor, like the
        // single-row path does.
        _session._noticeSyncedAttachRefusal(selection.layerId);
        return false;
      }
      _rangeMoveMultiSources = sources;
      _rangeMoveCameraBefore = cameraBefore;
      _rangeMoveCameraLayerId = cameraLayerId;
      _rangeMoveInstructionSources = instructionSources.isEmpty
          ? null
          : instructionSources;
      _rangeMoveSelectionBefore = selection;
      return true;
    }
    // A SYNCED attach row's blocks are borrowed exposures — the move
    // refuses with the "edit the owner" pill (the synced-block UI made
    // the row look grabbable; before it, the all-ghost timeline fell out
    // of the block scan below on its own). A SINGLE-CEL (image) row's
    // covering block is immovable — the normalization would revert it.
    if (_session._isSyncedAttachedLayerId(selection.layerId)) {
      _session._noticeSyncedAttachRefusal(selection.layerId);
      return false;
    }
    if (_session._isSingleCelLayerId(selection.layerId)) {
      return false;
    }
    final layer = _session._layerById(selection.layerId);
    if (layer == null) {
      return false;
    }
    int? groupStart;
    for (final block in drawingBlocks(layer.timeline)) {
      if (block.entry.ghost) {
        continue;
      }
      if (block.startIndex >= selection.startIndex &&
          block.endIndexExclusive <= selection.endIndexExclusive) {
        groupStart = block.startIndex;
        break;
      }
    }
    if (groupStart == null) {
      return false; // Nothing but empty cells selected — nothing to move.
    }
    _rangeMoveSourceBefore = layer;
    _rangeMoveSelectionBefore = selection;
    _rangeMoveGroupStart = groupStart;
    return true;
  }

  /// A ROW-CHANGE drag step (P3b-4): returns true when it OWNED the step
  /// — either a planned SE→SE / instruction→instruction landing (preview
  /// published) or an owned-but-illegal hover (preview cleared). False
  /// falls through to the plain frame-axis slide.
  bool _updateRangeRowChangeDrag(
    TimelineFrameRangeSelection selection,
    int frameDelta,
    LayerId targetLayerId,
  ) {
    void keepLastValid() {
      // UI-R23 #10: a blocked / incompatible landing KEEPS the last valid
      // preview and outline — the move "stops at the last legal spot" and
      // resumes when a legal row returns, uniform across every source kind
      // (the R22-B snap-back-to-origin is retired). Nothing to mutate: the
      // stored last-valid plan and the live preview stand.
    }

    void followOutline() {
      _rangeMoveMultiPlans = null;
      _rangeMoveCameraShifted = null;
      _rangeMoveInstructionShifted = null;
      _session._camera._cameraKeysDragPreview = null;
      final newStart = selection.startIndex + frameDelta;
      if (newStart >= 0) {
        _rangeMoveSelection = TimelineFrameRangeSelection(
          layerId: targetLayerId,
          startIndex: newStart,
          endIndexExclusive: selection.endIndexExclusive + frameDelta,
        );
      }
    }

    final sourceIsSe = _session.isTrackSeLayerId(selection.layerId);
    if (sourceIsSe && _session.isTrackSeLayerId(targetLayerId)) {
      final sourceGlobal = _session.trackSeGlobalLayerById(selection.layerId);
      final targetGlobal = _session.trackSeGlobalLayerById(targetLayerId);
      if (sourceGlobal == null || targetGlobal == null) {
        keepLastValid();
        return true;
      }
      final offset = _rangeMoveCommitOffset(
        selection.layerId,
        selection.startIndex,
      );
      final plan = planSeRangeRowMove(
        source: sourceGlobal,
        target: targetGlobal,
        rangeStartIndex: selection.startIndex + offset,
        rangeEndIndexExclusive: selection.endIndexExclusive + offset,
        frameDelta: frameDelta,
      );
      if (plan == null) {
        keepLastValid();
        return true;
      }
      _rangeMoveSeRowChange = (
        sourceId: selection.layerId,
        targetId: targetLayerId,
        sourceBefore: sourceGlobal,
        sourceAfter: plan.sourceAfter,
        targetBefore: targetGlobal,
        targetAfter: plan.targetAfter,
      );
      _session.dragPreview.value = BlockMoveDragPreview(
        previewLayers: {
          selection.layerId: _session.trackSeWindow.displayLayer(
            plan.sourceAfter,
          ),
          targetLayerId: _session.trackSeWindow.displayLayer(plan.targetAfter),
        },
        // C2: the plans ARE the global forms — the storyboard strips
        // follow the cross-row drop live through the same one gate.
        previewGlobalLayers: {
          selection.layerId: plan.sourceAfter,
          targetLayerId: plan.targetAfter,
        },
      );
      followOutline();
      return true;
    }
    final sourceLayer = _session._layerById(selection.layerId);
    final targetLayer = _session._layerById(targetLayerId);
    final sourceIsInstruction = sourceLayer?.kind == LayerKind.instruction;
    if (sourceIsInstruction && targetLayer?.kind == LayerKind.instruction) {
      final plan = planInstructionRangeRowMove(
        source: sourceLayer!.instructions,
        target: targetLayer!.instructions,
        rangeStartIndex: selection.startIndex,
        rangeEndIndexExclusive: selection.endIndexExclusive,
        frameDelta: frameDelta,
      );
      if (plan == null) {
        keepLastValid();
        return true;
      }
      _rangeMoveInstructionRowChange = (
        sourceId: selection.layerId,
        targetId: targetLayerId,
        sourceAfter: plan.sourceAfter,
        targetAfter: plan.targetAfter,
      );
      _session.dragPreview.value = BlockMoveDragPreview(
        previewLayers: {
          selection.layerId: sourceLayer.copyWith(
            instructions: plan.sourceAfter,
          ),
          targetLayerId: targetLayer.copyWith(instructions: plan.targetAfter),
        },
      );
      followOutline();
      return true;
    }
    // SE / instruction sources hovering an INCOMPATIBLE row: the drop is
    // illegal — the last valid preview HOLDS until a legal row returns
    // (UI-R23 #10, the cross-section discipline). Every other source falls
    // through to the plain slide (the camera key drag keeps ignoring row
    // wander, P3b-2).
    if (sourceIsSe || sourceIsInstruction) {
      keepLastValid();
      return true;
    }
    return false;
  }

  /// The display-ordered lattice of move-eligible DRAWING rows — the rows a
  /// multi-row rigid shift can travel across (all one section).
  List<Layer> _blockMoveLattice() {
    final ordered = sectionedLayerOrder(
      _session.activeCutOrNull?.layers ?? const [],
    );
    return [
      for (final layer in ordered)
        if (_session._blockMoveEligible(layer.id)) layer,
    ];
  }

  /// R27 #8: EVERY row the timeline shows, in the order it shows them —
  /// drawing rows, SE rows (track clones included) and the camera /
  /// instruction rows alike.
  ///
  /// A range move's row hop is a fact about what the POINTER did on
  /// screen; deriving it from one content lattice (the old behaviour)
  /// made the hop uncomputable whenever the drag was anchored on a row
  /// that lattice does not contain — a camera or instruction row — and
  /// the whole multi-row move silently died even though the selected
  /// blocks had a perfectly legal home. Each moving row translates this
  /// display hop into its own lattice below.
  List<Layer> _rangeRowOrder() => sectionedLayerOrder(_session.layers);

  /// The display-row hop from [anchorId] to [targetId]; null when either
  /// row is not on screen.
  int? _displayRowDelta(List<Layer> rows, LayerId anchorId, LayerId targetId) {
    final anchorIndex = rows.indexWhere((layer) => layer.id == anchorId);
    final targetIndex = rows.indexWhere((layer) => layer.id == targetId);
    if (anchorIndex == -1 || targetIndex == -1) {
      return null;
    }
    return targetIndex - anchorIndex;
  }

  /// The one lattice hop every content-bearing row in [ids] agrees on.
  /// `blocked` when a row cannot land, or when two rows would need
  /// different hops (the rigid move is all-or-nothing); a null `delta`
  /// with `blocked: false` means nothing in this lattice is moving.
  ({bool blocked, int? delta}) _agreedLatticeHop({
    required List<Layer> rows,
    required List<Layer> lattice,
    required List<LayerId> ids,
    required int displayDelta,
  }) {
    int? shared;
    for (final id in ids) {
      final hop = _latticeHopFor(
        rows: rows,
        lattice: lattice,
        layerId: id,
        displayDelta: displayDelta,
      );
      if (hop == null || (shared != null && shared != hop)) {
        return (blocked: true, delta: null);
      }
      shared = hop;
    }
    return (blocked: false, delta: shared);
  }

  /// A MULTI-ROW range move step (UI-R23 #9): a multi-layer DRAWING
  /// selection dragged onto a different row shifts every selected row
  /// rigidly by the same row + frame delta. Returns true when it OWNS the
  /// step — a valid rigid landing (preview published) or an illegal one
  /// that HOLDS the last valid preview (UI-R23 #10). Returns false (falls
  /// through to the plain frame slide) for same-row steps or spans whose
  /// NON-drawing rows carry content in range (keys ride the frame axis
  /// only). Empty rows of any kind never block (UI-R24 #3: only the
  /// frames inside the selection move).
  /// The instruction riders' commit commands — ONE two-armed projection
  /// for BOTH the plain-slide and the rigid commit branches (C1/C④). The
  /// TRANSITION row's shifted spans land through the row's own
  /// track-owned writer (the edge drags' command): it has no cut to be
  /// addressed by, so the cut gate must never swallow it. Cut-local
  /// instruction rows keep the cut-addressed command they always had.
  List<Command> _instructionShiftCommands(
    Map<LayerId, Map<int, InstructionEvent>> instructionShifted,
    Cut? cut,
  ) => [
    for (final entry in instructionShifted.entries)
      if (_session._transitions.trackTransitionOwner(entry.key)
          case final owner?)
        UpdateTrackTransitionLayerCommand(
          repository: _session._repository,
          trackId: owner.id,
          before: owner.transitionLayer,
          after: owner.transitionLayer.copyWith(
            instructions: SplayTreeMap<int, InstructionEvent>.from(entry.value),
          ),
          debugLabel: 'Move transition',
        )
      else if (cut != null)
        UpdateLayerInstructionsCommand(
          repository: _session._repository,
          cutId: cut.id,
          layerId: entry.key,
          instructions: entry.value,
          description: 'Move instruction keys',
        ),
  ];

  bool _updateMultiRowRangeMove(
    TimelineFrameRangeSelection selection,
    int frameDelta,
    LayerId targetLayerId,
  ) {
    if (selection.spanLayerIds.length <= 1) {
      return false;
    }
    bool anyKeyIn(Iterable<int> keys) => keys.any(
      (key) => key >= selection.startIndex && key < selection.endIndexExclusive,
    );
    bool carriesBlockInRange(Layer layer) => drawingBlocks(layer.timeline).any(
      (block) =>
          !block.entry.ghost &&
          block.startIndex < selection.endIndexExclusive &&
          block.endIndexExclusive > selection.startIndex,
    );
    // R27 #8: sort the span by what each row can DO with the hop. Drawing
    // rows and track-SE rows travel across their own lattice; the camera
    // and instruction rows have no row axis to travel, so their keys ride
    // the FRAME delta and stay put. Empty rows contribute nothing at all.
    //
    // The old code made a key-carrying camera/instruction row veto the
    // whole move ("keys ride the frame axis only" → `return false`). That
    // is the "임시처방" the user called out: selecting a CAM row next to a
    // sound block made the sound unmovable, even though its landing row
    // was empty. A row that cannot change rows now simply doesn't.
    final drawingSourceIds = <LayerId>[];
    final sePassengerIds = <LayerId>[];
    var cameraRides = false;
    for (final id in selection.spanLayerIds) {
      if (_session._blockMoveEligible(id)) {
        final layer = _session._layerById(id);
        if (layer != null && carriesBlockInRange(layer)) {
          drawingSourceIds.add(id);
        }
        continue;
      }
      if (_session.isTrackSeLayerId(id)) {
        final display = _session._rangeLayerById(id);
        if (display != null && carriesBlockInRange(display)) {
          sePassengerIds.add(id);
        }
        continue;
      }
      final layer = _session._layerById(id);
      if (layer == null) {
        continue;
      }
      if (layer.kind == LayerKind.camera) {
        final keyframes = _session.activeCutOrNull?.camera.keyframes;
        if (keyframes != null && anyKeyIn(keyframes.keys)) {
          cameraRides = true;
        }
        continue;
      }
      // Instruction rows (the transition included, via its display clone)
      // are frame-axis riders — WHO rides was decided at begin
      // (_rangeMoveInstructionSources, the same list the plain slide
      // consumes). Re-deriving them here is the copy that silently
      // dropped the TRANSITION on rigid steps (C④): its clone's kind
      // matched no arm, so the spans snapped home the moment the pointer
      // crossed a row.
      if (layer.kind == LayerKind.instruction ||
          layer.kind == LayerKind.transition) {
        continue;
      }
      // A row that is neither move-eligible nor a known frame-axis rider
      // (a SYNCED attach row) still routes the step to the plain slide
      // when it carries content: its timing belongs to its base.
      if (carriesBlockInRange(layer)) {
        return false;
      }
    }
    final lattice = _blockMoveLattice();
    final seLattice = _session.activeTrack.seLayers;
    final rows = _rangeRowOrder();
    final displayDelta = _displayRowDelta(
      rows,
      _rangeMoveGrabLayerId ?? selection.layerId,
      targetLayerId,
    );
    if (displayDelta == null) {
      // The pointer left the rows entirely. When something in the span
      // CAN travel, HOLD the last valid preview (UI-R23 #10); otherwise
      // the plain slide owns the step.
      return drawingSourceIds.isNotEmpty || sePassengerIds.isNotEmpty;
    }
    if (displayDelta == 0) {
      // No row change this step — the plain frame slide owns it.
      return false;
    }
    final drawingHop = _agreedLatticeHop(
      rows: rows,
      lattice: lattice,
      ids: drawingSourceIds,
      displayDelta: displayDelta,
    );
    final seHop = _agreedLatticeHop(
      rows: rows,
      lattice: seLattice,
      ids: sePassengerIds,
      displayDelta: displayDelta,
    );
    if (drawingHop.blocked || seHop.blocked) {
      // A content-bearing row has nowhere to land (or two rows would need
      // different hops): all-or-nothing, HOLD the last valid preview.
      return true;
    }
    // A hop of 0 alongside a non-zero one would tear the rigid move apart
    // — the slide owns those steps instead.
    final rowDelta = drawingHop.delta ?? seHop.delta;
    if (rowDelta == null || rowDelta == 0) {
      return false;
    }
    if ((drawingHop.delta ?? rowDelta) != rowDelta ||
        (seHop.delta ?? rowDelta) != rowDelta) {
      return false;
    }
    MultiRowRangeMovePlan? plan;
    if (drawingSourceIds.isNotEmpty) {
      plan = planMultiRowRangeMove(
        orderedLayers: lattice,
        sourceLayerIds: selection.spanLayerIds,
        rangeStartIndex: selection.startIndex,
        rangeEndIndexExclusive: selection.endIndexExclusive,
        frameDelta: frameDelta,
        rowDelta: rowDelta,
      );
      if (plan == null) {
        // An illegal rigid landing HOLDS the last valid preview (R23 #10).
        return true;
      }
    }
    final sePlans = sePassengerIds.isEmpty
        ? const <SeRowMovePair>[]
        : _planMultiRowSePassengers(
            seSourceIds: sePassengerIds,
            seLattice: seLattice,
            selection: selection,
            frameDelta: frameDelta,
            rowDelta: rowDelta,
          );
    if (sePlans == null) {
      return true; // An SE passenger cannot land — the whole move voids.
    }
    if (plan == null && sePlans.isEmpty) {
      return false; // Nothing to carry — the plain slide owns the step.
    }
    // R27 #8: the frame-axis riders shift with the same frame delta. A
    // rider that cannot shift voids the move like any other passenger.
    // A PURE row hop (frameDelta 0) moves no frames, so the riders simply
    // hold — the shifters answer null for "nothing to shift" (the R28 #5
    // conflation) and reading that as "blocked" killed every vertical
    // step of a mixed span.
    Map<int, CameraPose>? cameraShifted;
    if (cameraRides && frameDelta != 0) {
      cameraShifted = shiftCameraKeysInRange(
        keyframes: _session.activeCutOrNull?.camera.keyframes ?? const {},
        rangeStartIndex: selection.startIndex,
        rangeEndIndexExclusive: selection.endIndexExclusive,
        frameDelta: frameDelta,
      );
      if (cameraShifted == null) {
        return true;
      }
    }
    final instructionShifted = <LayerId, Map<int, InstructionEvent>>{};
    if (frameDelta != 0) {
      for (final layer in _rangeMoveInstructionSources ?? const <Layer>[]) {
        final shifted = shiftInstructionEventsInRange(
          events: layer.instructions,
          rangeStartIndex: selection.startIndex,
          rangeEndIndexExclusive: selection.endIndexExclusive,
          frameDelta: frameDelta,
        );
        if (shifted == null) {
          return true;
        }
        instructionShifted[layer.id] = shifted;
      }
    }
    // A valid rigid landing supersedes the slide / row-change plans.
    _rangeMoveMultiRowPlan = plan;
    _rangeMoveMultiSeRowChanges = sePlans.isEmpty ? null : sePlans;
    _rangeMoveMultiPlans = null;
    _rangeMoveSeRowChange = null;
    _rangeMoveInstructionRowChange = null;
    _rangeMoveCameraShifted = cameraShifted;
    _rangeMoveInstructionShifted = instructionShifted.isEmpty
        ? null
        : instructionShifted;
    _session._camera._cameraKeysDragPreview = cameraShifted;
    _session.dragPreview.value = BlockMoveDragPreview(
      previewLayers: {
        if (plan != null)
          for (final entry in plan.layersAfter.entries)
            entry.key: rederiveRunBehaviors(
              entry.value,
              cutFrameCount: _session._activeCutFrameCount,
            ),
        for (final se in sePlans) ...{
          se.sourceId: _session.trackSeWindow.displayLayer(se.sourceAfter),
          se.targetId: _session.trackSeWindow.displayLayer(se.targetAfter),
        },
        // R27 #8: the frame-axis riders preview their shifted spans in
        // place (the cells row renders straight off layer.instructions).
        // ⛔The TRANSITION stays OFF this map: on the ACTIVE track
        // _layerById finds its display clone under the same id, and a
        // global-keyed entry here would leak into the cut timeline's
        // read-only projection. It previews on its own channel below.
        for (final entry in instructionShifted.entries)
          if (_session._transitions.trackTransitionOwner(entry.key) == null &&
              _session._layerById(entry.key) != null)
            entry.key: _session
                ._layerById(entry.key)!
                .copyWith(instructions: entry.value),
      },
      // C2: the SE passengers' global forms, for the storyboard strips.
      previewGlobalLayers: {
        for (final se in sePlans) ...{
          se.sourceId: se.sourceAfter,
          se.targetId: se.targetAfter,
        },
      },
      cameraCutId: cameraShifted == null ? null : _session.activeCutOrNull?.id,
      cameraKeyframes: cameraShifted,
      // A FRESH CLONE per step (the P3b-2 contract) — the gate compares
      // identities, and the repository instance trips nothing (B4-①: the
      // multi-row rigid path was the one place still handing it over raw,
      // so a union drag spanning rows froze the camera's markers).
      cameraMarkerLayer:
          cameraShifted == null || _rangeMoveCameraLayerId == null
          ? null
          : _session._layerById(_rangeMoveCameraLayerId!)?.copyWith(),
    );
    // C1: the transition channel follows every published step — a riding
    // transition previews its shifted spans here (C④: it used to be
    // absent from this path's shift map, so the write CLEARED the channel
    // and the spans snapped home on every rigid step).
    _publishRangeMoveTransitionPreview(instructionShifted);
    // The outline rides the rigid shift to the target rows (rows that
    // carried nothing — off the lattice or shifted off it — drop out of
    // the outline; only the moved frames' landings read selected).
    final indexById = {
      for (var i = 0; i < lattice.length; i += 1) lattice[i].id: i,
    };
    final seIndexById = {
      for (var i = 0; i < seLattice.length; i += 1) seLattice[i].id: i,
    };
    final landedLayerIds = [
      for (final id in selection.spanLayerIds)
        if (indexById[id] case final index?
            when index + rowDelta >= 0 && index + rowDelta < lattice.length)
          lattice[index + rowDelta].id
        else if (seIndexById[id] case final index?
            when index + rowDelta >= 0 && index + rowDelta < seLattice.length)
          seLattice[index + rowDelta].id,
    ];
    final newStart = selection.startIndex + frameDelta;
    if (newStart >= 0) {
      _rangeMoveSelection = TimelineFrameRangeSelection(
        layerId: targetLayerId,
        startIndex: newStart,
        endIndexExclusive: selection.endIndexExclusive + frameDelta,
        layerIds: landedLayerIds,
      );
    }
    return true;
  }

  /// Plans the SE passengers of a multi-row rigid move (R26 #2): every
  /// track-SE row in [seSourceIds] shifts [rowDelta] rows inside the SE
  /// lattice, carrying its selected blocks (and their audio clips, which
  /// anchor to the cels). Null when ANY passenger cannot land — the whole
  /// move voids, the multi-row all-or-nothing rule.
  List<SeRowMovePair>? _planMultiRowSePassengers({
    required List<LayerId> seSourceIds,
    required List<Layer> seLattice,
    required TimelineFrameRangeSelection selection,
    required int frameDelta,
    required int rowDelta,
  }) {
    final sourceIndexes = <int>{
      for (final id in seSourceIds) seLattice.indexWhere((l) => l.id == id),
    };
    if (sourceIndexes.contains(-1)) {
      return null;
    }
    final plans = <SeRowMovePair>[];
    for (final sourceId in seSourceIds) {
      final sourceIndex = seLattice.indexWhere((l) => l.id == sourceId);
      final targetIndex = sourceIndex + rowDelta;
      if (targetIndex < 0 || targetIndex >= seLattice.length) {
        return null; // Off the SE lattice.
      }
      if (sourceIndexes.contains(targetIndex)) {
        return null; // A chained/swapped landing — voided rather than
        // ordered (two SE rows never shift the same delta legally).
      }
      final source = seLattice[sourceIndex];
      final target = seLattice[targetIndex];
      final offset = _rangeMoveCommitOffset(sourceId, selection.startIndex);
      final plan = planSeRangeRowMove(
        source: source,
        target: target,
        rangeStartIndex: selection.startIndex + offset,
        rangeEndIndexExclusive: selection.endIndexExclusive + offset,
        frameDelta: frameDelta,
      );
      if (plan == null) {
        return null;
      }
      plans.add((
        sourceId: sourceId,
        targetId: target.id,
        sourceBefore: source,
        sourceAfter: plan.sourceAfter,
        targetBefore: target,
        targetAfter: plan.targetAfter,
      ));
    }
    return plans;
  }

  /// R28 #5: returns the drag preview to the block's REAL position.
  ///
  /// `planDrawingRangeMove` answers null for two different questions —
  /// "impossible" and "no movement" (frameDelta 0, or a landing back on
  /// the group's own start). The drag step read every null as blocked and
  /// so HELD the last valid preview (UI-R23 #10, which is right for a
  /// blocked landing). A drag that went right and came back therefore
  /// froze one step out and refused to reach home: "더 이상 왼쪽으로 이동이
  /// 안먹혀버리고 그 자리에서 멈춰버린다". Zero delta is not a blocked
  /// landing — it is the origin, and the preview must show it.
  void _resetRangeMovePreviewToOrigin() {
    _rangeMovePlan = null;
    _rangeMoveMultiPlans = null;
    _rangeMoveSeRowChange = null;
    _rangeMoveInstructionRowChange = null;
    _rangeMoveMultiRowPlan = null;
    _rangeMoveMultiSeRowChanges = null;
    _rangeMoveCameraShifted = null;
    _rangeMoveInstructionShifted = null;
    _session._camera._cameraKeysDragPreview = null;
    _session.dragPreview.value = null;
    _session.transitionEdgeDragPreview.value = null;
    final selection = _rangeMoveSelectionBefore;
    if (selection != null) {
      _rangeMoveSelection = selection;
    }
  }

  /// C1 (2026-08-17): the in-flight form of a range-moved TRANSITION row,
  /// published on [_session.transitionEdgeDragPreview] — the channel the row's edge
  /// drags already preview on and the storyboard's transition strip
  /// already renders. One preview channel per row family: the move joins
  /// the edge drag instead of growing a second gate.
  ///
  /// A step whose shift map carries no transition entry CLEARS the channel
  /// (a null write on an already-null notifier is a silent no-op), so an
  /// ordinary cell move can never leave a stale transition form standing.
  void _publishRangeMoveTransitionPreview(
    Map<LayerId, Map<int, InstructionEvent>> instructionShifted,
  ) {
    Layer? preview;
    for (final entry in instructionShifted.entries) {
      final owner = _session._transitions.trackTransitionOwner(entry.key);
      if (owner != null) {
        preview = owner.transitionLayer.copyWith(
          instructions: SplayTreeMap<int, InstructionEvent>.from(entry.value),
        );
      }
    }
    _session.transitionEdgeDragPreview.value = preview;
  }

  /// A range-move drag step: live preview on [_session.dragPreview] (repository
  /// untouched), the selection outline riding the previewed landing.
  void updateFrameRangeMoveDrag({
    required int frameDelta,
    LayerId? targetLayerId,
  }) {
    final selection = _rangeMoveSelectionBefore;
    final multiSources = _rangeMoveMultiSources;
    // R28 #5: back at the start = the origin, not a refusal. A row change
    // still owns the step (a delta-0 drop onto a sibling row is a real
    // move), so only same-row zero deltas reset.
    if (selection != null &&
        frameDelta == 0 &&
        (targetLayerId == null ||
            targetLayerId == selection.layerId ||
            targetLayerId == _rangeMoveGrabLayerId)) {
      _resetRangeMovePreviewToOrigin();
      return;
    }
    if (selection != null && multiSources != null) {
      // ROW-CHANGE drops within the SE / camera sections (P3b-4, 같은
      // 섹션 행이동): a single-row track-SE selection may land on a
      // sibling SE row, an instruction selection on a sibling
      // instruction row — the handler owns the step then (an incompatible
      // hover HOLDS the last valid landing, UI-R23 #10).
      if (targetLayerId != null &&
          targetLayerId != selection.layerId &&
          selection.spanLayerIds.length == 1 &&
          _updateRangeRowChangeDrag(selection, frameDelta, targetLayerId)) {
        return;
      }
      // MULTI-ROW rigid move (UI-R23 #9): a multi-layer drawing selection
      // dragged onto a different row carries every selected row together.
      if (targetLayerId != null &&
          selection.spanLayerIds.length > 1 &&
          _updateMultiRowRangeMove(selection, frameDelta, targetLayerId)) {
        return;
      }
      // Falling to the plain slide: any prior row-change / multi-row plan
      // is stale now (the slide, not the row change, is last valid).
      _rangeMoveSeRowChange = null;
      _rangeMoveInstructionRowChange = null;
      _rangeMoveMultiRowPlan = null;
      _rangeMoveMultiSeRowChanges = null;
      // …and the rigid step's RIDER shifts die WITH its plans: a stale
      // shift surviving here commits alone when the slide step holds —
      // the rigid group torn in one silent undo step (transition spans
      // moving while the blocks stay home). A valid slide step re-derives
      // them fresh below.
      _rangeMoveCameraShifted = null;
      _rangeMoveInstructionShifted = null;
      // Cross-layer slide (UI-R18 #1): every spanned layer plans the SAME
      // frame delta on itself; any illegal landing HOLDS the last valid
      // preview (all-or-nothing, the single-layer discipline). KEY
      // sources (P3b-2) join the same contract: camera keys and
      // instruction spans shift by the same delta or the whole move
      // voids.
      var illegal = false;
      final plans = <DrawingBlockMovePlan>[];
      for (final source in multiSources) {
        final plan = planDrawingRangeMove(
          source: source.commit,
          target: source.commit,
          rangeStartIndex: selection.startIndex + source.offset,
          rangeEndIndexExclusive: selection.endIndexExclusive + source.offset,
          frameDelta: frameDelta,
          cutFrameCount: _session._activeCutFrameCount,
        );
        if (plan == null) {
          illegal = true;
          plans.clear();
          break;
        }
        plans.add(plan);
      }
      if (multiSources.isEmpty && frameDelta == 0) {
        illegal = true;
      }
      final cameraBefore = _rangeMoveCameraBefore;
      Map<int, CameraPose>? cameraShifted;
      if (!illegal && cameraBefore != null) {
        cameraShifted = shiftCameraKeysInRange(
          keyframes: cameraBefore,
          rangeStartIndex: selection.startIndex,
          rangeEndIndexExclusive: selection.endIndexExclusive,
          frameDelta: frameDelta,
        );
        illegal = cameraShifted == null;
      }
      final instructionShifted = <LayerId, Map<int, InstructionEvent>>{};
      if (!illegal) {
        for (final layer in _rangeMoveInstructionSources ?? const <Layer>[]) {
          final shifted = shiftInstructionEventsInRange(
            events: layer.instructions,
            rangeStartIndex: selection.startIndex,
            rangeEndIndexExclusive: selection.endIndexExclusive,
            frameDelta: frameDelta,
          );
          if (shifted == null) {
            illegal = true;
            break;
          }
          instructionShifted[layer.id] = shifted;
        }
      }
      if (illegal) {
        // UI-R23 #10: a blocked landing HOLDS the last valid preview,
        // outline and stored plans — no snap-back to the origin.
        return;
      }
      _rangeMoveMultiPlans = plans.isEmpty ? null : plans;
      _rangeMoveCameraShifted = cameraShifted;
      _rangeMoveInstructionShifted = instructionShifted.isEmpty
          ? null
          : instructionShifted;
      _session._camera._cameraKeysDragPreview = cameraShifted;
      final cameraMarker = cameraShifted == null
          ? null
          : _session._layerById(_rangeMoveCameraLayerId!)?.copyWith();
      final previewLayers = <LayerId, Layer>{};
      // C2 (2026-08-17): the GLOBAL forms ride the same preview — the
      // storyboard's track-global SE strips resolve THIS map, exactly as
      // they resolve an edge drag's global form, so a move follows the
      // hand live there too instead of jumping on release.
      final previewGlobalLayers = <LayerId, Layer>{};
      for (final plan in plans) {
        // The commit form is computed ONCE; the display clone is that
        // form windowed (UI-R18 #1 seam) — the two can never disagree.
        final commitForm = rederiveRunBehaviors(
          plan.sourceAfter,
          cutFrameCount: _session._activeCutFrameCount,
        );
        if (_session.isTrackSeLayerId(plan.sourceAfter.id)) {
          previewLayers[plan.sourceAfter.id] = _session.trackSeWindow
              .displayLayer(commitForm);
          previewGlobalLayers[plan.sourceAfter.id] = commitForm;
        } else {
          previewLayers[plan.sourceAfter.id] = commitForm;
        }
      }
      // Instruction rows preview with their shifted spans — the cells row
      // renders straight off layer.instructions. ⛔The track-owned
      // TRANSITION row stays OFF this map: on the ACTIVE track
      // [_layerById] DOES find its display clone under the same id
      // (layer_controller inserts it), and a global-keyed entry here
      // would leak into the cut timeline's read-only projection. It
      // previews on its own channel below instead.
      for (final entry in instructionShifted.entries) {
        if (_session._transitions.trackTransitionOwner(entry.key) != null) {
          continue;
        }
        final layer = _session._layerById(entry.key);
        if (layer != null) {
          previewLayers[entry.key] = layer.copyWith(instructions: entry.value);
        }
      }
      _session.dragPreview.value = BlockMoveDragPreview(
        previewLayers: previewLayers,
        previewGlobalLayers: previewGlobalLayers,
        cameraCutId: cameraShifted == null
            ? null
            : _session.activeCutOrNull?.id,
        cameraKeyframes: cameraShifted,
        cameraMarkerLayer: cameraMarker,
      );
      // C1 (2026-08-17): a moved TRANSITION row previews on the row's own
      // channel — the SAME one its edge drags publish to, which is what
      // the storyboard's transition strip already renders live.
      _publishRangeMoveTransitionPreview(instructionShifted);
      final newStart = selection.startIndex + frameDelta;
      if (newStart >= 0) {
        _rangeMoveSelection = TimelineFrameRangeSelection(
          layerId: selection.layerId,
          startIndex: newStart,
          endIndexExclusive: selection.endIndexExclusive + frameDelta,
          layerIds: selection.layerIds,
        );
      }
      return;
    }

    final source = _rangeMoveSourceBefore;
    final groupStart = _rangeMoveGroupStart;
    if (source == null || selection == null || groupStart == null) {
      return;
    }
    Layer? target = source;
    if (targetLayerId != null && targetLayerId != source.id) {
      target = _session._blockMoveEligible(targetLayerId)
          ? _session._layerById(targetLayerId)
          : null;
      // Cross-row drops stay within the SAME SECTION (UI-R20 #2 P3b-3:
      // 행이동도 같은 섹션 내 — animation/storyboard/image interchange
      // freely now; an animation range still never lands on the SE or
      // camera sections).
      if (target != null &&
          timelineSectionForLayerKind(target.kind) !=
              timelineSectionForLayerKind(source.kind)) {
        target = null;
      }
    }
    final plan = target == null
        ? null
        : planDrawingRangeMove(
            source: source,
            target: target,
            rangeStartIndex: selection.startIndex,
            rangeEndIndexExclusive: selection.endIndexExclusive,
            frameDelta: frameDelta,
            cutFrameCount: _session._activeCutFrameCount,
          );
    if (plan == null) {
      // UI-R23 #10: a blocked / incompatible landing HOLDS the last valid
      // preview, outline and plan — the move stops at the last legal spot
      // and resumes on a legal return (no snap-back to the origin).
      return;
    }
    _rangeMovePlan = plan;
    _session.dragPreview.value = BlockMoveDragPreview(
      previewLayers: {
        plan.sourceAfter.id: rederiveRunBehaviors(
          plan.sourceAfter,
          cutFrameCount: _session._activeCutFrameCount,
        ),
        if (plan.targetAfter != null)
          plan.targetAfter!.id: rederiveRunBehaviors(
            plan.targetAfter!,
            cutFrameCount: _session._activeCutFrameCount,
          ),
      },
    );
    // The selection outline follows the previewed landing live.
    final landedLayerId = plan.isCrossLayer ? plan.targetAfter!.id : source.id;
    final startShift = plan.destinationStartIndex - groupStart;
    final newStart = selection.startIndex + startShift;
    if (newStart >= 0) {
      _rangeMoveSelection = TimelineFrameRangeSelection(
        layerId: landedLayerId,
        startIndex: newStart,
        endIndexExclusive: selection.endIndexExclusive + startShift,
      );
    }
  }

  /// Commits the range move as ONE undo step (layer updates + the brush
  /// re-key on cross-layer carries), mirroring the block-move commit.
  void endFrameRangeMoveDrag() {
    final source = _rangeMoveSourceBefore;
    final selection = _rangeMoveSelectionBefore;
    final plan = _rangeMovePlan;
    final multiPlans = _rangeMoveMultiPlans;
    final multiSources = _rangeMoveMultiSources;
    final cameraShifted = _rangeMoveCameraShifted;
    final instructionShifted = _rangeMoveInstructionShifted;
    final seRowChange = _rangeMoveSeRowChange;
    final instructionRowChange = _rangeMoveInstructionRowChange;
    final multiRowPlan = _rangeMoveMultiRowPlan;
    final multiSeRowChanges = _rangeMoveMultiSeRowChanges;
    final landedSelection = _rangeMoveSelection;
    _rangeMoveSourceBefore = null;
    _rangeMoveSelectionBefore = null;
    _rangeMoveGrabLayerId = null;
    _rangeMoveGroupStart = null;
    _rangeMovePlan = null;
    _rangeMoveMultiSources = null;
    _rangeMoveMultiPlans = null;
    _rangeMoveMultiRowPlan = null;
    _rangeMoveMultiSeRowChanges = null;
    _rangeMoveCameraBefore = null;
    _rangeMoveCameraLayerId = null;
    _rangeMoveInstructionSources = null;
    _rangeMoveCameraShifted = null;
    _rangeMoveInstructionShifted = null;
    _rangeMoveSeRowChange = null;
    _rangeMoveInstructionRowChange = null;
    _session._camera._cameraKeysDragPreview = null;
    _session.dragPreview.value = null;
    _session.transitionEdgeDragPreview.value = null;
    // ROW-CHANGE commits (P3b-4): the planned pair replaces both rows in
    // one composite undo; the selection follows the landing row.
    if (selection != null && seRowChange != null) {
      _session._historyManager.execute(
        CompositeCommand(
          description: 'Move frame range',
          commands: [
            UpdateLayerTimelineCommand(
              repository: _session._repository,
              before: seRowChange.sourceBefore,
              after: seRowChange.sourceAfter,
            ),
            UpdateLayerTimelineCommand(
              repository: _session._repository,
              before: seRowChange.targetBefore,
              after: seRowChange.targetAfter,
            ),
          ],
        ),
      );
      _rangeMoveSelection = landedSelection;
      _session._layerController.selectLayer(seRowChange.targetId);
      _session._warmActiveCut();
      _session._notifyChanged();
      return;
    }
    if (selection != null && instructionRowChange != null) {
      final cut = _session.activeCutOrNull;
      if (cut != null) {
        _session._historyManager.execute(
          CompositeCommand(
            description: 'Move frame range',
            commands: [
              UpdateLayerInstructionsCommand(
                repository: _session._repository,
                cutId: cut.id,
                layerId: instructionRowChange.sourceId,
                instructions: instructionRowChange.sourceAfter,
                description: 'Move instruction keys',
              ),
              UpdateLayerInstructionsCommand(
                repository: _session._repository,
                cutId: cut.id,
                layerId: instructionRowChange.targetId,
                instructions: instructionRowChange.targetAfter,
                description: 'Move instruction keys',
              ),
            ],
          ),
        );
        _rangeMoveSelection = landedSelection;
        _session._layerController.selectLayer(instructionRowChange.targetId);
        _session._warmActiveCut();
        _session._notifyChanged();
      } else {
        _rangeMoveSelection = selection;
      }
      return;
    }
    if (selection != null &&
        (multiRowPlan != null || multiSeRowChanges != null)) {
      // MULTI-ROW rigid move commit (UI-R23 #9): every affected drawing row
      // rewrites in one composite undo, and each cross-row cel re-keys its
      // brush frame to the target row. Track-SE passengers (R26 #2) join
      // the SAME undo step through their global-form layer pair.
      final cut = _session.activeCutOrNull;
      final commands = <Command>[];
      for (final se in multiSeRowChanges ?? const <SeRowMovePair>[]) {
        commands.add(
          UpdateLayerTimelineCommand(
            repository: _session._repository,
            before: se.sourceBefore,
            after: se.sourceAfter,
          ),
        );
        commands.add(
          UpdateLayerTimelineCommand(
            repository: _session._repository,
            before: se.targetBefore,
            after: se.targetAfter,
          ),
        );
      }
      for (final entry
          in multiRowPlan?.layersAfter.entries ??
              const <MapEntry<LayerId, Layer>>[]) {
        final before = _session._layerById(entry.key);
        if (before == null) {
          continue;
        }
        final after = rederiveRunBehaviors(
          entry.value,
          cutFrameCount: _session._activeCutFrameCount,
        );
        if (after == before) {
          continue; // An untouched source/target row — no command.
        }
        commands.add(
          UpdateLayerTimelineCommand(
            repository: _session._repository,
            before: before,
            after: after,
          ),
        );
      }
      // R27 #8: the frame-axis riders (camera keys, instruction spans)
      // land in the SAME undo step as the rigid row move — through the
      // ONE two-armed projection the plain slide commits with, so a
      // riding TRANSITION lands too (C④: this branch used to carry a
      // cut-gated copy with the transition arm missing).
      if (instructionShifted != null) {
        commands.addAll(_instructionShiftCommands(instructionShifted, cut));
      }
      if (cut != null && cameraShifted != null) {
        commands.add(
          UpdateCutCameraCommand(
            repository: _session._repository,
            cutId: cut.id,
            camera: CutCamera(keyframes: cameraShifted),
            description: 'Move camera keys',
          ),
        );
      }
      if (cut != null && (multiRowPlan?.rekeys.isNotEmpty ?? false)) {
        commands.add(
          RekeyBrushFramesCommand(
            store: _session.brushFrameStore,
            pairs: [
              for (final rekey in multiRowPlan!.rekeys)
                (
                  _session.brushFrameKeyForCut(cut, rekey.from, rekey.frameId),
                  _session.brushFrameKeyForCut(cut, rekey.to, rekey.frameId),
                ),
            ],
          ),
        );
      }
      if (commands.isEmpty) {
        _rangeMoveSelection = selection;
        return;
      }
      _session._historyManager.execute(
        commands.length == 1
            ? commands.single
            : CompositeCommand(
                description: 'Move frame range',
                commands: commands,
              ),
      );
      _rangeMoveSelection = landedSelection;
      if (landedSelection != null) {
        _session._layerController.selectLayer(landedSelection.layerId);
      }
      _session._warmActiveCut();
      _session._notifyChanged();
      return;
    }
    if (selection != null && multiSources != null) {
      // Cross-layer slide commit (UI-R18 #1) + key shifts (P3b-2): one
      // composite undo across blocks, camera keys and instruction spans.
      // (UI-R23 #3: the layer transform track no longer rides the slide.)
      final cut = _session.activeCutOrNull;
      final commands = <Command>[
        if (multiPlans != null)
          for (var i = 0; i < multiPlans.length; i += 1)
            UpdateLayerTimelineCommand(
              repository: _session._repository,
              before: multiSources[i].commit,
              after: rederiveRunBehaviors(
                multiPlans[i].sourceAfter,
                cutFrameCount: _session._activeCutFrameCount,
              ),
            ),
        if (instructionShifted != null)
          ..._instructionShiftCommands(instructionShifted, cut),
        if (cameraShifted != null && cut != null)
          UpdateCutCameraCommand(
            repository: _session._repository,
            cutId: cut.id,
            camera: CutCamera(keyframes: cameraShifted),
            description: 'Move camera keys',
          ),
      ];
      if (commands.isEmpty) {
        _rangeMoveSelection = selection;
        return;
      }
      _session._historyManager.execute(
        commands.length == 1
            ? commands.single
            : CompositeCommand(
                description: 'Move frame range',
                commands: commands,
              ),
      );
      _rangeMoveSelection = landedSelection;
      _session._warmActiveCut();
      _session._notifyChanged();
      return;
    }
    if (source == null || selection == null) {
      return;
    }
    if (plan == null) {
      _rangeMoveSelection = selection;
      return;
    }
    _session._historyManager.execute(
      _session._singleRowMoveCommand(
        plan,
        source: source,
        description: 'Move frame range',
      ),
    );
    // The selection stays on the moved frames where they landed.
    _rangeMoveSelection = landedSelection;
    if (plan.isCrossLayer) {
      _session._layerController.selectLayer(plan.targetAfter!.id);
    }
    _session._warmActiveCut();
    _session._notifyChanged();
  }

  /// Drops an in-flight range-move preview, restoring the selection.
  void cancelFrameRangeMoveDrag() {
    final selection = _rangeMoveSelectionBefore;
    _rangeMoveSourceBefore = null;
    _rangeMoveSelectionBefore = null;
    _rangeMoveGrabLayerId = null;
    _rangeMoveGroupStart = null;
    _rangeMovePlan = null;
    _rangeMoveMultiSources = null;
    _rangeMoveMultiPlans = null;
    _rangeMoveMultiRowPlan = null;
    _rangeMoveMultiSeRowChanges = null;
    _rangeMoveCameraBefore = null;
    _rangeMoveCameraLayerId = null;
    _rangeMoveInstructionSources = null;
    _rangeMoveCameraShifted = null;
    _rangeMoveInstructionShifted = null;
    _rangeMoveSeRowChange = null;
    _rangeMoveInstructionRowChange = null;
    _session._camera._cameraKeysDragPreview = null;
    _session.dragPreview.value = null;
    _session.transitionEdgeDragPreview.value = null;
    if (selection != null) {
      _rangeMoveSelection = selection;
    }
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
    if (!_session._blockMoveEligible(layerId)) {
      return;
    }
    final before = _session._layerById(layerId);
    if (before == null) {
      return;
    }
    // Design E: the storyboard row refuses repeat/hold regions outright —
    // a derived instance would look exactly like a panel while owning no
    // memo of its own. Copy the frames instead.
    if (!layerKindAcceptsRepeatRegions(before.kind)) {
      return;
    }
    final run = gluedRunAt(before, blockStartIndex);
    if (run == null) {
      return;
    }

    // Replace any behavior already sitting on this (run, side).
    bool ownsThisEdge(TimelineRunBehavior behavior) {
      if (behavior.side != side) {
        return false;
      }
      for (final entry in before.timeline.entries) {
        if (entry.value.ghost ||
            entry.value.frameId != behavior.anchorFrameId) {
          continue;
        }
        return entry.key >= run.startIndex && entry.key < run.endIndexExclusive;
      }
      return false;
    }

    FrameId? patternAnchor;
    if (mode == TimelineRunEdgeMode.repeat && scopeToSelection) {
      final selection = _session.frameRangeSelection.value;
      if (selection != null && selection.layerId == layerId) {
        if (side == TimelineRunEdgeSide.end &&
            selection.contains(run.endIndexExclusive - 1) &&
            selection.startIndex > run.startIndex) {
          // Pattern = first block at/after the selection start → run end.
          for (final entry in before.timeline.entries) {
            if (!entry.value.ghost &&
                entry.key >= selection.startIndex &&
                entry.key < run.endIndexExclusive) {
              patternAnchor = entry.value.frameId;
              break;
            }
          }
        } else if (side == TimelineRunEdgeSide.start &&
            selection.contains(run.startIndex) &&
            selection.endIndexExclusive < run.endIndexExclusive) {
          // Pattern = run start → the last block ending by the selection.
          for (final entry in before.timeline.entries) {
            if (entry.value.ghost ||
                entry.key < run.startIndex ||
                entry.key >= selection.endIndexExclusive) {
              continue;
            }
            patternAnchor = entry.value.frameId;
          }
        }
      }
    }

    // The behavior anchors to its EDGE block (UI-R10 #4): the end side to
    // the run's LAST block, the start side to the FIRST — splitting the
    // run keeps the property with the fragment that owns that edge.
    var edgeAnchor = run.anchorFrameId;
    if (side == TimelineRunEdgeSide.end) {
      for (final entry in before.timeline.entries) {
        if (entry.value.ghost ||
            entry.key < run.startIndex ||
            entry.key >= run.endIndexExclusive) {
          continue;
        }
        edgeAnchor = entry.value.frameId!;
      }
    }
    final behaviors = [
      for (final behavior in before.runBehaviors)
        if (!ownsThisEdge(behavior)) behavior,
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
      cutFrameCount: _session._activeCutFrameCount,
    );
    if (after == before) {
      return;
    }
    _session._timelineController.commitLayerTimelineDrag(
      before: before,
      after: after,
    );
    _session._warmActiveCut();
    _session._notifyChanged();
  }

  /// What [displayDelta] means INSIDE [lattice] for the row [layerId]:
  /// walk the display rows by the hop, then read where the row it landed
  /// on sits in the lattice. Null when the hop leaves the screen or lands
  /// on a row this kind of content cannot live on.
  int? _latticeHopFor({
    required List<Layer> rows,
    required List<Layer> lattice,
    required LayerId layerId,
    required int displayDelta,
  }) {
    final rowIndex = rows.indexWhere((layer) => layer.id == layerId);
    if (rowIndex == -1) {
      return null;
    }
    final landingIndex = rowIndex + displayDelta;
    if (landingIndex < 0 || landingIndex >= rows.length) {
      return null;
    }
    final landingId = rows[landingIndex].id;
    final from = lattice.indexWhere((layer) => layer.id == layerId);
    final to = lattice.indexWhere((layer) => layer.id == landingId);
    if (from == -1 || to == -1) {
      return null;
    }
    return to - from;
  }
}
