import 'dart:collection' show SplayTreeMap;

import '../../../models/camera_instruction.dart';
import '../../../models/camera_pose.dart';
import '../../../models/cut.dart';
import '../../../models/cut_camera.dart';
import '../../../models/drawing_block_move.dart';
import '../../../models/key_range_move.dart';
import '../../../models/layer.dart';
import '../../../models/layer_id.dart';
import '../../../models/layer_kind.dart';
import '../../../models/layer_stack_order.dart';
import '../../../models/multi_row_range_move.dart';
import '../../../models/timeline_coverage.dart';
import '../../../models/timeline_frame_range.dart';
import '../../../models/timeline_repeat.dart';
import '../../../models/timeline_row_address.dart';
import '../../../models/track_frame_range.dart';
import '../../../services/command.dart';
import '../../../services/commands/rekey_brush_frames_command.dart';
import '../../../services/commands/track_transition_commands.dart';
import '../../../services/commands/update_cut_camera_command.dart';
import '../../../services/commands/update_layer_timeline_command.dart';
import '../../timeline/timeline_drag_preview.dart';
import '../../timeline/timeline_section_policy.dart';
import '../active_cut_controllers.dart';
import '../camera.dart';
import '../drawing_block_move_drag.dart';
import '../folders_and_attachments.dart';
import '../range_selections.dart';
import '../render_caches.dart';
import '../row_spans.dart';
import '../session_roles.dart';
import '../track_se_display.dart';
import '../transitions.dart';

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

/// What one row can DO with a rigid hop (R27 #8, [FrameRangeMoveDrag]).
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
/// no camera row rides), the transition's events by row, and each
/// DIRECTION row as the row its shifted blocks make (R27 — its spans are
/// its blocks, so they ride as blocks).
typedef FrameAxisRiders = ({
  Map<int, CameraPose>? camera,
  Map<LayerId, Map<int, InstructionEvent>> instructions,
  Map<LayerId, Layer> directions,
});

/// No rider moves: a PURE row hop (frameDelta 0) leaves every key where
/// it is, so the riders simply hold.
const FrameAxisRiders noRiders = (
  camera: null,
  instructions: {},
  directions: {},
);

/// The KEY sources a frame-range move carries (P3b-2): the camera keys
/// (with the camera row's id) and the instruction rows that own spans in
/// the range.
typedef KeySources = ({
  ({Map<int, CameraPose> before, LayerId layerId})? camera,
  List<Layer> instructionSources,
});

/// Whether [block] is a real (non-ghost) block lying WHOLE inside
/// [start, endExclusive) — the one rule every begin uses to decide which
/// rows carry something to move (the cross-layer slide's rule, UI-R18 #1).
bool _wholeBlockIn(TimelineDrawingBlock block, int start, int endExclusive) =>
    !block.entry.ghost &&
    block.startIndex >= start &&
    block.endIndexExclusive <= endExclusive;

/// The display→commit offset a move applies to [layerId]'s span. ZERO on
/// the track axis: the span is already stated in commit keys, and
/// translating it again would address another cut's frames.
int _commitOffsetFor(
  LayerId layerId,
  int spanStart, {
  required bool onTrackAxis,
  required SessionInternals internals,
}) => onTrackAxis ? 0 : internals.commitBlockStart(layerId, spanStart) - spanStart;

/// The layer-stated span a TRACK-axis selection moves, or null when the
/// track selection names no owning layer.
///
/// C②: an ESCALATED span anchors on a LANE row — its owning layer is the
/// machine's anchor layer, so the span the band advertises is the span
/// the move machine accepts.
///
/// 🚨C3-lane-move: this used to switch on the address TYPE and fall to
/// null on anything else, and the `layerIds` below dropped every row that
/// was not a `LayerRowAddress`. Both are the same mistake stated twice: a
/// lane row HAS an owning layer, so asking the address for it
/// ([TimelineRowAddress.owningLayerId]) is the whole answer. Without it a
/// band that advertised a move quietly became a re-select — the move
/// machine got a null span and the press fell through to the select path,
/// with nothing on screen to say so.
TimelineFrameRangeSelection? _spanOfTrackSelection(
  TrackFrameRangeSelection? live,
) {
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

/// The rows of [live] that source a move on the track axis — one COMMIT
/// form per owning layer that carries a whole block inside the range —
/// and the transition row's spans as instruction sources.
({List<({Layer commit, int offset})> sources, List<Layer> instructionSources})
_castTrackSources(
  TrackFrameRangeSelection live, {
  required ProjectAccess project,
  required Transitions transitions,
}) {
  final sources = <({Layer commit, int offset})>[];
  // C1 (2026-08-17): the TRANSITION row is a movable subject on THIS
  // axis — its spans live global, and this rail is their one author
  // (the cut timeline's clone stays the read-only projection). It rides
  // the move machine's existing INSTRUCTION-source arm, exactly as the
  // cut-local instruction rows do in [FrameRangeMoveDrag.begin].
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
    final transition = transitions
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
    final commit = project.trackSeGlobalLayerById(rowLayerId);
    if (commit == null) {
      continue;
    }
    // Only rows that actually carry a WHOLE block inside the range move
    // — the cross-layer slide's rule, unchanged.
    final hasBlock = drawingBlocks(commit.timeline).any(
      (block) => _wholeBlockIn(block, live.startFrame, live.endFrameExclusive),
    );
    if (hasBlock) {
      sources.add((commit: commit, offset: 0));
    }
  }
  return (sources: sources, instructionSources: instructionSources);
}

/// KEY sources (P3b-2, #2 second half): camera keys, instruction
/// spans AND the layers' own transform-track keys (P3c, #13) inside
/// the selection move with the blocks — same delta, one rigid group.
/// SYNCED attach mirrors stay PASSENGERS (P3b-1): the base's slide
/// carries them by derivation.
KeySources _castKeySources(
  TimelineFrameRangeSelection selection, {
  required ProjectAccess project,
}) {
  ({Map<int, CameraPose> before, LayerId layerId})? camera;
  final instructionSources = <Layer>[];
  bool anyKeyIn(Iterable<int> keys) => keys.any(
    (key) => key >= selection.startIndex && key < selection.endIndexExclusive,
  );
  for (final id in selection.spanLayerIds) {
    final layer = project.layerById(id);
    if (layer == null) {
      continue;
    }
    if (layer.kind == LayerKind.camera) {
      final keyframes = project.activeCutOrNull?.camera.keyframes;
      if (keyframes != null && anyKeyIn(keyframes.keys)) {
        camera = (before: Map<int, CameraPose>.of(keyframes), layerId: id);
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
  return (camera: camera, instructionSources: instructionSources);
}

/// What one cut-local begin picked up — EXACTLY one of the two arms is
/// set. Null means the span carries nothing this drag could move, which
/// is how [FrameRangeMoveDrag.begin] refuses.
typedef _MoveSubjects = ({
  ({Layer layer, int groupStart})? singleRow,
  List<({Layer commit, int offset})>? multiSources,
});

/// The session handles a frame-range move keeps for its whole flight.
///
/// ⛔They travel as ONE argument, and that is not tidiness: spelling the
/// ten of them at each of the two factories, and again at each of the two
/// verbs, is four copies of the same wiring — the clone gate caught
/// exactly that when this drag first took its factory shape (2026-09-10).
/// The drag still holds them as ten separate fields; the constructor's
/// initializer list unpacks them ONCE.
typedef FrameRangeMoveRoles = ({
  ProjectAccess project,
  SelectionAccess selection,
  ChangeSink changes,
  ActiveCutControllers controllers,
  SessionInternals internals,
  DrawingBlockMoveDragVerbs blockMove,
  RenderCaches renderCaches,
  Camera camera,
  Transitions transitions,
  TrackSeDisplay trackSe,
});

/// The frame-range MOVE DRAG — a selection of cells picked up and put down
/// on the frame axis, previewed live and committed once — as ONE object
/// that exists only while the gesture does.
///
/// 🚨It is BORN by a factory that can refuse ([begin] / [beginOnTrackAxis]
/// answer null) and dies at [commit] or [cancel]. That is the whole point
/// of the shape, and it is not about line count: every field below means
/// something only DURING a drag, so none of them may be able to exist when
/// there is no drag. The verbs used to answer `bool` on a long-lived
/// collaborator, which made "half a drag" representable — a refused begin
/// left the axis flag, the sources and the grabbed row standing from the
/// attempt, and every step afterwards re-asked "is there a selection?"
/// because the answer could still be no.
///
/// What follows from that: [_selectionBefore] is FINAL and non-null (a
/// drag without a subject span cannot be constructed), the axis is not a
/// flag of its own ([_trackSelectionBefore] carries it), and there is no
/// "forget everything" verb — the object IS the state, so dropping it is
/// the forgetting. Only the preview CHANNELS, which live outside, are
/// cleared by hand.
class FrameRangeMoveDrag {
  FrameRangeMoveDrag._({
    required FrameRangeMoveRoles roles,
    required TimelineFrameRangeSelection selectionBefore,
    required TrackFrameRangeSelection? trackSelectionBefore,
    required LayerId? grabLayerId,
    required ({Layer layer, int groupStart})? singleRow,
    required List<({Layer commit, int offset})>? multiSources,
    required ({Map<int, CameraPose> before, LayerId layerId})? cameraKeys,
    required List<Layer>? instructionSources,
  }) : _project = roles.project,
       _selection = roles.selection,
       _changes = roles.changes,
       _controllers = roles.controllers,
       _internals = roles.internals,
       _blockMove = roles.blockMove,
       _renderCaches = roles.renderCaches,
       _camera = roles.camera,
       _transitions = roles.transitions,
       _trackSe = roles.trackSe,
       _selectionBefore = selectionBefore,
       _trackSelectionBefore = trackSelectionBefore,
       _grabLayerId = grabLayerId,
       _singleRow = singleRow,
       _multiSources = multiSources,
       _cameraKeys = cameraKeys,
       _instructionSources = instructionSources;

  /// A range-move drag on the TRACK axis — the storyboard's S rows. Null
  /// when the track selection is gone, names no owning layer, or covers
  /// nothing movable.
  ///
  /// The same machine as [begin]: it plans on its sources' COMMIT forms,
  /// and a track-SE row's commit form is the global layer whichever rail
  /// asked. What is different is only the axis the span is stated in, so
  /// the sources take offset 0 (the range is ALREADY in their keys) where
  /// a cut-local drag would carry the cut's start.
  ///
  /// Track rows are not movable subjects here: a cut row's blocks are cuts
  /// and sliding those is the cut drag's job, which the storyboard's own V
  /// row already mounts.
  static FrameRangeMoveDrag? beginOnTrackAxis({
    required FrameRangeMoveRoles roles,
    LayerId? grabLayerId,
  }) {
    final live = roles.selection.trackFrameRangeSelection.value;
    if (live == null) {
      return null;
    }
    final (:sources, :instructionSources) = _castTrackSources(
      live,
      project: roles.project,
      transitions: roles.transitions,
    );
    if (sources.isEmpty && instructionSources.isEmpty) {
      return null;
    }
    final span = _spanOfTrackSelection(live);
    if (span == null) {
      return null;
    }
    return FrameRangeMoveDrag._(
      roles: roles,
      selectionBefore: span,
      trackSelectionBefore: live,
      grabLayerId: grabLayerId,
      singleRow: null,
      multiSources: sources,
      cameraKeys: null,
      instructionSources: instructionSources.isEmpty
          ? null
          : instructionSources,
    );
  }

  /// Starts moving the CURRENT cut-local frame-range selection; null when
  /// there is none (or its row stands down, or the span holds nothing but
  /// empty cells).
  ///
  /// Cross-layer selections (UI-R18 #1) move too: every spanned layer's
  /// selected blocks slide together along the frame axis, one composite
  /// undo on release. Row-changing drops stay single-layer (the kind
  /// guard would make partial rect drops ambiguous).
  /// [grabLayerId] = the row the pointer went down on (R27 #8); null falls
  /// back to the selection's anchor row (the callers that have no pointer,
  /// e.g. tests of a single-row move).
  static FrameRangeMoveDrag? begin({
    required FrameRangeMoveRoles roles,
    required RowSpans rowSpans,
    required FoldersAndAttachments folders,
    required RangeSelections rangeSelections,
    LayerId? grabLayerId,
  }) {
    final span = roles.selection.frameRangeSelection.value;
    if (span == null || !rangeSelections.rangeSelectionEligible(span.layerId)) {
      return null;
    }
    final keys = _castKeySources(span, project: roles.project);
    // Multi-layer spans, SE rows and KEY sources route through the
    // frame-axis slide (UI-R18 #1): per-layer plans on the COMMIT forms;
    // row-change drops stay the single-anim path below.
    final multiSource =
        span.spanLayerIds.length > 1 ||
        roles.project.isTrackSeLayerId(span.layerId) ||
        keys.camera != null ||
        keys.instructionSources.isNotEmpty;
    final subjects = multiSource
        ? _multiSourceSubjects(
            span,
            keys,
            internals: roles.internals,
            folders: folders,
            rangeSelections: rangeSelections,
          )
        : _singleRowSubjects(
            span,
            project: roles.project,
            rowSpans: rowSpans,
            folders: folders,
          );
    if (subjects == null) {
      return null;
    }
    return FrameRangeMoveDrag._(
      roles: roles,
      selectionBefore: span,
      trackSelectionBefore: null,
      grabLayerId: grabLayerId ?? span.layerId,
      singleRow: subjects.singleRow,
      multiSources: subjects.multiSources,
      cameraKeys: multiSource ? keys.camera : null,
      instructionSources: multiSource && keys.instructionSources.isNotEmpty
          ? keys.instructionSources
          : null,
    );
  }

  /// The frame-axis slide's subjects (UI-R18 #1) for a multi-layer span,
  /// an SE row or a span carrying KEY sources: every eligible row's COMMIT
  /// form becomes a source, planned with the same delta as one rigid
  /// group.
  static _MoveSubjects? _multiSourceSubjects(
    TimelineFrameRangeSelection span,
    KeySources keys, {
    required SessionInternals internals,
    required FoldersAndAttachments folders,
    required RangeSelections rangeSelections,
  }) {
    final sources = <({Layer commit, int offset})>[];
    for (final row in rangeSelections.retimableSpanRows(span)) {
      // A DIRECTION row rides as a key source ([_castKeySources]) — its
      // spans are its blocks (R27) and they shift there, as they always
      // did. Planning its blocks here as well would move them twice.
      if (row.commit.kind.spansRideBlocks) {
        continue;
      }
      final hasBlock = drawingBlocks(row.display.timeline).any(
        (block) =>
            _wholeBlockIn(block, span.startIndex, span.endIndexExclusive),
      );
      if (hasBlock) {
        sources.add((
          commit: row.commit,
          offset: _commitOffsetFor(
            row.id,
            span.startIndex,
            onTrackAxis: false,
            internals: internals,
          ),
        ));
      }
    }
    if (sources.isEmpty &&
        keys.camera == null &&
        keys.instructionSources.isEmpty) {
      // An all-synced span dies here — say why at the cursor, like the
      // single-row path does.
      folders.noticeSyncedAttachRefusal(span.layerId);
      return null;
    }
    return (singleRow: null, multiSources: sources);
  }

  /// The single-row move's subject: the row's first whole block inside the
  /// selection anchors the group; nothing but empty cells means nothing
  /// to move.
  static _MoveSubjects? _singleRowSubjects(
    TimelineFrameRangeSelection span, {
    required ProjectAccess project,
    required RowSpans rowSpans,
    required FoldersAndAttachments folders,
  }) {
    // A SYNCED attach row's blocks are borrowed exposures — the move
    // refuses with the "edit the owner" pill (the synced-block UI made
    // the row look grabbable; before it, the all-ghost timeline fell out
    // of the block scan below on its own). A SINGLE-CEL (image) row's
    // covering block is immovable — the normalization would revert it.
    if (folders.isSyncedAttachedLayerId(span.layerId)) {
      folders.noticeSyncedAttachRefusal(span.layerId);
      return null;
    }
    if (rowSpans.isSingleCelLayerId(span.layerId)) {
      return null;
    }
    final layer = project.layerById(span.layerId);
    if (layer == null) {
      return null;
    }
    for (final block in drawingBlocks(layer.timeline)) {
      if (_wholeBlockIn(block, span.startIndex, span.endIndexExclusive)) {
        return (
          singleRow: (layer: layer, groupStart: block.startIndex),
          multiSources: null,
        );
      }
    }
    return null; // Nothing but empty cells selected — nothing to move.
  }

  final TrackSeDisplay _trackSe;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final ActiveCutControllers _controllers;
  final SessionInternals _internals;
  final DrawingBlockMoveDragVerbs _blockMove;
  final RenderCaches _renderCaches;
  final Camera _camera;
  final Transitions _transitions;

  /// The move's subject span as it stood at drag start, stated in the axis
  /// its sources commit in (see [_liveSpan]). ⛔Non-null by construction:
  /// a drag with no span is not a drag, so the factory answers null
  /// instead of building one.
  final TimelineFrameRangeSelection _selectionBefore;

  /// The TRACK-axis selection as it stood at drag start, and — because it
  /// is only ever captured on that rail — the ANSWER to which axis this
  /// drag is on ([_onTrackAxis]).
  ///
  /// 🚨One field, because they are one fact: the drag is on the track axis
  /// BECAUSE it was begun from a track selection, and that selection is
  /// this capture. A separate bool could disagree with it, and did — the
  /// old flag was set before the begin could refuse, so a refused track
  /// begin left the next cut-local press reading the wrong rail until
  /// something reset it.
  ///
  /// The setter reads the track id and the non-layer rows from here,
  /// because the machine's layer-stated span cannot carry them and the
  /// LIVE value is the very thing the setter is overwriting.
  final TrackFrameRangeSelection? _trackSelectionBefore;

  bool get _onTrackAxis => _trackSelectionBefore != null;

  /// R27 #8: the row the move drag GRABBED — the hop origin. The
  /// selection's anchor row is a different thing (selecting upward makes
  /// them differ), and using it made "this block lands on that row" come
  /// out shifted by however far the two were apart.
  final LayerId? _grabLayerId;

  /// The single-row subject: the row as it stood, and the start of the
  /// block that anchors the group. ⛔ONE field for the pair — they are
  /// set together and read together, and two nullables let "a row with no
  /// group" be written down.
  final ({Layer layer, int groupStart})? _singleRow;

  /// Cross-layer selections (UI-R18 #1): every spanned layer's drag-start
  /// snapshot in COMMIT form (+ the display→commit index offset for
  /// track-SE rows); the move slides them together along the FRAME axis
  /// (row changes stay single-layer anim-only — the kind guard would make
  /// partial rect drops ambiguous).
  ///
  /// ⚠️EXACTLY one of this and [_singleRow] is set — which one decided
  /// the whole shape of the step at begin, and no step may switch rails.
  final List<({Layer commit, int offset})>? _multiSources;

  /// KEY sources riding the range move (P3b-2, #2 second half): the
  /// camera row's keyframe snapshot WITH the row's id — their keys shift
  /// with the same delta the blocks slide.
  ///
  /// ⛔ONE field for the pair: the snapshot is meaningless without the row
  /// it came from, and the preview's marker layer used to reach for the id
  /// with a `!` because two fields could not say so.
  final ({Map<int, CameraPose> before, LayerId layerId})? _cameraKeys;

  final List<Layer>? _instructionSources;

  DrawingBlockMovePlan? _plan;

  List<DrawingBlockMovePlan>? _multiPlans;

  /// The in-flight MULTI-ROW range move (UI-R23 #9): a multi-layer drawing
  /// selection dragged onto a different row shifts every selected row
  /// rigidly. Set only while a valid rigid landing is previewed; an illegal
  /// step leaves the last valid plan in place (UI-R23 #10).
  MultiRowRangeMovePlan? _multiRowPlan;

  Map<int, CameraPose>? _cameraShifted;

  Map<LayerId, Map<int, InstructionEvent>>? _instructionShifted;

  /// The DIRECTION riders' shifted rows (R27), committed as their timeline
  /// writes beside [_instructionShifted].
  Map<LayerId, Layer>? _directionShifted;

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
  _seRowChange;

  /// The SE rows riding a MULTI-ROW rigid move (R26 #2): a span that also
  /// covers a track-SE row moves that row's blocks by the same row delta
  /// within the SE lattice — "if a block is movable, it moves no matter
  /// how many rows you select" applies to SE rows too.
  List<SeRowMovePair>? _multiSeRowChanges;

  /// A direction→direction ROW-CHANGE drop in flight (P3b-4): the drawing
  /// rows' cross-layer plan, because the spans are the blocks (R27), and
  /// the row it leaves — committed the block move's own way.
  ({DrawingBlockMovePlan plan, Layer source})? _directionRowChange;

  /// THE selection this move reads and publishes, in the axis its sources
  /// are keyed by. Every step of the drag writes through here instead of
  /// touching a notifier directly, so the machine never has to know which
  /// object owns it.
  TimelineFrameRangeSelection? get _liveSpan => _onTrackAxis
      ? _spanOfTrackSelection(_selection.trackFrameRangeSelection.value)
      : _selection.frameRangeSelection.value;

  set _liveSpan(TimelineFrameRangeSelection? span) {
    final before = _trackSelectionBefore;
    if (before == null) {
      _selection.frameRangeSelection.value = span;
      return;
    }
    if (span == null) {
      _selection.trackFrameRangeSelection.value = null;
      return;
    }
    // The axis's own facts ride from the drag-start capture: the anchor
    // names its OWN track (the select path's law — re-keying to
    // [SelectionAccess.selectedTrackId] here hid the band for the whole
    // drag on any other track and left the landed selection keyed to the
    // wrong one), and a non-layer row in a mixed span is not something
    // the layer-stated span can re-derive.
    _selection.trackFrameRangeSelection.value = TrackFrameRangeSelection(
      trackId: before.trackId,
      anchorRow: LayerRowAddress(span.layerId),
      rows: [
        for (final id in span.spanLayerIds) LayerRowAddress(id),
        for (final row in before.rows)
          if (row is! LayerRowAddress) row,
      ],
      startFrame: span.startIndex,
      endFrameExclusive: span.endIndexExclusive,
    );
  }

  int _commitOffset(LayerId layerId, int spanStart) => _commitOffsetFor(
    layerId,
    spanStart,
    onTrackAxis: _onTrackAxis,
    internals: _internals,
  );

  /// A ROW-CHANGE drag step (P3b-4): returns true when it OWNED the step
  /// — either a planned SE→SE / instruction→instruction landing (preview
  /// published) or an owned-but-illegal hover (preview cleared). False
  /// falls through to the plain frame-axis slide.
  bool _updateRowChange(int frameDelta, LayerId targetLayerId) {
    final selection = _selectionBefore;
    void keepLastValid() {
      // UI-R23 #10: a blocked / incompatible landing KEEPS the last valid
      // preview and outline — the move "stops at the last legal spot" and
      // resumes when a legal row returns, uniform across every source kind
      // (the R22-B snap-back-to-origin is retired). Nothing to mutate: the
      // stored last-valid plan and the live preview stand.
    }

    void followOutline() {
      _multiPlans = null;
      _cameraShifted = null;
      _instructionShifted = null;
      _directionShifted = null;
      _camera.showCameraKeysDragPreview(null);
      _slideSelectionOutline(
        selection,
        landedLayerId: targetLayerId,
        shift: frameDelta,
      );
    }

    final sourceIsSe = _project.isTrackSeLayerId(selection.layerId);
    if (sourceIsSe && _project.isTrackSeLayerId(targetLayerId)) {
      final sourceGlobal = _project.trackSeGlobalLayerById(selection.layerId);
      final targetGlobal = _project.trackSeGlobalLayerById(targetLayerId);
      if (sourceGlobal == null || targetGlobal == null) {
        keepLastValid();
        return true;
      }
      final offset = _commitOffset(selection.layerId, selection.startIndex);
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
      _seRowChange = (
        sourceId: selection.layerId,
        targetId: targetLayerId,
        sourceBefore: sourceGlobal,
        sourceAfter: plan.sourceAfter,
        targetBefore: targetGlobal,
        targetAfter: plan.targetAfter,
      );
      // C2: the plans ARE the global forms — the storyboard strips follow
      // the cross-row drop live through the same one gate.
      final sourceForms = _trackSe.previewFormsOf(plan.sourceAfter);
      final targetForms = _trackSe.previewFormsOf(plan.targetAfter);
      _internals.dragPreview.value = BlockMoveDragPreview(
        previewLayers: {
          selection.layerId: sourceForms.shown,
          targetLayerId: targetForms.shown,
        },
        previewGlobalLayers: {
          selection.layerId: ?sourceForms.global,
          targetLayerId: ?targetForms.global,
        },
      );
      followOutline();
      return true;
    }
    final sourceLayer = _project.layerById(selection.layerId);
    final targetLayer = _project.layerById(targetLayerId);
    final sourceIsInstruction = sourceLayer?.kind == LayerKind.instruction;
    if (sourceIsInstruction && targetLayer?.kind == LayerKind.instruction) {
      // A direction row's spans are its blocks (R27): a drop on a sibling
      // direction row is the drawing rows' own cross-layer move — the
      // drawings travel with their spans, and their brush frames re-key.
      final plan = planDrawingRangeMove(
        source: sourceLayer!,
        target: targetLayer!,
        rangeStartIndex: selection.startIndex,
        rangeEndIndexExclusive: selection.endIndexExclusive,
        frameDelta: frameDelta,
        sourceBank: _controllers.timelineController.bankLanesOf(
          sourceLayer.id,
        ),
        cutFrameCount: _project.activeCutFrameCount,
      );
      if (plan == null) {
        keepLastValid();
        return true;
      }
      _directionRowChange = (plan: plan, source: sourceLayer);
      final frames = _project.activeCutFrameCount;
      _internals.dragPreview.value = BlockMoveDragPreview(
        previewLayers: {
          selection.layerId: rederiveRunBehaviors(
            plan.sourceAfter,
            cutFrameCount: frames,
          ),
          targetLayerId: rederiveRunBehaviors(
            plan.targetAfter!,
            cutFrameCount: frames,
          ),
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

  /// The instruction riders' commit commands — ONE two-armed projection
  /// for BOTH the plain-slide and the rigid commit branches (C1/C④). The
  /// TRANSITION row's shifted spans land through the row's own
  /// track-owned writer (the edge drags' command): it has no cut to be
  /// addressed by, so no cut gate may ever swallow it. (A cut's DIRECTION
  /// row is not here — its spans are its blocks and ride as blocks, R27.)
  List<Command> _instructionShiftCommands(
    Map<LayerId, Map<int, InstructionEvent>> instructionShifted,
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
        ),
  ];

  /// A MULTI-ROW range move step (UI-R23 #9): a multi-layer DRAWING
  /// selection dragged onto a different row shifts every selected row
  /// rigidly by the same row + frame delta. Returns true when it OWNS the
  /// step — a valid rigid landing (preview published) or an illegal one
  /// that HOLDS the last valid preview (UI-R23 #10). Returns false (falls
  /// through to the plain frame slide) for same-row steps or spans whose
  /// NON-drawing rows carry content in range (keys ride the frame axis
  /// only). Empty rows of any kind never block (UI-R24 #3: only the
  /// frames inside the selection move).
  bool _updateMultiRow(int frameDelta, LayerId targetLayerId) {
    final selection = _selectionBefore;
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
    _publishMultiRowMovePreview(landing.plan, landing.sePlans, riders);
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
    _slideSelectionOutline(
      selection,
      landedLayerId: targetLayerId,
      shift: frameDelta,
      layerIds: landedLayerIds,
    );
  }

  /// The selection outline follows the previewed landing live.
  ///
  /// The `newStart >= 0` clamp is the whole reason this is one function:
  /// four copies spelled it, and it is precisely the rung that goes
  /// missing from one of them later.
  void _slideSelectionOutline(
    TimelineFrameRangeSelection selection, {
    required LayerId landedLayerId,
    required int shift,
    List<LayerId> layerIds = const [],
  }) {
    final newStart = selection.startIndex + shift;
    if (newStart < 0) {
      return;
    }
    _liveSpan = TimelineFrameRangeSelection(
      layerId: landedLayerId,
      startIndex: newStart,
      endIndexExclusive: selection.endIndexExclusive + shift,
      layerIds: layerIds,
    );
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
    // begin ([_cameraKeys] and [_instructionSources], the same answers
    // the plain slide consumes). Re-deriving them here is the copy that
    // silently dropped the TRANSITION on rigid steps (C④): its clone's
    // kind matched no arm, so the spans snapped home the moment the
    // pointer crossed a row.
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
    final displayDelta = layerIndexDelta(
      lattices.rows,
      _grabLayerId ?? step.selection.layerId,
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
        bankOf: _controllers.timelineController.bankLanesOf,
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
    final cameraKeys = _cameraKeys;
    Map<int, CameraPose>? cameraShifted;
    if (cameraKeys != null) {
      cameraShifted = shiftCameraKeysInRange(
        keyframes: cameraKeys.before,
        rangeStartIndex: selection.startIndex,
        rangeEndIndexExclusive: selection.endIndexExclusive,
        frameDelta: frameDelta,
      );
      if (cameraShifted == null) {
        return null;
      }
    }
    final instructionShifted = <LayerId, Map<int, InstructionEvent>>{};
    final directionShifted = <LayerId, Layer>{};
    for (final layer in _instructionSources ?? const <Layer>[]) {
      if (layer.kind.spansRideBlocks) {
        // A direction row's spans are its blocks (R27): they ride as the
        // drawing rows' own slide, drawings and all.
        final plan = planDrawingRangeMove(
          source: layer,
          target: layer,
          rangeStartIndex: selection.startIndex,
          rangeEndIndexExclusive: selection.endIndexExclusive,
          frameDelta: frameDelta,
          sourceBank: _controllers.timelineController.bankLanesOf(layer.id),
          cutFrameCount: _project.activeCutFrameCount,
        );
        if (plan == null) {
          return null;
        }
        directionShifted[layer.id] = plan.sourceAfter;
        continue;
      }
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
    return (
      camera: cameraShifted,
      instructions: instructionShifted,
      directions: directionShifted,
    );
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
    FrameAxisRiders riders,
  ) {
    final cameraShifted = riders.camera;
    final instructionShifted = riders.instructions;
    _multiRowPlan = plan;
    _multiSeRowChanges = sePlans.isEmpty ? null : sePlans;
    _multiPlans = null;
    _seRowChange = null;
    _directionRowChange = null;
    _cameraShifted = cameraShifted;
    _instructionShifted = instructionShifted.isEmpty
        ? null
        : instructionShifted;
    _directionShifted = riders.directions.isEmpty ? null : riders.directions;
    _camera.showCameraKeysDragPreview(cameraShifted);
    final sePreviews = {
      for (final se in sePlans) ...{
        se.sourceId: _trackSe.previewFormsOf(se.sourceAfter),
        se.targetId: _trackSe.previewFormsOf(se.targetAfter),
      },
      ..._transitionPreviewForms(instructionShifted),
    };
    _internals.dragPreview.value = BlockMoveDragPreview(
      previewLayers: {
        if (plan != null)
          for (final entry in plan.layersAfter.entries)
            entry.key: rederiveRunBehaviors(
              entry.value,
              cutFrameCount: _project.activeCutFrameCount,
            ),
        for (final entry in sePreviews.entries) entry.key: entry.value.shown,
        // R27 #8: the frame-axis riders preview in place — a DIRECTION row
        // as the row its shifted blocks make (its spans are its blocks).
        // A riding TRANSITION is in [sePreviews] above, in the SE rows'
        // two forms.
        for (final entry in riders.directions.entries)
          entry.key: rederiveRunBehaviors(
            entry.value,
            cutFrameCount: _project.activeCutFrameCount,
          ),
      },
      // C2: the SE passengers' global forms, for the storyboard strips.
      previewGlobalLayers: {
        for (final entry in sePreviews.entries) entry.key: ?entry.value.global,
      },
      cameraCutId: cameraShifted == null ? null : _project.activeCutOrNull?.id,
      cameraKeyframes: cameraShifted,
      // A FRESH CLONE per step (the P3b-2 contract) — the gate compares
      // identities, and the repository instance trips nothing (B4-①: the
      // multi-row rigid path was the one place still handing it over raw,
      // so a union drag spanning rows froze the camera's markers).
      cameraMarkerLayer: _cameraMarkerLayer(cameraShifted),
    );
  }

  /// The camera row's marker clone for a step that shifted [cameraShifted]
  /// — null when no camera rides.
  Layer? _cameraMarkerLayer(Map<int, CameraPose>? cameraShifted) {
    final cameraKeys = _cameraKeys;
    if (cameraShifted == null || cameraKeys == null) {
      return null;
    }
    return _project.layerById(cameraKeys.layerId)?.copyWith();
  }

  /// Plans the SE passengers of a multi-row rigid move (R26 #2): every
  /// track-SE row in [seSourceIds] shifts [rowDelta] rows inside the SE
  /// lattice, carrying its selected blocks (and their audio clips, which
  /// anchor to the cels). Null when ANY passenger cannot land — the whole
  /// move voids, the multi-row all-or-nothing rule.
  List<SeRowMovePair>? _planMultiRowSePassengers({
    required List<LayerId> seSourceIds,
    required List<Layer> seLattice,
    required int frameDelta,
    required int rowDelta,
  }) {
    final selection = _selectionBefore;
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
      final offset = _commitOffset(sourceId, selection.startIndex);
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
  void _resetPreviewToOrigin() {
    _plan = null;
    _multiPlans = null;
    _seRowChange = null;
    _directionRowChange = null;
    _multiRowPlan = null;
    _multiSeRowChanges = null;
    _cameraShifted = null;
    _instructionShifted = null;
    _directionShifted = null;
    _dropPreviewChannels();
    _liveSpan = _selectionBefore;
  }

  /// Clears every channel this drag publishes to. They live OUTSIDE the
  /// drag (on the session and its collaborators), so dropping the object
  /// does not clear them — this is the one piece of forgetting the object
  /// cannot do by dying.
  void _dropPreviewChannels() {
    _camera.showCameraKeysDragPreview(null);
    _internals.dragPreview.value = null;
  }

  /// A range-moved TRANSITION row's in-flight forms, in the track-SE rows'
  /// shape ([Transitions.previewFormsOf]): the row projected onto the active
  /// cut for the cut's rows, the row itself for the storyboard's strip — so
  /// it rides the step's one preview beside the SE passengers.
  ///
  /// ↩️C1 (2026-08-17) gave it a channel of its own ("one preview channel
  /// per row family"), off this one because a global-keyed entry here would
  /// have leaked into the cut's projection. The cut form answers that the
  /// way it answers it for the SE rows (유저 2026-09-25: 「se블록이랑 똑같이
  /// 글로벌이 주인인 상태랑 똑같지않나? 그거 그대로 법 통일해서 적용해도
  /// 문제되나?」).
  Map<LayerId, ({Layer shown, Layer? global})> _transitionPreviewForms(
    Map<LayerId, Map<int, InstructionEvent>> instructionShifted,
  ) => {
    for (final entry in instructionShifted.entries)
      if (_transitions.trackTransitionOwner(entry.key) case final owner?)
        entry.key: _transitions.previewFormsOf(
          owner.transitionLayer.copyWith(
            instructions: SplayTreeMap<int, InstructionEvent>.from(entry.value),
          ),
        ),
  };

  /// A range-move drag step: live preview on
  /// [SessionInternals.dragPreview] (repository untouched), the selection
  /// outline riding the previewed landing.
  void update({required int frameDelta, LayerId? targetLayerId}) {
    final selection = _selectionBefore;
    // R28 #5: back at the start = the origin, not a refusal. A row change
    // still owns the step (a delta-0 drop onto a sibling row is a real
    // move), so only same-row zero deltas reset.
    if (frameDelta == 0 &&
        (targetLayerId == null ||
            targetLayerId == selection.layerId ||
            targetLayerId == _grabLayerId)) {
      _resetPreviewToOrigin();
      return;
    }
    final multiSources = _multiSources;
    if (multiSources != null) {
      // ROW-CHANGE drops within the SE / camera sections (P3b-4, 같은
      // 섹션 행이동): a single-row track-SE selection may land on a
      // sibling SE row, an instruction selection on a sibling
      // instruction row — the handler owns the step then (an incompatible
      // hover HOLDS the last valid landing, UI-R23 #10).
      _updateMultiSource(targetLayerId, frameDelta, multiSources);
      return;
    }

    final singleRow = _singleRow;
    if (singleRow == null) {
      return;
    }
    final source = singleRow.layer;
    final target = _singleRowMoveTarget(source, targetLayerId);
    final plan = target == null
        ? null
        : planDrawingRangeMove(
            source: source,
            target: target,
            rangeStartIndex: selection.startIndex,
            rangeEndIndexExclusive: selection.endIndexExclusive,
            frameDelta: frameDelta,
            sourceBank: _controllers.timelineController.bankLanesOf(source.id),
            cutFrameCount: _project.activeCutFrameCount,
          );
    if (plan == null) {
      // UI-R23 #10: a blocked / incompatible landing HOLDS the last valid
      // preview, outline and plan — the move stops at the last legal spot
      // and resumes on a legal return (no snap-back to the origin).
      return;
    }
    _publishSingleRowMove(plan, source, singleRow.groupStart);
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
    Layer source,
    int groupStart,
  ) {
    _plan = plan;
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
    _slideSelectionOutline(
      _selectionBefore,
      landedLayerId: plan.isCrossLayer ? plan.targetAfter!.id : source.id,
      shift: plan.destinationStartIndex - groupStart,
    );
  }

  void _updateMultiSource(
    LayerId? targetLayerId,
    int frameDelta,
    List<({Layer commit, int offset})> multiSources,
  ) {
    final selection = _selectionBefore;
    if (targetLayerId != null &&
        targetLayerId != selection.layerId &&
        selection.spanLayerIds.length == 1 &&
        _updateRowChange(frameDelta, targetLayerId)) {
      return;
    }
    // MULTI-ROW rigid move (UI-R23 #9): a multi-layer drawing selection
    // dragged onto a different row carries every selected row together.
    if (targetLayerId != null &&
        selection.spanLayerIds.length > 1 &&
        _updateMultiRow(frameDelta, targetLayerId)) {
      return;
    }
    // Falling to the plain slide: any prior row-change / multi-row plan
    // is stale now (the slide, not the row change, is last valid).
    _seRowChange = null;
    _directionRowChange = null;
    _multiRowPlan = null;
    _multiSeRowChanges = null;
    // …and the rigid step's RIDER shifts die WITH its plans: a stale
    // shift surviving here commits alone when the slide step holds —
    // the rigid group torn in one silent undo step (transition spans
    // moving while the blocks stay home). A valid slide step re-derives
    // them fresh below.
    _cameraShifted = null;
    _instructionShifted = null;
    _directionShifted = null;
    final plans = _planSlide(multiSources, selection, frameDelta);
    final riders = plans == null
        ? null
        : _shiftFrameAxisRiders(selection, frameDelta);
    if (plans == null || riders == null) {
      // UI-R23 #10: a blocked landing HOLDS the last valid preview,
      // outline and stored plans — no snap-back to the origin.
      return;
    }
    final instructionShifted = riders.instructions;
    _multiPlans = plans.isEmpty ? null : plans;
    _cameraShifted = riders.camera;
    _instructionShifted = instructionShifted.isEmpty
        ? null
        : instructionShifted;
    _directionShifted = riders.directions.isEmpty ? null : riders.directions;
    _publishSlidePreview(plans, riders);
    _slideSelectionOutline(
      selection,
      landedLayerId: selection.layerId,
      shift: frameDelta,
      layerIds: selection.layerIds,
    );
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
        sourceBank: _controllers.timelineController.bankLanesOf(
          source.commit.id,
        ),
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
  /// the track-SE rows), the shifted instruction rows and a riding
  /// transition in the same two forms, and the camera keys on their own
  /// channel.
  void _publishSlidePreview(
    List<DrawingBlockMovePlan> plans,
    FrameAxisRiders riders,
  ) {
    final cameraShifted = riders.camera;
    final instructionShifted = riders.instructions;
    _camera.showCameraKeysDragPreview(cameraShifted);
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
      final forms = _trackSe.previewFormsOf(commitForm);
      previewLayers[commitForm.id] = forms.shown;
      final global = forms.global;
      if (global != null) {
        previewGlobalLayers[commitForm.id] = global;
      }
    }
    // A DIRECTION row previews as the row its shifted blocks make — its
    // spans are its blocks (R27), so the cells row reads them there.
    for (final entry in riders.directions.entries) {
      previewLayers[entry.key] = rederiveRunBehaviors(
        entry.value,
        cutFrameCount: _project.activeCutFrameCount,
      );
    }
    for (final entry in _transitionPreviewForms(instructionShifted).entries) {
      previewLayers[entry.key] = entry.value.shown;
      final global = entry.value.global;
      if (global != null) {
        previewGlobalLayers[entry.key] = global;
      }
    }
    _internals.dragPreview.value = BlockMoveDragPreview(
      previewLayers: previewLayers,
      previewGlobalLayers: previewGlobalLayers,
      cameraCutId: cameraShifted == null ? null : _project.activeCutOrNull?.id,
      cameraKeyframes: cameraShifted,
      cameraMarkerLayer: _cameraMarkerLayer(cameraShifted),
    );
  }

  /// Commits the range move as ONE undo step (layer updates + the brush
  /// re-key on cross-layer carries), mirroring the block-move commit.
  ///
  /// ⛔The caller has already dropped this object — there is nothing to
  /// forget but the preview channels, which is why the old "clear every
  /// field" list is gone.
  void commit() {
    final landedSelection = _liveSpan;
    _dropPreviewChannels();
    // ROW-CHANGE commits (P3b-4): the planned pair replaces both rows in
    // one composite undo; the selection follows the landing row.
    if (_seRowChange != null) {
      _commitSeRowMove(_seRowChange!, landedSelection);
      return;
    }
    if (_directionRowChange case final change?) {
      _commitDirectionRowMove(change, landedSelection);
      return;
    }
    if (_multiRowPlan != null || _multiSeRowChanges != null) {
      // MULTI-ROW rigid move commit (UI-R23 #9): every affected drawing row
      // rewrites in one composite undo, and each cross-row cel re-keys its
      // brush frame to the target row. Track-SE passengers (R26 #2) join
      // the SAME undo step through their global-form layer pair.
      _commitMultiRowMove(landedSelection);
      return;
    }
    final multiSources = _multiSources;
    if (multiSources != null) {
      // Cross-layer slide commit (UI-R18 #1) + key shifts (P3b-2): one
      // composite undo across blocks, camera keys and instruction spans.
      // (UI-R23 #3: the layer transform track no longer rides the slide.)
      _commitMultiSourceMove(multiSources, landedSelection);
      return;
    }
    final singleRow = _singleRow;
    final plan = _plan;
    if (singleRow == null) {
      return;
    }
    if (plan == null) {
      _liveSpan = _selectionBefore;
      return;
    }
    _project.historyManager.execute(
      _blockMove.singleRowMoveCommand(
        plan,
        source: singleRow.layer,
        description: 'Move frame range',
      ),
    );
    // The selection stays on the moved frames where they landed.
    _liveSpan = landedSelection;
    if (plan.isCrossLayer) {
      _controllers.layerController.selectLayer(plan.targetAfter!.id);
    }
    _changes.warmActiveCut();
    _changes.notifyChanged();
  }

  void _commitMultiSourceMove(
    List<({Layer commit, int offset})> multiSources,
    TimelineFrameRangeSelection? landedSelection,
  ) {
    final cut = _project.activeCutOrNull;
    final multiPlans = _multiPlans;
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
      ..._riderCommands(cut),
    ];
    if (!_commitRangeMoveCommands(commands, landedSelection)) {
      return;
    }
    _changes.warmActiveCut();
    _changes.notifyChanged();
  }

  /// R27 #8: the frame-axis riders (camera keys, instruction spans)
  /// land in the SAME undo step as the rigid row move — through the
  /// ONE two-armed projection the plain slide commits with, so a
  /// riding TRANSITION lands too (C④: this branch used to carry a
  /// cut-gated copy with the transition arm missing).
  List<Command> _riderCommands(Cut? cut) {
    final instructionShifted = _instructionShifted;
    final directionShifted = _directionShifted;
    final cameraShifted = _cameraShifted;
    return [
      if (instructionShifted != null)
        ..._instructionShiftCommands(instructionShifted),
      // A DIRECTION rider lands as the timeline write any block move makes
      // — its spans are its blocks (R27).
      if (directionShifted != null)
        for (final MapEntry(key: id, value: after) in directionShifted.entries)
          if (_project.commitLayerById(id) case final before?)
            UpdateLayerTimelineCommand(
              repository: _project.repository,
              before: before,
              after: rederiveRunBehaviors(
                after,
                cutFrameCount: _project.activeCutFrameCount,
              ),
            ),
      if (cameraShifted != null && cut != null)
        UpdateCutCameraCommand(
          repository: _project.repository,
          cutId: cut.id,
          camera: CutCamera(keyframes: cameraShifted),
          description: 'Move camera keys',
        ),
    ];
  }

  /// Executes a range move's [commands] as ONE undo step and leaves the
  /// selection on the frames where they landed. False when there was
  /// nothing to commit — the selection goes back to where the drag
  /// started and the caller stops.
  bool _commitRangeMoveCommands(
    List<Command> commands,
    TimelineFrameRangeSelection? landedSelection,
  ) {
    if (commands.isEmpty) {
      _liveSpan = _selectionBefore;
      return false;
    }
    _project.historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(
              description: 'Move frame range',
              commands: commands,
            ),
    );
    _liveSpan = landedSelection;
    return true;
  }

  void _commitMultiRowMove(TimelineFrameRangeSelection? landedSelection) {
    final cut = _project.activeCutOrNull;
    final multiRowPlan = _multiRowPlan;
    final commands = <Command>[];
    commands.addAll(_seRowMoveCommands(_multiSeRowChanges));
    commands.addAll(_multiRowLayerCommands(multiRowPlan));
    commands.addAll(_riderCommands(cut));
    if (cut != null && (multiRowPlan?.rekeys.isNotEmpty ?? false)) {
      commands.add(
        RekeyBrushFramesCommand(
          store: _renderCaches.brushFrameStore,
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
    if (!_commitRangeMoveCommands(commands, landedSelection)) {
      return;
    }
    if (landedSelection != null) {
      _controllers.layerController.selectLayer(landedSelection.layerId);
    }
    _changes.warmActiveCut();
    _changes.notifyChanged();
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

  /// A direction→direction drop lands as the block move it is: both rows
  /// and the brush re-key of every carried cel in ONE undo step
  /// ([DrawingBlockMoveDragVerbs.singleRowMoveCommand]).
  void _commitDirectionRowMove(
    ({DrawingBlockMovePlan plan, Layer source}) change,
    TimelineFrameRangeSelection? landedSelection,
  ) {
    _project.historyManager.execute(
      _blockMove.singleRowMoveCommand(
        change.plan,
        source: change.source,
        description: 'Move frame range',
      ),
    );
    _liveSpan = landedSelection;
    _controllers.layerController.selectLayer(change.plan.targetAfter!.id);
    _changes.warmActiveCut();
    _changes.notifyChanged();
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
    _liveSpan = landedSelection;
    _controllers.layerController.selectLayer(seRowChange.targetId);
    _changes.warmActiveCut();
    _changes.notifyChanged();
  }

  /// Drops an in-flight range-move preview, restoring the selection.
  void cancel() {
    _dropPreviewChannels();
    _liveSpan = _selectionBefore;
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
    return layerIndexDelta(lattice, layerId, rows[landingIndex].id);
  }
}
