import 'dart:collection' show SplayTreeMap;
import '../../models/camera_instruction.dart';
import '../../models/camera_pose.dart';
import '../../models/cut.dart';
import '../../models/cut_camera.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/key_range_move.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_coverage.dart';
import '../../models/timeline_frame_range.dart';
import '../../models/timeline_repeat.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track_frame_range.dart';
import '../../models/drawing_block_move.dart';
import '../../models/multi_row_range_move.dart';
import '../../services/command.dart';
import '../../services/commands/rekey_brush_frames_command.dart';
import '../../services/commands/update_cut_camera_command.dart';
import '../../services/commands/update_layer_instructions_command.dart';
import '../../services/commands/update_layer_timeline_command.dart';
import '../../services/commands/track_transition_commands.dart';
import '../timeline/timeline_drag_preview.dart';
import '../timeline/timeline_section_policy.dart';
import 'session_roles.dart';
import 'transitions.dart';
import 'camera.dart';
import 'range_selections.dart';
import 'folders_and_attachments.dart';
import 'track_se_display.dart';

/// A planned SE row-change pair in COMMIT (global track) form: the source
/// row after its blocks leave, the target row after they arrive.
typedef SeRowMovePair = ({
  LayerId sourceId,
  LayerId targetId,
  Layer sourceBefore,
  Layer sourceAfter,
  Layer targetBefore,
  Layer targetAfter,
});

/// The rows a rigid multi-row step can hop across: the display rows the
/// pointer travels, the drawing lattice and the track-SE lattice.
typedef MultiRowLattices = ({
  List<Layer> rows,
  List<Layer> lattice,
  List<Layer> seLattice,
});

/// A multi-row span sorted by what each row can DO with a hop: the rows
/// that travel the drawing lattice, and the track-SE rows riding theirs.
typedef MultiRowSpanCast = ({
  List<LayerId> drawingSourceIds,
  List<LayerId> sePassengerIds,
});

/// What one row can DO with a rigid hop (R27 #8, [_castMultiRowSpan]).
enum HopCast {
  /// Travels across its own lattice.
  drawingSource,

  /// Rides along on the track-SE lattice.
  sePassenger,

  /// Its keys ride the FRAME delta and the row stays put.
  frameAxisRider,

  /// Contributes nothing.
  nothing,

  /// Content on a row that is none of the above (a SYNCED attach row):
  /// the step belongs to its base — the plain slide owns it.
  boundToBase,
}

/// One rigid multi-row drag step's subjects, read once per step.
typedef MultiRowStep = ({
  TimelineFrameRangeSelection selection,
  MultiRowSpanCast cast,
  MultiRowLattices lattices,
});

/// The frame-axis riders shifted with a move: the camera keys (null when
/// no camera row rides) and each instruction source's events by row.
typedef FrameAxisRiders = ({
  Map<int, CameraPose>? camera,
  Map<LayerId, Map<int, InstructionEvent>> instructions,
});

/// No rider moves: a PURE row hop (frameDelta 0) leaves every key where
/// it is, so the riders simply hold.
const FrameAxisRiders noRiders = (camera: null, instructions: {});

/// The KEY sources a frame-range move carries (P3b-2): the camera keys
/// (with the camera row's id) and the instruction rows that own spans in
/// the range.
typedef KeySources = ({
  Map<int, CameraPose>? cameraBefore,
  LayerId? cameraLayerId,
  List<Layer> instructionSources,
});

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
class FrameRangeMoveDrag {
  FrameRangeMoveDrag({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required SessionInternals internals,
    required Camera camera,
    required FoldersAndAttachments folders,
    required RangeSelections rangeSelections,
    required Transitions transitions,
    required TrackSeDisplay trackSe,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _internals = internals,
       _camera = camera,
       _folders = folders,
       _rangeSelections = rangeSelections,
       _transitions = transitions,
       _trackSe = trackSe;

  final TrackSeDisplay _trackSe;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final SessionInternals _internals;
  final Camera _camera;
  final FoldersAndAttachments _folders;
  final RangeSelections _rangeSelections;
  final Transitions _transitions;

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
      return _selection.frameRangeSelection.value;
    }
    final live = _selection.trackFrameRangeSelection.value;
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
      _selection.frameRangeSelection.value = span;
      return;
    }
    if (span == null) {
      _selection.trackFrameRangeSelection.value = null;
      return;
    }
    // The axis's own facts ride from the drag-start capture: the anchor
    // names its OWN track (the select path's law — re-keying to
    // [selectedTrackId] here hid the band for the whole drag on any other
    // track and left the landed selection keyed to the wrong one), and a
    // non-layer row in a mixed span is not something the layer-stated span
    // can re-derive.
    final before = _rangeMoveTrackSelectionBefore;
    _selection.trackFrameRangeSelection.value = TrackFrameRangeSelection(
      trackId: before?.trackId ?? _selection.selectedTrackId,
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
      : _internals.commitBlockStart(layerId, spanStart) - spanStart;

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
    final live = _selection.trackFrameRangeSelection.value;
    if (live == null) {
      return false;
    }
    _rangeMoveTrackSelectionBefore = live;
    final (:sources, :instructionSources) = _castTrackSources(live);
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

  /// Whether [block] is a real (non-ghost) block lying WHOLE inside
  /// [start, endExclusive) — the one rule every begin uses to decide which
  /// rows carry something to move (the cross-layer slide's rule, UI-R18 #1).
  bool _wholeBlockIn(TimelineDrawingBlock block, int start, int endExclusive) =>
      !block.entry.ghost &&
      block.startIndex >= start &&
      block.endIndexExclusive <= endExclusive;

  /// The rows of [live] that source a move on the track axis — one COMMIT
  /// form per owning layer that carries a whole block inside the range —
  /// and the transition row's spans as instruction sources.
  ({List<({Layer commit, int offset})> sources, List<Layer> instructionSources})
  _castTrackSources(TrackFrameRangeSelection live) {
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
      final transition = _transitions
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
      final commit = _project.trackSeGlobalLayerById(rowLayerId);
      if (commit == null) {
        continue;
      }
      // Only rows that actually carry a WHOLE block inside the range move
      // — the cross-layer slide's rule, unchanged.
      final hasBlock = drawingBlocks(commit.timeline).any(
        (block) =>
            _wholeBlockIn(block, live.startFrame, live.endFrameExclusive),
      );
      if (hasBlock) {
        sources.add((commit: commit, offset: 0));
      }
    }
    return (sources: sources, instructionSources: instructionSources);
  }

  bool beginFrameRangeMoveDrag([LayerId? grabLayerId]) {
    // The axis is decided HERE and nowhere else: every begin states it, so
    // no path can inherit the previous drag's answer.
    _rangeMoveOnTrackAxis = false;
    _rangeMoveTrackSelectionBefore = null;
    final selection = _rangeMoveSelection;
    if (selection == null ||
        !_rangeSelections.rangeSelectionEligible(selection.layerId)) {
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
    final keys = _castKeySources(selection);
    // Multi-layer spans, SE rows and KEY sources route through the
    // frame-axis slide (UI-R18 #1): per-layer plans on the COMMIT forms;
    // row-change drops stay the single-anim path below.
    if (selection.spanLayerIds.length > 1 ||
        _project.isTrackSeLayerId(selection.layerId) ||
        keys.cameraBefore != null ||
        keys.instructionSources.isNotEmpty) {
      return _beginMultiSourceRangeMove(selection, keys);
    }
    return _beginSingleRowRangeMove(selection);
  }

  /// KEY sources (P3b-2, #2 second half): camera keys, instruction
  /// spans AND the layers' own transform-track keys (P3c, #13) inside
  /// the selection move with the blocks — same delta, one rigid group.
  /// SYNCED attach mirrors stay PASSENGERS (P3b-1): the base's slide
  /// carries them by derivation.
  KeySources _castKeySources(TimelineFrameRangeSelection selection) {
    Map<int, CameraPose>? cameraBefore;
    LayerId? cameraLayerId;
    final instructionSources = <Layer>[];
    bool anyKeyIn(Iterable<int> keys) => keys.any(
      (key) => key >= selection.startIndex && key < selection.endIndexExclusive,
    );
    for (final id in selection.spanLayerIds) {
      final layer = _project.layerById(id);
      if (layer == null) {
        continue;
      }
      if (layer.kind == LayerKind.camera) {
        final keyframes = _project.activeCutOrNull?.camera.keyframes;
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
    return (
      cameraBefore: cameraBefore,
      cameraLayerId: cameraLayerId,
      instructionSources: instructionSources,
    );
  }

  /// Begins the frame-axis slide (UI-R18 #1) for a multi-layer span, an
  /// SE row or a span carrying KEY sources: every eligible row's COMMIT
  /// form becomes a source, planned with the same delta as one rigid
  /// group.
  bool _beginMultiSourceRangeMove(
    TimelineFrameRangeSelection selection,
    KeySources keys,
  ) {
    final sources = <({Layer commit, int offset})>[];
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
      final hasBlock = drawingBlocks(display.timeline).any(
        (block) => _wholeBlockIn(
          block,
          selection.startIndex,
          selection.endIndexExclusive,
        ),
      );
      if (hasBlock) {
        sources.add((
          commit: commit,
          offset: _rangeMoveCommitOffset(id, selection.startIndex),
        ));
      }
    }
    if (sources.isEmpty &&
        keys.cameraBefore == null &&
        keys.instructionSources.isEmpty) {
      // An all-synced span dies here — say why at the cursor, like the
      // single-row path does.
      _folders.noticeSyncedAttachRefusal(selection.layerId);
      return false;
    }
    _rangeMoveMultiSources = sources;
    _rangeMoveCameraBefore = keys.cameraBefore;
    _rangeMoveCameraLayerId = keys.cameraLayerId;
    _rangeMoveInstructionSources = keys.instructionSources.isEmpty
        ? null
        : keys.instructionSources;
    _rangeMoveSelectionBefore = selection;
    return true;
  }

  /// Begins the single-row move: the row's first whole block inside the
  /// selection anchors the group; nothing but empty cells means nothing
  /// to move.
  bool _beginSingleRowRangeMove(TimelineFrameRangeSelection selection) {
    // A SYNCED attach row's blocks are borrowed exposures — the move
    // refuses with the "edit the owner" pill (the synced-block UI made
    // the row look grabbable; before it, the all-ghost timeline fell out
    // of the block scan below on its own). A SINGLE-CEL (image) row's
    // covering block is immovable — the normalization would revert it.
    if (_folders.isSyncedAttachedLayerId(selection.layerId)) {
      _folders.noticeSyncedAttachRefusal(selection.layerId);
      return false;
    }
    if (_internals.isSingleCelLayerId(selection.layerId)) {
      return false;
    }
    final layer = _project.layerById(selection.layerId);
    if (layer == null) {
      return false;
    }
    int? groupStart;
    for (final block in drawingBlocks(layer.timeline)) {
      if (_wholeBlockIn(
        block,
        selection.startIndex,
        selection.endIndexExclusive,
      )) {
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
      _camera.showCameraKeysDragPreview(null);
      final newStart = selection.startIndex + frameDelta;
      if (newStart >= 0) {
        _rangeMoveSelection = TimelineFrameRangeSelection(
          layerId: targetLayerId,
          startIndex: newStart,
          endIndexExclusive: selection.endIndexExclusive + frameDelta,
        );
      }
    }

    final sourceIsSe = _project.isTrackSeLayerId(selection.layerId);
    if (sourceIsSe && _project.isTrackSeLayerId(targetLayerId)) {
      final sourceGlobal = _project.trackSeGlobalLayerById(selection.layerId);
      final targetGlobal = _project.trackSeGlobalLayerById(targetLayerId);
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
      _internals.dragPreview.value = BlockMoveDragPreview(
        previewLayers: {
          selection.layerId: _trackSe.trackSeWindow.displayLayer(
            plan.sourceAfter,
          ),
          targetLayerId: _trackSe.trackSeWindow.displayLayer(plan.targetAfter),
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
    final sourceLayer = _project.layerById(selection.layerId);
    final targetLayer = _project.layerById(targetLayerId);
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
      _internals.dragPreview.value = BlockMoveDragPreview(
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
      _project.activeCutOrNull?.layers ?? const [],
    );
    return [
      for (final layer in ordered)
        if (_internals.blockMoveEligible(layer.id)) layer,
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
  List<Layer> _rangeRowOrder() => sectionedLayerOrder(_project.layers);

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
      if (_transitions.trackTransitionOwner(entry.key) case final owner?)
        UpdateTrackTransitionLayerCommand(
          repository: _project.repository,
          trackId: owner.id,
          before: owner.transitionLayer,
          after: owner.transitionLayer.copyWith(
            instructions: SplayTreeMap<int, InstructionEvent>.from(entry.value),
          ),
          debugLabel: 'Move transition',
        )
      else if (cut != null)
        UpdateLayerInstructionsCommand(
          repository: _project.repository,
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
    final cast = _castMultiRowSpan(selection);
    if (cast == null) {
      return false;
    }
    final step = (
      selection: selection,
      cast: cast,
      lattices: _multiRowLattices(),
    );
    final hop = _agreedRowHop(step, targetLayerId);
    final rowDelta = hop.rowDelta;
    if (rowDelta == null) {
      return hop.holds;
    }
    final landing = _planMultiRowLanding(step, frameDelta, rowDelta);
    if (landing == null) {
      return true;
    }
    if (landing.plan == null && landing.sePlans.isEmpty) {
      return false; // Nothing to carry — the plain slide owns the step.
    }
    // R27 #8: the frame-axis riders shift with the same frame delta. A
    // rider that cannot shift voids the move like any other passenger.
    // A PURE row hop (frameDelta 0) moves no frames, so the riders simply
    // hold — the shifters answer null for "nothing to shift" (the R28 #5
    // conflation) and reading that as "blocked" killed every vertical
    // step of a mixed span.
    final riders = frameDelta == 0
        ? noRiders
        : _shiftFrameAxisRiders(selection, frameDelta);
    if (riders == null) {
      return true;
    }
    // A valid rigid landing supersedes the slide / row-change plans.
    _publishMultiRowMovePreview(
      landing.plan,
      landing.sePlans,
      riders.camera,
      riders.instructions,
    );
    _landMultiRowOutline(step, targetLayerId, frameDelta, rowDelta);
    return true;
  }

  /// The outline rides the rigid shift to the target rows (rows that
  /// carried nothing — off the lattice or shifted off it — drop out of
  /// the outline; only the moved frames' landings read selected).
  void _landMultiRowOutline(
    MultiRowStep step,
    LayerId targetLayerId,
    int frameDelta,
    int rowDelta,
  ) {
    final selection = step.selection;
    final landedLayerIds = _landedLayerIds(
      step.lattices.lattice,
      step.lattices.seLattice,
      selection,
      rowDelta,
    );
    final newStart = selection.startIndex + frameDelta;
    if (newStart >= 0) {
      _rangeMoveSelection = TimelineFrameRangeSelection(
        layerId: targetLayerId,
        startIndex: newStart,
        endIndexExclusive: selection.endIndexExclusive + frameDelta,
        layerIds: landedLayerIds,
      );
    }
  }

  /// The span sorted by what each row can DO with the hop, or null when a
  /// row that cannot hop still carries content (the plain slide owns the
  /// step then).
  ///
  /// R27 #8: sort the span by what each row can DO with the hop. Drawing
  /// rows and track-SE rows travel across their own lattice; the camera
  /// and instruction rows have no row axis to travel, so their keys ride
  /// the FRAME delta and stay put. Empty rows contribute nothing at all.
  ///
  /// The old code made a key-carrying camera/instruction row veto the
  /// whole move ("keys ride the frame axis only" → `return false`). That
  /// is the "임시처방" the user called out: selecting a CAM row next to a
  /// sound block made the sound unmovable, even though its landing row
  /// was empty. A row that cannot change rows now simply doesn't.
  MultiRowSpanCast? _castMultiRowSpan(TimelineFrameRangeSelection selection) {
    bool carriesBlockInRange(Layer layer) => drawingBlocks(layer.timeline).any(
      (block) =>
          !block.entry.ghost &&
          block.startIndex < selection.endIndexExclusive &&
          block.endIndexExclusive > selection.startIndex,
    );
    final drawingSourceIds = <LayerId>[];
    final sePassengerIds = <LayerId>[];
    for (final id in selection.spanLayerIds) {
      switch (_castRowForHop(id, carriesBlockInRange)) {
        case HopCast.drawingSource:
          drawingSourceIds.add(id);
        case HopCast.sePassenger:
          sePassengerIds.add(id);
        case HopCast.boundToBase:
          return null;
        case HopCast.frameAxisRider || HopCast.nothing:
          break;
      }
    }
    return (drawingSourceIds: drawingSourceIds, sePassengerIds: sePassengerIds);
  }

  /// Which [HopCast] the row [id] is for this hop, given whether a row
  /// [carriesBlockInRange].
  HopCast _castRowForHop(LayerId id, bool Function(Layer) carriesBlockInRange) {
    if (_internals.blockMoveEligible(id)) {
      final layer = _project.layerById(id);
      return layer != null && carriesBlockInRange(layer)
          ? HopCast.drawingSource
          : HopCast.nothing;
    }
    if (_project.isTrackSeLayerId(id)) {
      final display = _project.rangeLayerById(id);
      return display != null && carriesBlockInRange(display)
          ? HopCast.sePassenger
          : HopCast.nothing;
    }
    final layer = _project.layerById(id);
    if (layer == null) {
      return HopCast.nothing;
    }
    // The camera and instruction rows (the transition included, via its
    // display clone) are frame-axis riders — WHO rides was decided at
    // begin (_rangeMoveCameraBefore and _rangeMoveInstructionSources,
    // the same answers the plain slide consumes). Re-deriving them here
    // is the copy that silently dropped the TRANSITION on rigid steps
    // (C④): its clone's kind matched no arm, so the spans snapped home
    // the moment the pointer crossed a row.
    if (layer.kind == LayerKind.camera ||
        layer.kind == LayerKind.instruction ||
        layer.kind == LayerKind.transition) {
      return HopCast.frameAxisRider;
    }
    // A row that is neither move-eligible nor a known frame-axis rider
    // (a SYNCED attach row) still routes the step to the plain slide
    // when it carries content: its timing belongs to its base.
    return carriesBlockInRange(layer) ? HopCast.boundToBase : HopCast.nothing;
  }

  /// The row orders a rigid step reads: the display rows (where the
  /// pointer is), the drawing lattice and the track-SE lattice (where
  /// rows can land).
  MultiRowLattices _multiRowLattices() => (
    rows: _rangeRowOrder(),
    lattice: _blockMoveLattice(),
    seLattice: _selection.activeTrack.seLayers,
  );

  /// The rigid row hop for this step: `rowDelta` when the whole span
  /// agrees on one, else null with `holds` — true HOLDS the last valid
  /// preview, false hands the step to the plain frame slide.
  ({int? rowDelta, bool holds}) _agreedRowHop(
    MultiRowStep step,
    LayerId targetLayerId,
  ) {
    final cast = step.cast;
    final lattices = step.lattices;
    final displayDelta = _displayRowDelta(
      lattices.rows,
      _rangeMoveGrabLayerId ?? step.selection.layerId,
      targetLayerId,
    );
    if (displayDelta == null) {
      // The pointer left the rows entirely. When something in the span
      // CAN travel, HOLD the last valid preview (UI-R23 #10); otherwise
      // the plain slide owns the step.
      return (
        rowDelta: null,
        holds:
            cast.drawingSourceIds.isNotEmpty || cast.sePassengerIds.isNotEmpty,
      );
    }
    if (displayDelta == 0) {
      // No row change this step — the plain frame slide owns it.
      return (rowDelta: null, holds: false);
    }
    final drawingHop = _agreedLatticeHop(
      rows: lattices.rows,
      lattice: lattices.lattice,
      ids: cast.drawingSourceIds,
      displayDelta: displayDelta,
    );
    final seHop = _agreedLatticeHop(
      rows: lattices.rows,
      lattice: lattices.seLattice,
      ids: cast.sePassengerIds,
      displayDelta: displayDelta,
    );
    if (drawingHop.blocked || seHop.blocked) {
      // A content-bearing row has nowhere to land (or two rows would need
      // different hops): all-or-nothing, HOLD the last valid preview.
      return (rowDelta: null, holds: true);
    }
    // A hop of 0 alongside a non-zero one would tear the rigid move apart
    // — the slide owns those steps instead.
    final rowDelta = drawingHop.delta ?? seHop.delta;
    if (rowDelta == null || rowDelta == 0) {
      return (rowDelta: null, holds: false);
    }
    if ((drawingHop.delta ?? rowDelta) != rowDelta ||
        (seHop.delta ?? rowDelta) != rowDelta) {
      return (rowDelta: null, holds: false);
    }
    return (rowDelta: rowDelta, holds: true);
  }

  /// The rigid landing's plans — the drawing rows' plan and the SE
  /// passengers' pairs — or null when a row cannot land, which HOLDS the
  /// last valid preview (R23 #10).
  ({MultiRowRangeMovePlan? plan, List<SeRowMovePair> sePlans})?
  _planMultiRowLanding(MultiRowStep step, int frameDelta, int rowDelta) {
    final selection = step.selection;
    MultiRowRangeMovePlan? plan;
    if (step.cast.drawingSourceIds.isNotEmpty) {
      plan = planMultiRowRangeMove(
        orderedLayers: step.lattices.lattice,
        sourceLayerIds: selection.spanLayerIds,
        rangeStartIndex: selection.startIndex,
        rangeEndIndexExclusive: selection.endIndexExclusive,
        frameDelta: frameDelta,
        rowDelta: rowDelta,
      );
      if (plan == null) {
        // An illegal rigid landing HOLDS the last valid preview (R23 #10).
        return null;
      }
    }
    final sePlans = step.cast.sePassengerIds.isEmpty
        ? const <SeRowMovePair>[]
        : _planMultiRowSePassengers(
            seSourceIds: step.cast.sePassengerIds,
            seLattice: step.lattices.seLattice,
            selection: selection,
            frameDelta: frameDelta,
            rowDelta: rowDelta,
          );
    if (sePlans == null) {
      return null; // An SE passenger cannot land — the whole move voids.
    }
    return (plan: plan, sePlans: sePlans);
  }

  /// The frame-axis riders shifted by [frameDelta] — the camera keys when
  /// a camera row rides, and every instruction source's events — or null
  /// when a rider cannot shift, which voids the whole move (P3b-2: KEY
  /// sources join the all-or-nothing contract). WHO rides was decided at
  /// begin; the plain slide and the rigid row hop both ask here.
  FrameAxisRiders? _shiftFrameAxisRiders(
    TimelineFrameRangeSelection selection,
    int frameDelta,
  ) {
    final cameraBefore = _rangeMoveCameraBefore;
    Map<int, CameraPose>? cameraShifted;
    if (cameraBefore != null) {
      cameraShifted = shiftCameraKeysInRange(
        keyframes: cameraBefore,
        rangeStartIndex: selection.startIndex,
        rangeEndIndexExclusive: selection.endIndexExclusive,
        frameDelta: frameDelta,
      );
      if (cameraShifted == null) {
        return null;
      }
    }
    final instructionShifted = <LayerId, Map<int, InstructionEvent>>{};
    for (final layer in _rangeMoveInstructionSources ?? const <Layer>[]) {
      final shifted = shiftInstructionEventsInRange(
        events: layer.instructions,
        rangeStartIndex: selection.startIndex,
        rangeEndIndexExclusive: selection.endIndexExclusive,
        frameDelta: frameDelta,
      );
      if (shifted == null) {
        return null;
      }
      instructionShifted[layer.id] = shifted;
    }
    return (camera: cameraShifted, instructions: instructionShifted);
  }

  List<LayerId> _landedLayerIds(
    List<Layer> lattice,
    List<Layer> seLattice,
    TimelineFrameRangeSelection selection,
    int rowDelta,
  ) {
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
    return landedLayerIds;
  }

  void _publishMultiRowMovePreview(
    MultiRowRangeMovePlan? plan,
    List<SeRowMovePair> sePlans,
    Map<int, CameraPose>? cameraShifted,
    Map<LayerId, Map<int, InstructionEvent>> instructionShifted,
  ) {
    _rangeMoveMultiRowPlan = plan;
    _rangeMoveMultiSeRowChanges = sePlans.isEmpty ? null : sePlans;
    _rangeMoveMultiPlans = null;
    _rangeMoveSeRowChange = null;
    _rangeMoveInstructionRowChange = null;
    _rangeMoveCameraShifted = cameraShifted;
    _rangeMoveInstructionShifted = instructionShifted.isEmpty
        ? null
        : instructionShifted;
    _camera.showCameraKeysDragPreview(cameraShifted);
    _internals.dragPreview.value = BlockMoveDragPreview(
      previewLayers: {
        if (plan != null)
          for (final entry in plan.layersAfter.entries)
            entry.key: rederiveRunBehaviors(
              entry.value,
              cutFrameCount: _project.activeCutFrameCount,
            ),
        for (final se in sePlans) ...{
          se.sourceId: _trackSe.trackSeWindow.displayLayer(se.sourceAfter),
          se.targetId: _trackSe.trackSeWindow.displayLayer(se.targetAfter),
        },
        // R27 #8: the frame-axis riders preview their shifted spans in
        // place (the cells row renders straight off layer.instructions).
        // ⛔The TRANSITION stays OFF this map: on the ACTIVE track
        // layerById finds its display clone under the same id, and a
        // global-keyed entry here would leak into the cut timeline's
        // read-only projection. It previews on its own channel below.
        for (final entry in instructionShifted.entries)
          if (_transitions.trackTransitionOwner(entry.key) == null &&
              _project.layerById(entry.key) != null)
            entry.key: _project
                .layerById(entry.key)!
                .copyWith(instructions: entry.value),
      },
      // C2: the SE passengers' global forms, for the storyboard strips.
      previewGlobalLayers: {
        for (final se in sePlans) ...{
          se.sourceId: se.sourceAfter,
          se.targetId: se.targetAfter,
        },
      },
      cameraCutId: cameraShifted == null ? null : _project.activeCutOrNull?.id,
      cameraKeyframes: cameraShifted,
      // A FRESH CLONE per step (the P3b-2 contract) — the gate compares
      // identities, and the repository instance trips nothing (B4-①: the
      // multi-row rigid path was the one place still handing it over raw,
      // so a union drag spanning rows froze the camera's markers).
      cameraMarkerLayer:
          cameraShifted == null || _rangeMoveCameraLayerId == null
          ? null
          : _project.layerById(_rangeMoveCameraLayerId!)?.copyWith(),
    );
    // C1: the transition channel follows every published step — a riding
    // transition previews its shifted spans here (C④: it used to be
    // absent from this path's shift map, so the write CLEARED the channel
    // and the spans snapped home on every rigid step).
    _publishRangeMoveTransitionPreview(instructionShifted);
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
    _camera.showCameraKeysDragPreview(null);
    _internals.dragPreview.value = null;
    _internals.transitionEdgeDragPreview.value = null;
    final selection = _rangeMoveSelectionBefore;
    if (selection != null) {
      _rangeMoveSelection = selection;
    }
  }

  /// C1 (2026-08-17): the in-flight form of a range-moved TRANSITION row,
  /// published on [_internals.transitionEdgeDragPreview] — the channel the row's edge
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
      final owner = _transitions.trackTransitionOwner(entry.key);
      if (owner != null) {
        preview = owner.transitionLayer.copyWith(
          instructions: SplayTreeMap<int, InstructionEvent>.from(entry.value),
        );
      }
    }
    _internals.transitionEdgeDragPreview.value = preview;
  }

  /// A range-move drag step: live preview on [_internals.dragPreview] (repository
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
      _updateMultiSourceRangeMove(
        targetLayerId,
        selection,
        frameDelta,
        multiSources,
      );
      return;
    }

    final source = _rangeMoveSourceBefore;
    final groupStart = _rangeMoveGroupStart;
    if (source == null || selection == null || groupStart == null) {
      return;
    }
    final target = _singleRowMoveTarget(source, targetLayerId);
    final plan = target == null
        ? null
        : planDrawingRangeMove(
            source: source,
            target: target,
            rangeStartIndex: selection.startIndex,
            rangeEndIndexExclusive: selection.endIndexExclusive,
            frameDelta: frameDelta,
            cutFrameCount: _project.activeCutFrameCount,
          );
    if (plan == null) {
      // UI-R23 #10: a blocked / incompatible landing HOLDS the last valid
      // preview, outline and plan — the move stops at the last legal spot
      // and resumes on a legal return (no snap-back to the origin).
      return;
    }
    _publishSingleRowMove(plan, selection, source, groupStart);
  }

  /// The row a single-row range move lands on: [source] itself, or the
  /// row [targetLayerId] names when it is move-eligible and in the same
  /// section — else none, and the step has no plan.
  Layer? _singleRowMoveTarget(Layer source, LayerId? targetLayerId) {
    Layer? target = source;
    if (targetLayerId != null && targetLayerId != source.id) {
      target = _internals.blockMoveEligible(targetLayerId)
          ? _project.layerById(targetLayerId)
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
    return target;
  }

  /// Publishes a single-row [plan]: the plan itself, the preview layers,
  /// and the selection moved to where the group landed.
  void _publishSingleRowMove(
    DrawingBlockMovePlan plan,
    TimelineFrameRangeSelection selection,
    Layer source,
    int groupStart,
  ) {
    _rangeMovePlan = plan;
    _internals.dragPreview.value = BlockMoveDragPreview(
      previewLayers: {
        plan.sourceAfter.id: rederiveRunBehaviors(
          plan.sourceAfter,
          cutFrameCount: _project.activeCutFrameCount,
        ),
        if (plan.targetAfter != null)
          plan.targetAfter!.id: rederiveRunBehaviors(
            plan.targetAfter!,
            cutFrameCount: _project.activeCutFrameCount,
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

  void _updateMultiSourceRangeMove(
    LayerId? targetLayerId,
    TimelineFrameRangeSelection selection,
    int frameDelta,
    List<({Layer commit, int offset})> multiSources,
  ) {
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
    final plans = _planSlide(multiSources, selection, frameDelta);
    final riders = plans == null
        ? null
        : _shiftFrameAxisRiders(selection, frameDelta);
    if (plans == null || riders == null) {
      // UI-R23 #10: a blocked landing HOLDS the last valid preview,
      // outline and stored plans — no snap-back to the origin.
      return;
    }
    final cameraShifted = riders.camera;
    final instructionShifted = riders.instructions;
    _rangeMoveMultiPlans = plans.isEmpty ? null : plans;
    _rangeMoveCameraShifted = cameraShifted;
    _rangeMoveInstructionShifted = instructionShifted.isEmpty
        ? null
        : instructionShifted;
    _publishSlidePreview(plans, riders);
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

  /// Forgets the drag — every stored source, plan and rider shift — and
  /// clears the preview channels it published to. The end and the cancel
  /// both forget through here (they were two copies of this list).
  void _clearRangeMoveState() {
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
    _camera.showCameraKeysDragPreview(null);
    _internals.dragPreview.value = null;
    _internals.transitionEdgeDragPreview.value = null;
  }

  /// Cross-layer slide (UI-R18 #1): every spanned layer plans the SAME
  /// frame delta on itself; any illegal landing HOLDS the last valid
  /// preview (all-or-nothing, the single-layer discipline). KEY
  /// sources (P3b-2) join the same contract: camera keys and
  /// instruction spans shift by the same delta or the whole move
  /// voids.
  List<DrawingBlockMovePlan>? _planSlide(
    List<({Layer commit, int offset})> multiSources,
    TimelineFrameRangeSelection selection,
    int frameDelta,
  ) {
    if (multiSources.isEmpty && frameDelta == 0) {
      return null;
    }
    final plans = <DrawingBlockMovePlan>[];
    for (final source in multiSources) {
      final plan = planDrawingRangeMove(
        source: source.commit,
        target: source.commit,
        rangeStartIndex: selection.startIndex + source.offset,
        rangeEndIndexExclusive: selection.endIndexExclusive + source.offset,
        frameDelta: frameDelta,
        cutFrameCount: _project.activeCutFrameCount,
      );
      if (plan == null) {
        return null;
      }
      plans.add(plan);
    }
    return plans;
  }

  /// Publishes a valid slide step: every plan's commit form (windowed for
  /// the track-SE rows), the shifted instruction rows, the camera keys on
  /// their own channel, and the transition on its own.
  void _publishSlidePreview(
    List<DrawingBlockMovePlan> plans,
    FrameAxisRiders riders,
  ) {
    final cameraShifted = riders.camera;
    final instructionShifted = riders.instructions;
    _camera.showCameraKeysDragPreview(cameraShifted);
    final cameraMarker = cameraShifted == null
        ? null
        : _project.layerById(_rangeMoveCameraLayerId!)?.copyWith();
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
        cutFrameCount: _project.activeCutFrameCount,
      );
      if (_project.isTrackSeLayerId(plan.sourceAfter.id)) {
        previewLayers[plan.sourceAfter.id] = _trackSe.trackSeWindow
            .displayLayer(commitForm);
        previewGlobalLayers[plan.sourceAfter.id] = commitForm;
      } else {
        previewLayers[plan.sourceAfter.id] = commitForm;
      }
    }
    // Instruction rows preview with their shifted spans — the cells row
    // renders straight off layer.instructions. ⛔The track-owned
    // TRANSITION row stays OFF this map: on the ACTIVE track
    // [layerById] DOES find its display clone under the same id
    // (layer_controller inserts it), and a global-keyed entry here
    // would leak into the cut timeline's read-only projection. It
    // previews on its own channel below instead.
    for (final entry in instructionShifted.entries) {
      if (_transitions.trackTransitionOwner(entry.key) != null) {
        continue;
      }
      final layer = _project.layerById(entry.key);
      if (layer != null) {
        previewLayers[entry.key] = layer.copyWith(instructions: entry.value);
      }
    }
    _internals.dragPreview.value = BlockMoveDragPreview(
      previewLayers: previewLayers,
      previewGlobalLayers: previewGlobalLayers,
      cameraCutId: cameraShifted == null ? null : _project.activeCutOrNull?.id,
      cameraKeyframes: cameraShifted,
      cameraMarkerLayer: cameraMarker,
    );
    // C1 (2026-08-17): a moved TRANSITION row previews on the row's own
    // channel — the SAME one its edge drags publish to, which is what
    // the storyboard's transition strip already renders live.
    _publishRangeMoveTransitionPreview(instructionShifted);
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
    _clearRangeMoveState();
    // ROW-CHANGE commits (P3b-4): the planned pair replaces both rows in
    // one composite undo; the selection follows the landing row.
    if (selection != null && seRowChange != null) {
      _commitSeRowMove(seRowChange, landedSelection);
      return;
    }
    if (selection != null && instructionRowChange != null) {
      _commitInstructionRowMove(
        instructionRowChange,
        landedSelection,
        selection,
      );
      return;
    }
    if (selection != null &&
        (multiRowPlan != null || multiSeRowChanges != null)) {
      // MULTI-ROW rigid move commit (UI-R23 #9): every affected drawing row
      // rewrites in one composite undo, and each cross-row cel re-keys its
      // brush frame to the target row. Track-SE passengers (R26 #2) join
      // the SAME undo step through their global-form layer pair.
      _commitMultiRowMove(
        multiSeRowChanges,
        multiRowPlan,
        instructionShifted,
        cameraShifted,
        selection,
        landedSelection,
      );
      return;
    }
    if (selection != null && multiSources != null) {
      // Cross-layer slide commit (UI-R18 #1) + key shifts (P3b-2): one
      // composite undo across blocks, camera keys and instruction spans.
      // (UI-R23 #3: the layer transform track no longer rides the slide.)
      _commitMultiSourceMove(
        multiPlans,
        multiSources,
        instructionShifted,
        cameraShifted,
        selection,
        landedSelection,
      );
      return;
    }
    if (source == null || selection == null) {
      return;
    }
    if (plan == null) {
      _rangeMoveSelection = selection;
      return;
    }
    _project.historyManager.execute(
      _internals.singleRowMoveCommand(
        plan,
        source: source,
        description: 'Move frame range',
      ),
    );
    // The selection stays on the moved frames where they landed.
    _rangeMoveSelection = landedSelection;
    if (plan.isCrossLayer) {
      _timeline.layerController.selectLayer(plan.targetAfter!.id);
    }
    _changes.warmActiveCut();
    _changes.notifyChanged();
  }

  void _commitMultiSourceMove(
    List<DrawingBlockMovePlan>? multiPlans,
    List<({Layer commit, int offset})> multiSources,
    Map<LayerId, Map<int, InstructionEvent>>? instructionShifted,
    Map<int, CameraPose>? cameraShifted,
    TimelineFrameRangeSelection selection,
    TimelineFrameRangeSelection? landedSelection,
  ) {
    final cut = _project.activeCutOrNull;
    final commands = <Command>[
      if (multiPlans != null)
        for (var i = 0; i < multiPlans.length; i += 1)
          UpdateLayerTimelineCommand(
            repository: _project.repository,
            before: multiSources[i].commit,
            after: rederiveRunBehaviors(
              multiPlans[i].sourceAfter,
              cutFrameCount: _project.activeCutFrameCount,
            ),
          ),
      if (instructionShifted != null)
        ..._instructionShiftCommands(instructionShifted, cut),
      if (cameraShifted != null && cut != null)
        UpdateCutCameraCommand(
          repository: _project.repository,
          cutId: cut.id,
          camera: CutCamera(keyframes: cameraShifted),
          description: 'Move camera keys',
        ),
    ];
    if (commands.isEmpty) {
      _rangeMoveSelection = selection;
      return;
    }
    _project.historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(
              description: 'Move frame range',
              commands: commands,
            ),
    );
    _rangeMoveSelection = landedSelection;
    _changes.warmActiveCut();
    _changes.notifyChanged();
    return;
  }

  void _commitMultiRowMove(
    List<SeRowMovePair>? multiSeRowChanges,
    MultiRowRangeMovePlan? multiRowPlan,
    Map<LayerId, Map<int, InstructionEvent>>? instructionShifted,
    Map<int, CameraPose>? cameraShifted,
    TimelineFrameRangeSelection selection,
    TimelineFrameRangeSelection? landedSelection,
  ) {
    final cut = _project.activeCutOrNull;
    final commands = <Command>[];
    commands.addAll(_seRowMoveCommands(multiSeRowChanges));
    commands.addAll(_multiRowLayerCommands(multiRowPlan));
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
          repository: _project.repository,
          cutId: cut.id,
          camera: CutCamera(keyframes: cameraShifted),
          description: 'Move camera keys',
        ),
      );
    }
    if (cut != null && (multiRowPlan?.rekeys.isNotEmpty ?? false)) {
      commands.add(
        RekeyBrushFramesCommand(
          store: _internals.brushFrameStore,
          pairs: [
            for (final rekey in multiRowPlan!.rekeys)
              (
                _internals.brushFrameKeyForCut(cut, rekey.from, rekey.frameId),
                _internals.brushFrameKeyForCut(cut, rekey.to, rekey.frameId),
              ),
          ],
        ),
      );
    }
    if (commands.isEmpty) {
      _rangeMoveSelection = selection;
      return;
    }
    _project.historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(
              description: 'Move frame range',
              commands: commands,
            ),
    );
    _rangeMoveSelection = landedSelection;
    if (landedSelection != null) {
      _timeline.layerController.selectLayer(landedSelection.layerId);
    }
    _changes.warmActiveCut();
    _changes.notifyChanged();
    return;
  }

  /// The timeline commands of the SE row pairs a multi-row move changed:
  /// each pair's source and target rows.
  List<Command> _seRowMoveCommands(List<SeRowMovePair>? multiSeRowChanges) {
    final commands = <Command>[];
    for (final se in multiSeRowChanges ?? const <SeRowMovePair>[]) {
      commands.add(
        UpdateLayerTimelineCommand(
          repository: _project.repository,
          before: se.sourceBefore,
          after: se.sourceAfter,
        ),
      );
      commands.add(
        UpdateLayerTimelineCommand(
          repository: _project.repository,
          before: se.targetBefore,
          after: se.targetAfter,
        ),
      );
    }
    return commands;
  }

  /// The timeline commands of the rows a multi-row plan moved — none for
  /// a row the plan left as it was.
  List<Command> _multiRowLayerCommands(MultiRowRangeMovePlan? multiRowPlan) {
    final commands = <Command>[];
    for (final entry
        in multiRowPlan?.layersAfter.entries ??
            const <MapEntry<LayerId, Layer>>[]) {
      final before = _project.layerById(entry.key);
      if (before == null) {
        continue;
      }
      final after = rederiveRunBehaviors(
        entry.value,
        cutFrameCount: _project.activeCutFrameCount,
      );
      if (after == before) {
        continue; // An untouched source/target row — no command.
      }
      commands.add(
        UpdateLayerTimelineCommand(
          repository: _project.repository,
          before: before,
          after: after,
        ),
      );
    }
    return commands;
  }

  void _commitInstructionRowMove(
    ({
      Map<int, InstructionEvent> sourceAfter,
      LayerId sourceId,
      Map<int, InstructionEvent> targetAfter,
      LayerId targetId,
    })
    instructionRowChange,
    TimelineFrameRangeSelection? landedSelection,
    TimelineFrameRangeSelection selection,
  ) {
    final cut = _project.activeCutOrNull;
    if (cut != null) {
      _project.historyManager.execute(
        CompositeCommand(
          description: 'Move frame range',
          commands: [
            UpdateLayerInstructionsCommand(
              repository: _project.repository,
              cutId: cut.id,
              layerId: instructionRowChange.sourceId,
              instructions: instructionRowChange.sourceAfter,
              description: 'Move instruction keys',
            ),
            UpdateLayerInstructionsCommand(
              repository: _project.repository,
              cutId: cut.id,
              layerId: instructionRowChange.targetId,
              instructions: instructionRowChange.targetAfter,
              description: 'Move instruction keys',
            ),
          ],
        ),
      );
      _rangeMoveSelection = landedSelection;
      _timeline.layerController.selectLayer(instructionRowChange.targetId);
      _changes.warmActiveCut();
      _changes.notifyChanged();
    } else {
      _rangeMoveSelection = selection;
    }
    return;
  }

  void _commitSeRowMove(
    ({
      Layer sourceAfter,
      Layer sourceBefore,
      LayerId sourceId,
      Layer targetAfter,
      Layer targetBefore,
      LayerId targetId,
    })
    seRowChange,
    TimelineFrameRangeSelection? landedSelection,
  ) {
    _project.historyManager.execute(
      CompositeCommand(
        description: 'Move frame range',
        commands: [
          UpdateLayerTimelineCommand(
            repository: _project.repository,
            before: seRowChange.sourceBefore,
            after: seRowChange.sourceAfter,
          ),
          UpdateLayerTimelineCommand(
            repository: _project.repository,
            before: seRowChange.targetBefore,
            after: seRowChange.targetAfter,
          ),
        ],
      ),
    );
    _rangeMoveSelection = landedSelection;
    _timeline.layerController.selectLayer(seRowChange.targetId);
    _changes.warmActiveCut();
    _changes.notifyChanged();
    return;
  }

  /// Drops an in-flight range-move preview, restoring the selection.
  void cancelFrameRangeMoveDrag() {
    final selection = _rangeMoveSelectionBefore;
    _clearRangeMoveState();
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
    if (!layerKindAcceptsRepeatRegions(before.kind)) {
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
    _timeline.timelineController.commitLayerTimelineDrag(
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
    return edgeAnchor;
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
    for (final entry in before.timeline.entries) {
      if (!entry.value.ghost &&
          entry.key >= selection.startIndex &&
          entry.key < run.endIndexExclusive) {
        return entry.value.frameId;
      }
    }
    return null;
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
    FrameId? patternAnchor;
    for (final entry in before.timeline.entries) {
      if (entry.value.ghost ||
          entry.key < run.startIndex ||
          entry.key >= selection.endIndexExclusive) {
        continue;
      }
      patternAnchor = entry.value.frameId;
    }
    return patternAnchor;
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
