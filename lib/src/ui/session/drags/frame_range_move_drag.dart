import 'package:flutter/foundation.dart' show ValueNotifier, listEquals;
import 'dart:collection' show SplayTreeMap;

import '../../../models/attach_picture_trade.dart';
import '../../../models/attached_layer_resolve.dart'
    show isSyncedAttachedLayer;
import '../../../models/block_row_swap.dart';
import '../../../models/camera_instruction.dart';
import '../../../models/cel_bank_lanes.dart';
import '../../../models/cel_rekey.dart';
import '../../../models/drawing_block_move.dart';
import '../../../models/frame_id.dart';
import '../../../models/key_range_move.dart';
import '../../../models/layer.dart';
import '../../../models/layer_folder.dart' show LayerFolderIndex;
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
import '../../../services/commands/track_transition_commands.dart';
import '../../../services/commands/update_layer_timeline_command.dart';
import '../../timeline/timeline_drag_preview.dart';
import '../../timeline/timeline_section_policy.dart';
import '../active_cut_controllers.dart';
import '../block_move_commands.dart';
import '../folder_bands.dart' show folderBandsFollowing;
import '../folders_and_attachments.dart';
import '../lane_edit_subject.dart' show LaneEdit;
import '../lane_verbs.dart';
import '../range_selections.dart';
import '../row_spans.dart';
import '../session_roles.dart';
import '../track_se_display.dart';
import '../transition_range_hold.dart';
import '../transitions.dart';
import 'lane_range_move_drag.dart' show laneSpanKeysMovedOn;

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

  /// Stays on its row and keeps no other row from travelling: an empty
  /// row, a row whose keys ride the FRAME delta, a row whose blocks are
  /// not its own to move ([FrameRangeMoveDrag._castRowForHop]).
  staysPut,
}

/// One rigid multi-row drag step's subjects, read once per step.
typedef MultiRowStep = ({
  TimelineFrameRangeSelection selection,
  MultiRowSpanCast cast,
  MultiRowLattices lattices,
});

/// The frame-axis riders shifted with a move: the band's lanes with their
/// keys moved ([LaneRide]), the transition's events by row, and each row
/// riding as BLOCKS as the row its shifted blocks make — a DIRECTION row
/// (R27: its spans are its blocks, so they ride as blocks) and the rows a
/// FOLDER row of the span holds (F-311, [rowsHeldByFolderRowsOf]).
typedef FrameAxisRiders = ({
  List<LaneRide> lanes,
  Map<LayerId, Map<int, InstructionEvent>> instructions,
  Map<LayerId, Layer> blockRiders,
});

/// No rider moves: a PURE row hop (frameDelta 0) leaves every key where
/// it is, so the riders simply hold.
const FrameAxisRiders noRiders = (
  lanes: [],
  instructions: {},
  blockRiders: {},
);

/// A lane the band holds, as a step leaves it: the row the lane verbs
/// resolve ([BandLane]) and its keys moved — landed through that row's own
/// lane commit, which writes each family where it lives.
typedef LaneRide = ({Layer row, LaneEdit edit});

/// A TRANSITION row riding a frame-range move: the GLOBAL row as it stood
/// at begin, and the starts of the spans that move — the ones the
/// selection holds ([TransitionRangeHold.transitionStartsHeldInCut] /
/// [TransitionRangeHold.transitionStartsHeldOnTrack]), which on a cut's
/// rail are not the frames the selection covers.
typedef TransitionRider = ({Layer row, Set<int> starts});

/// The KEY sources a frame-range move carries (P3b-2): the rows that ride
/// as BLOCKS — the DIRECTION rows that own spans in the range, joined at
/// [FrameRangeMoveDrag.begin] by the rows a folder row holds — and the
/// transition rows.
///
/// ↩️`blockRiders` was `instructionSources` while only a direction row rode
/// this way; a folder's rows are no instruction (F-311).
/// ↩️The camera's track rode here too, by a resolver of its own; it is the
/// camera row's transform header, so it rides as the band's lanes do
/// ([LaneVerbs.bandLanesRiding], H20).
typedef KeySources = ({
  List<Layer> blockRiders,
  List<TransitionRider> transitionRiders,
});

/// Whether [block] is a real (non-ghost) block lying WHOLE inside
/// [start, endExclusive) — the one rule every begin uses to decide which
/// rows carry something to move (the cross-layer slide's rule, UI-R18 #1).
bool _wholeBlockIn(TimelineDrawingBlock block, int start, int endExclusive) =>
    !block.entry.ghost &&
    block.startIndex >= start &&
    block.endIndexExclusive <= endExclusive;

/// The row whose SEAT the display row [id] shows — itself, or, for a SYNCED
/// attach row, the base whose blocks it shows.
///
/// 🚨F-276 (유저 2026-10-04): 「프레임 블록은 이동가능한곳이라면 어디든
/// 이동가능. 지금 어태치 싱크레이어를 가진 레이어의 블록을 다른 레이어로
/// 이동하는게 불가능한데 가능하도록」. A mirror row holds no block of its own:
/// every block it shows is its base's, shown again. So a move never reads
/// it as a row — the row GRABBED, the row POINTED AT and the rows a span
/// COVERS all read the base, the way a lane row reads its owning layer
/// (`resolveBlockMoveTargetLayer`). Reading it as a row of its own is what
/// made a base's block unmovable the moment its mirror was in the selection
/// or under the hand: the mirror has no seat to land on, and the rigid hop
/// counted it as one.
LayerId _seatRowOf(ProjectAccess project, LayerId id) =>
    switch (project.layerById(id)) {
      final layer? when isSyncedAttachedLayer(layer) =>
        layer.attachedToLayerId ?? id,
      _ => id,
    };

/// The attach group a span trades pictures in (F-330): the base and its
/// SYNCED rows, in the order the rows show them, and the base's cels the
/// span covers ([picturesTradedInAttachGroup]).
typedef _AttachTrade = ({List<Layer> group, List<FrameId> baseCels});

/// [span]'s [_AttachTrade] — null when its rows are not all of one attach
/// group, or it covers no whole block of the base. Every row of the group
/// shows the base's blocks, so the span covers the same ones on each.
_AttachTrade? _attachTradeOf(
  TimelineFrameRangeSelection span,
  ProjectAccess project,
) {
  final seats = {for (final id in span.spanLayerIds) _seatRowOf(project, id)};
  final base = seats.length == 1 ? project.layerById(seats.single) : null;
  if (base == null) {
    return null;
  }
  final group = [
    for (final layer in sectionedLayerOrder(project.layers))
      if (layer.id == base.id ||
          (isSyncedAttachedLayer(layer) && layer.attachedToLayerId == base.id))
        layer,
  ];
  final baseCels = [
    for (final block in drawingBlocks(base.timeline))
      if (_wholeBlockIn(block, span.startIndex, span.endIndexExclusive))
        block.frameId,
  ];
  return group.length < 2 || baseCels.isEmpty
      ? null
      : (group: group, baseCels: baseCels);
}

/// The display→commit offset a move applies to [layerId]'s span. ZERO on
/// the track axis: the span is already stated in commit keys, and
/// translating it again would address another cut's frames.
int _commitOffsetFor(
  LayerId layerId,
  int spanStart, {
  required bool onTrackAxis,
  required TrackSeDisplay trackSe,
}) => onTrackAxis ? 0 : trackSe.commitBlockStart(layerId, spanStart) - spanStart;

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
///
/// ↩️F-87: the rows it plans are the ones whose BLOCKS were swept
/// ([TimelineRowAddress.blockLayerId]); a lane row holds its keys, never
/// its layer's sounds (유저 H20: 「선택한 곳만 움직이게하라고」). The anchor
/// is the drag's own row when that is one of them, else the first of them.
/// A band whose rows hold no block — the V row's cuts and its lanes — keeps
/// its rows and names the layer of the first lane: its lanes are what a
/// move of it carries ([LaneVerbs.bandLanesRiding]), as the cut's band of
/// lanes alone does.
TimelineFrameRangeSelection? _spanOfTrackSelection(
  TrackFrameRangeSelection? live,
) {
  if (live == null) {
    return null;
  }
  // Deduped in display order: a layer row and its own lane rows are
  // several rows of ONE layer, and the move machine plans per layer.
  final blockIds = [
    ...{for (final row in live.spanRows) ?row.blockLayerId},
  ];
  final anchorLayerId = live.anchorRow.blockLayerId;
  if (blockIds.isEmpty) {
    final lanesOf = [
      for (final row in live.spanRows) ?row.owningLayerId,
    ].firstOrNull;
    return lanesOf == null
        ? null
        : TimelineFrameRangeSelection(
            layerId: lanesOf,
            startIndex: live.startFrame,
            endIndexExclusive: live.endFrameExclusive,
            rows: live.spanRows,
          );
  }
  return TimelineFrameRangeSelection(
    layerId: blockIds.contains(anchorLayerId) ? anchorLayerId! : blockIds.first,
    startIndex: live.startFrame,
    endIndexExclusive: live.endFrameExclusive,
    layerIds: blockIds,
  );
}

/// The rows of [live] that source a move on the track axis — one COMMIT
/// form per owning layer that carries a whole block inside the range —
/// and the transition rows' spans.
({
  List<({Layer commit, int offset})> sources,
  List<TransitionRider> transitionRiders,
})
_castTrackSources(
  TrackFrameRangeSelection live, {
  required ProjectAccess project,
  required Transitions transitions,
}) {
  final sources = <({Layer commit, int offset})>[];
  // 🚨C3-lane-move: keyed by the row's OWNING layer, not by the row's
  // TYPE. A lane row is one of its layer's rows — skipping it here is
  // what made a band anchored on an fx row refuse to move and fall
  // through to a silent re-select. The `seen` set is the other half: a
  // layer row and its own lane rows are several rows of ONE layer, and
  // sourcing that layer twice would plan its slide twice.
  // ↩️F-87: keyed by the layer whose BLOCKS the row holds. A swept lane
  // holds its keys, not its layer's sounds — keyed by the owner, a band
  // over an S row's lane slid sounds nobody swept (H20).
  final seen = <LayerId>{};
  for (final row in live.spanRows) {
    final rowLayerId = row.blockLayerId;
    if (rowLayerId == null || !seen.add(rowLayerId)) {
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
  // C1 (2026-08-17): the TRANSITION row is a movable subject on THIS
  // axis — its spans live global, and this rail is where they are
  // authored. It rides beside the blocks as a cut's direction rows do.
  return (
    sources: sources,
    transitionRiders: _transitionRidersOf(
      transitions.transitionStartsHeldOnTrack(live),
      transitions,
    ),
  );
}

/// The transition rows riding a move, from the spans the selection holds
/// on each — the same hold the range delete takes
/// ([TransitionRangeHold.transitionStartsHeldBy]).
List<TransitionRider> _transitionRidersOf(
  Map<LayerId, Set<int>> held,
  Transitions transitions,
) => [
  for (final MapEntry(key: id, value: starts) in held.entries)
    if (transitions.trackTransitionOwner(id) case final owner?)
      (row: owner.transitionLayer, starts: starts),
];

/// KEY sources (P3b-2, #2 second half): instruction spans inside the
/// selection move with the blocks — same delta, one rigid group. SYNCED
/// attach mirrors stay PASSENGERS (P3b-1): the base's slide carries them
/// by derivation.
KeySources _castKeySources(
  TimelineFrameRangeSelection selection, {
  required ProjectAccess project,
  required Transitions transitions,
}) {
  final blockRiders = <Layer>[];
  bool anyKeyIn(Iterable<int> keys) => keys.any(
    (key) => key >= selection.startIndex && key < selection.endIndexExclusive,
  );
  for (final id in selection.spanLayerIds) {
    final layer = project.layerById(id);
    if (layer == null) {
      continue;
    }
    if (layer.kind == LayerKind.instruction &&
        anyKeyIn(layer.instructions.keys)) {
      blockRiders.add(layer);
    }
    // UI-R23 #3: a frame-range selection NO LONGER carries the layer's
    // own transform keys — frame selection ⊥ transform keys. The
    // transform lanes own their keys through their own lane-scoped
    // selection domain. ↩️H20: they ride where the band swept their lane
    // rows, as rows of their own ([LaneVerbs.bandLanesRiding]) — and the
    // camera's, its row being its transform header.
  }
  // The TRANSITION row rides as the storyboard's does (C1), on the global
  // row, with the spans the selection holds — its marks here are a
  // projection, mapped back to the spans they show, an O.L's left out
  // (transition-row-range-in-the-cut, 유저 2026-09-26).
  //
  // ⚠️A span that began in an EARLIER cut stays where it is: its head is
  // in that cut, which is why its start grip stands down here too
  // ([Transitions.transitionSpillInLeadFrames] — 유저 2026-09-26: 「애초에
  // 넘어온쪽 표시엔 머리그립이 없을텐데」). Its mark is pinned to frame 0,
  // so moving it here would move a head nobody sees move. The storyboard
  // moves it; a range DELETE still takes it, as a press on its mark does.
  final cutStart = project.activeCutGlobalStartFrame;
  final transitionRiders = [
    for (final (:row, :starts) in _transitionRidersOf(
      transitions.transitionStartsHeldInCut(selection),
      transitions,
    ))
      if ({
            for (final start in starts)
              if (start >= cutStart) start,
          }
          case final heads when heads.isNotEmpty)
        (row: row, starts: heads),
  ];
  return (blockRiders: blockRiders, transitionRiders: transitionRiders);
}

/// The rows a FOLDER row of [span] holds, as the riders its block is
/// (F-311, 유저 2026-10-06: 「폴더의 블록 드래그로 이동할 수 있게. 내부
/// 전체적으로 이동하는 느낌」).
///
/// A folder's row stands no block of its own: the band it shows is the
/// blocks its rows make together (`folderAggregateRuns`), so those rows are
/// what a drag on it carries. They ride the way a DIRECTION row's blocks do
/// ([_castKeySources]) — along the frame axis by the span's own delta, and
/// across no row: a folder's row has no row axis to travel.
///
/// A row rides when a retime may touch it
/// ([RangeSelections.retimableSpanRows]) and it stands a whole block in the
/// range — the rule every source of a move is picked by ([_wholeBlockIn]).
/// A row the span covers itself is a source of its own, and is not taken a
/// second time.
List<Layer> rowsHeldByFolderRowsOf(
  TimelineFrameRangeSelection span, {
  required ProjectAccess project,
  required RangeSelections rangeSelections,
}) {
  final folders = LayerFolderIndex(project.layers);
  final held = [
    ...{
      for (final id in span.spanLayerIds)
        for (final row in folders.subtreeMembersOf(id))
          if (!span.coversLayer(row.id)) row.id,
    },
  ];
  if (held.isEmpty) {
    return const [];
  }
  final rows = rangeSelections.retimableSpanRows(
    TimelineFrameRangeSelection(
      layerId: span.layerId,
      startIndex: span.startIndex,
      endIndexExclusive: span.endIndexExclusive,
      layerIds: held,
    ),
  );
  return [
    for (final row in rows)
      if (drawingBlocks(row.display.timeline).any(
        (block) =>
            _wholeBlockIn(block, span.startIndex, span.endIndexExclusive),
      ))
        row.commit,
  ];
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
  RetimeLaw retime,
  ValueNotifier<TimelineDragPreview?> dragPreview,
  BlockMoveCommands blockMove,
  LaneVerbs laneVerbs,
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
    required List<BandLane> laneRiders,
    required List<Layer>? blockRiders,
    required List<TransitionRider> transitionRiders,
    _AttachTrade? attachTrade,
    void Function()? refuseUntraded,
  }) : _project = roles.project,
       _selection = roles.selection,
       _changes = roles.changes,
       _controllers = roles.controllers,
       _retime = roles.retime,
       _dragPreview = roles.dragPreview,
       _blockMove = roles.blockMove,
       _laneVerbs = roles.laneVerbs,
       _transitions = roles.transitions,
       _trackSe = roles.trackSe,
       _selectionBefore = selectionBefore,
       _trackSelectionBefore = trackSelectionBefore,
       _laneTailBefore = trackSelectionBefore == null
           ? roles.selection.laneRangeSelection.value
           : null,
       _grabbedRow = grabLayerId,
       _singleRow = singleRow,
       _multiSources = multiSources,
       _laneRiders = laneRiders,
       _blockRiders = blockRiders,
       _transitionRiders = transitionRiders,
       _attachTrade = attachTrade,
       _refuseUntraded = refuseUntraded;

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
    final (:sources, :transitionRiders) = _castTrackSources(
      live,
      project: roles.project,
      transitions: roles.transitions,
    );
    // H20: the band's lanes ride here as on the cut's axis — and a band
    // that moves no block still moves them.
    final lanes = roles.laneVerbs.bandLanesRiding();
    if (sources.isEmpty && transitionRiders.isEmpty && lanes.isEmpty) {
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
      laneRiders: lanes,
      blockRiders: null,
      transitionRiders: transitionRiders,
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
    final keys = _keySourcesOf(span, roles, rangeSelections);
    final lanes = roles.laneVerbs.bandLanesRiding();
    final singleRowId = _singleRowOf(span, keys, roles.project);
    final multiSource = singleRowId == null;
    final subjects =
        (singleRowId == null
            ? _multiSourceSubjects(
                span,
                keys,
                trackSe: roles.trackSe,
                rangeSelections: rangeSelections,
              )
            : _singleRowSubjects(
                singleRowId,
                span,
                project: roles.project,
                rowSpans: rowSpans,
              )) ??
        // The band moves no block, and its lanes still go: a slide of
        // nothing but them (H20 — each row as it holds).
        (lanes.isEmpty ? null : (singleRow: null, multiSources: []));
    final attachTrade = _attachTradeOf(span, roles.project);
    if (subjects == null) {
      return singleRowId == null
          ? _tradingMirrors(
              roles,
              span,
              attachTrade,
              folders: folders,
              grabLayerId: grabLayerId,
            )
          : null;
    }
    return FrameRangeMoveDrag._(
      roles: roles,
      selectionBefore: span,
      trackSelectionBefore: null,
      grabLayerId: grabLayerId ?? span.layerId,
      singleRow: subjects.singleRow,
      multiSources: subjects.multiSources,
      laneRiders: lanes,
      blockRiders: multiSource && keys.blockRiders.isNotEmpty
          ? keys.blockRiders
          : null,
      transitionRiders: keys.transitionRiders,
      attachTrade: attachTrade,
    );
  }

  /// [span]'s key sources ([_castKeySources]) — and F-311: a folder row of
  /// the span brings the rows it holds, riding beside the direction rows as
  /// the blocks they are.
  static KeySources _keySourcesOf(
    TimelineFrameRangeSelection span,
    FrameRangeMoveRoles roles,
    RangeSelections rangeSelections,
  ) {
    final cast = _castKeySources(
      span,
      project: roles.project,
      transitions: roles.transitions,
    );
    return (
      blockRiders: [
        ...cast.blockRiders,
        ...rowsHeldByFolderRowsOf(
          span,
          project: roles.project,
          rangeSelections: rangeSelections,
        ),
      ],
      transitionRiders: cast.transitionRiders,
    );
  }

  /// The ONE row [span] moves by the single row's law, or null when it moves
  /// as several sources: multi-layer spans, SE rows and KEY sources route
  /// through the frame-axis slide (UI-R18 #1) — per-layer plans on the
  /// COMMIT forms; row-change drops stay the single-anim path.
  ///
  /// 🚨F-276: "multi-layer" is counted in rows of their OWN, and a mirror
  /// is not one ([_seatRowOf]). A base selected together with its mirror is
  /// one row selected twice, so it runs the code a selection of the base
  /// alone runs — the two cannot come to land differently. Mirrors selected
  /// without a base are no row at all, and have no single row either.
  ///
  /// 🚨H20: nor are a band's LANES a source of their own. They ride whichever
  /// path its blocks take ([_lanesShiftedBy]), so a row swept with its lanes
  /// moves its block by the very code the row alone does — selecting more
  /// must not change how the block lands.
  static LayerId? _singleRowOf(
    TimelineFrameRangeSelection span,
    KeySources keys,
    ProjectAccess project,
  ) {
    final ownRows = [
      for (final id in span.spanLayerIds)
        if (_seatRowOf(project, id) == id) id,
    ];
    final carriesKeys =
        keys.blockRiders.isNotEmpty || keys.transitionRiders.isNotEmpty;
    return ownRows.length != 1 ||
            carriesKeys ||
            project.isTrackSeLayerId(ownRows.single)
        ? null
        : ownRows.single;
  }

  /// The frame-axis slide's subjects (UI-R18 #1) for a multi-layer span,
  /// an SE row or a span carrying KEY sources: every eligible row's COMMIT
  /// form becomes a source, planned with the same delta as one rigid
  /// group.
  ///
  /// Null when the span moves nothing — a span of nothing but SYNCED attach
  /// rows among them ([_tradingMirrors]).
  static _MoveSubjects? _multiSourceSubjects(
    TimelineFrameRangeSelection span,
    KeySources keys, {
    required TrackSeDisplay trackSe,
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
            trackSe: trackSe,
          ),
        ));
      }
    }
    if (sources.isEmpty &&
        keys.blockRiders.isEmpty &&
        keys.transitionRiders.isEmpty) {
      return null;
    }
    return (singleRow: null, multiSources: sources);
  }

  /// The drag of a span that moves no block — a span of nothing but SYNCED
  /// attach rows: it trades their pictures inside their group, and nothing
  /// else (F-330, [_picturesTradedTo]). Null where there is no trade to
  /// make.
  ///
  /// Their blocks are borrowed exposures, so a move of them is refused with
  /// the "edit the owner" pill (the synced-block UI made the row look
  /// grabbable; before it, the all-ghost timeline fell out of the block scan
  /// on its own). One mirror or several: this is the one place that says
  /// so — a mirror is no row of its own, so a span of them never takes the
  /// single row's path ([_singleRowOf]), which used to say it too.
  ///
  /// ⚖️Mine, not the user's: the pill came at the press, when nothing could
  /// come of the drag. A trade can, so it comes at the release that traded
  /// nothing ([commit]).
  static FrameRangeMoveDrag? _tradingMirrors(
    FrameRangeMoveRoles roles,
    TimelineFrameRangeSelection span,
    _AttachTrade? attachTrade, {
    required FoldersAndAttachments folders,
    required LayerId? grabLayerId,
  }) {
    if (attachTrade == null) {
      folders.noticeSyncedAttachRefusal(span.layerId);
      return null;
    }
    return FrameRangeMoveDrag._(
      roles: roles,
      selectionBefore: span,
      trackSelectionBefore: null,
      grabLayerId: grabLayerId ?? span.layerId,
      singleRow: null,
      multiSources: const [],
      laneRiders: const [],
      blockRiders: null,
      transitionRiders: const [],
      attachTrade: attachTrade,
      refuseUntraded: () => folders.noticeSyncedAttachRefusal(span.layerId),
    );
  }

  /// The single-row move's subject on [rowId] — the one row of its own
  /// [span] covers ([_singleRowOf]): the row's first whole block inside the
  /// selection anchors the group; nothing but empty cells means nothing
  /// to move.
  static _MoveSubjects? _singleRowSubjects(
    LayerId rowId,
    TimelineFrameRangeSelection span, {
    required ProjectAccess project,
    required RowSpans rowSpans,
  }) {
    // A SINGLE-CEL (image) row's covering block is immovable — the
    // normalization would revert it.
    if (rowSpans.isSingleCelLayerId(rowId)) {
      return null;
    }
    final layer = project.layerById(rowId);
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
  final RetimeLaw _retime;
  final ValueNotifier<TimelineDragPreview?> _dragPreview;
  final BlockMoveCommands _blockMove;
  final LaneVerbs _laneVerbs;
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
  ///
  /// Held as the row the hand is on, mirror or not: a trade of pictures
  /// counts its hop among the rows of an attach group (F-330), where a
  /// mirror is a row.
  final LayerId? _grabbedRow;

  /// The row a step's row hop is measured FROM — and the row a step with no
  /// frame delta has come back to: the row grabbed, or the selection's
  /// anchor for a caller that names none.
  ///
  /// The grabbed row read as its SEAT ([_seatRowOf], F-276): a block
  /// grabbed by its mirror is the base's block, and the hop starts where
  /// that block lives.
  LayerId get _hopOrigin => switch (_grabbedRow) {
    final row? => _seatRowOf(_project, row),
    null => _selectionBefore.layerId,
  };

  /// The row [row] — the span's ONE moving row — lands on while the hand
  /// points at [pointedAt]: carried as far as the hand has moved from the
  /// row it grabbed ([_hopOrigin]). Null when the carry walks off the rows.
  ///
  /// 🚨F-87 (유저 2026-10-18): 「fx를 넘어서 뭐든 선택된 대상으로」 — a
  /// band's lane row holds none of its layer's blocks, so the band can be
  /// grabbed by a row that is not the row it moves. Read as the landing,
  /// the pointed row carried a sideways drag off its row: a hand sliding
  /// along S1's lane took S2's sound up into S1.
  LayerId? _carriedRow(LayerId row, LayerId? pointedAt) {
    if (pointedAt == null || _hopOrigin == row) {
      return pointedAt;
    }
    final rows = _rangeRowOrder();
    final hop = layerIndexDelta(rows, _hopOrigin, pointedAt);
    return hop == null ? null : _rowWalkedTo(rows, row, hop)?.id;
  }

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

  /// The LANES the band swept, riding the move ([LaneVerbs.bandLanesRiding],
  /// H20): each one's keys go the frames its blocks go, on their own lane,
  /// by the lanes' own move ([laneSpanKeysMovedOn]) — the camera row's among
  /// them, its row being its transform header.
  ///
  /// 🗣️F-309 (유저 2026-10-06): 「존재하지 않는 키를 새로 만들어서 이동함.
  /// 떼도 커밋되있음. 멋대로 키를 만들어내지 않도록, 있는 키만 움직이도록
  /// 근본/구조적 해결」. ↩️The camera's keys rode as the POSE FACADE's map —
  /// one whole pose a frame that any lane keys — and landed through
  /// `CutCamera(keyframes:)`, which rebuilds every lane from those poses:
  /// a frame that keyed Position alone came back keyed on Scale and
  /// Rotation too, a hold came back linear and a key's name was gone.
  /// ↩️Then the cut's track rode as it was, shifted by the lanes' law but
  /// resolved, previewed and landed by this drag's own camera code.
  final List<BandLane> _laneRiders;

  /// The lane selection a mixed sweep stood beside the band (R27 #14) — the
  /// same frames, the lanes of the band's own layer — as it was at begin;
  /// null where none stood. It rides the band's frames ([_liveSpan]).
  final TimelineLaneSelection? _laneTailBefore;

  /// The rows riding the move as BLOCKS, as they stood at begin
  /// ([KeySources]): along the frame axis by the move's delta, across no
  /// row.
  final List<Layer>? _blockRiders;

  final List<TransitionRider> _transitionRiders;

  /// The attach group the span trades pictures in on the same frames
  /// (F-330), or null when its rows are not one group's ([_attachTradeOf]).
  final _AttachTrade? _attachTrade;

  /// The "edit the owner" pill a span of nothing but mirrors says when its
  /// release traded nothing ([_tradingMirrors]) — and so the fact that the
  /// span moves no block: non-null exactly for such a span.
  final void Function()? _refuseUntraded;

  DrawingBlockMovePlan? _plan;

  List<DrawingBlockMovePlan>? _multiPlans;

  /// The in-flight MULTI-ROW range move (UI-R23 #9): a multi-layer drawing
  /// selection dragged onto a different row shifts every selected row
  /// rigidly. Set only while a valid rigid landing is previewed; an illegal
  /// step leaves the last valid plan in place (UI-R23 #10).
  MultiRowRangeMovePlan? _multiRowPlan;

  /// The lanes as the last valid step left them ([_publishStep]) — what the
  /// release lands beside its blocks.
  List<LaneRide> _lanesShifted = const [];

  Map<LayerId, Map<int, InstructionEvent>>? _instructionShifted;

  /// The block riders' shifted rows ([_blockRiders] — R27, F-311),
  /// committed as their timeline writes beside [_instructionShifted].
  Map<LayerId, Layer>? _rowsShifted;

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
  MultiRowRangeMovePlan? _multiSeRowPlan;

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
      _selection.frameRangeSelection.value = span == null
          ? null
          : _withSweptRows(span);
      _rideLaneTail(span);
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
    // wrong one), and the band's non-layer rows ([_rowsLanded]).
    _selection.trackFrameRangeSelection.value = TrackFrameRangeSelection(
      trackId: before.trackId,
      anchorRow: LayerRowAddress(span.layerId),
      rows: _rowsLanded(span, before.rows),
      startFrame: span.startIndex,
      endFrameExclusive: span.endIndexExclusive,
    );
  }

  /// The rows [span] lands on: its layer rows, and every other row the band
  /// was swept over ([swept]) — a non-layer row in a mixed span is not
  /// something the layer-stated span can re-derive, and a lane's keys go the
  /// frames on their own row (H20), so the row stays in the band.
  static List<TimelineRowAddress> _rowsLanded(
    TimelineFrameRangeSelection span,
    List<TimelineRowAddress> swept,
  ) => [
    for (final id in span.spanLayerIds) LayerRowAddress(id),
    for (final row in swept)
      if (row is! LayerRowAddress) row,
  ];

  /// [span] on the rows it lands on ([_rowsLanded]) — as it is where it
  /// names them already, and where the band was swept over layer rows
  /// alone: a band reads those off its layers
  /// ([TimelineFrameRangeSelection.coversRow]).
  ///
  /// ↩️H20 (유저 2026-08-23) found the four move paths publishing without
  /// the rows, and stopped the lanes being read as covered by inheritance;
  /// the rows the band was swept over were still dropped at every step, so
  /// a band moved with its lanes stood on its layer rows alone.
  TimelineFrameRangeSelection _withSweptRows(
    TimelineFrameRangeSelection span,
  ) {
    final swept = _selectionBefore.rows;
    if (span.rows.isNotEmpty || swept.every((row) => row is LayerRowAddress)) {
      return span;
    }
    return TimelineFrameRangeSelection(
      layerId: span.layerId,
      startIndex: span.startIndex,
      endIndexExclusive: span.endIndexExclusive,
      layerIds: span.layerIds,
      rows: _rowsLanded(span, swept),
    );
  }

  /// The lane selection a mixed sweep stood beside the band
  /// ([_laneTailBefore]), on the frames [span] went to: its lanes are the
  /// band's own, and their keys go the band's frames on them (H20). ⛔Two
  /// selections stand together only there ([RangeSelections.claimSelection]),
  /// so a lane selection live at begin is that one.
  void _rideLaneTail(TimelineFrameRangeSelection? span) {
    final tail = _laneTailBefore;
    if (tail == null || span == null) {
      return;
    }
    final shift = span.startIndex - _selectionBefore.startIndex;
    _selection.laneRangeSelection.value = TimelineLaneSelection(
      layerId: tail.layerId,
      laneId: tail.laneId,
      startIndex: tail.startIndex + shift,
      endIndexExclusive: tail.endIndexExclusive + shift,
      laneIds: tail.laneIds,
    );
  }

  int _commitOffset(LayerId layerId, int spanStart) => _commitOffsetFor(
    layerId,
    spanStart,
    onTrackAxis: _onTrackAxis,
    trackSe: _trackSe,
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
      _instructionShifted = null;
      _rowsShifted = null;
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
      final lanes = plan == null ? null : _lanesShiftedBy(frameDelta);
      if (plan == null || lanes == null) {
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
      _publishStep(
        BlockMoveDragPreview(
          previewLayers: {
            selection.layerId: sourceForms.shown,
            targetLayerId: targetForms.shown,
          },
          previewGlobalLayers: {
            selection.layerId: ?sourceForms.global,
            targetLayerId: ?targetForms.global,
          },
        ),
        lanes,
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
        landing: _swapsOn(targetLayer.id),
        cutFrameCount: _project.activeCutFrameCount,
      );
      final lanes = plan == null ? null : _lanesShiftedBy(frameDelta);
      if (plan == null || lanes == null) {
        keepLastValid();
        return true;
      }
      _directionRowChange = (plan: plan, source: sourceLayer);
      final drawn = _project.activeCutDrawnFrameCount;
      _publishStep(
        BlockMoveDragPreview(
          previewLayers: _withFolderBands({
            selection.layerId: rederiveRunBehaviors(
              plan.sourceAfter,
              drawnFrameCount: drawn,
            ),
            targetLayerId: rederiveRunBehaviors(
              plan.targetAfter!,
              drawnFrameCount: drawn,
            ),
          }),
          rekeys: plan.rekeys,
        ),
        lanes,
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
        if (_retime.blockMoveEligible(layer.id)) layer,
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
  ///
  /// 🚨F-276: every row but a SYNCED mirror. It is its base's row shown
  /// again ([_seatRowOf]), not a step of the walk — counted as one, a base
  /// hopping past its own mirror "landed" on the mirror, which no block can,
  /// and the whole move held.
  List<Layer> _rangeRowOrder() => [
    for (final layer in sectionedLayerOrder(_project.layers))
      if (!isSyncedAttachedLayer(layer)) layer,
  ];

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
  /// through to the plain frame slide) for same-row steps and for steps
  /// that carry nothing. No row of the span blocks the others: an empty
  /// one (UI-R24 #3: only the frames inside the selection move), and one
  /// that cannot change rows ([_castRowForHop]).
  bool _updateMultiRow(int frameDelta, LayerId targetLayerId) {
    final selection = _selectionBefore;
    if (selection.spanLayerIds.length <= 1) {
      return false;
    }
    final step = (
      selection: selection,
      cast: _castMultiRowSpan(selection),
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
    if (landing.plan == null && landing.sePlan == null) {
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
    _publishMultiRowMovePreview(landing.plan, landing.sePlan, riders);
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

  /// The span sorted by what each row can DO with the hop.
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
  MultiRowSpanCast _castMultiRowSpan(TimelineFrameRangeSelection selection) {
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
        case HopCast.staysPut:
          break;
      }
    }
    return (drawingSourceIds: drawingSourceIds, sePassengerIds: sePassengerIds);
  }

  /// Which [HopCast] the row [id] is for this hop, given whether a row
  /// [carriesBlockInRange].
  HopCast _castRowForHop(LayerId id, bool Function(Layer) carriesBlockInRange) {
    if (_retime.blockMoveEligible(id)) {
      final layer = _project.layerById(id);
      return layer != null && carriesBlockInRange(layer)
          ? HopCast.drawingSource
          : HopCast.staysPut;
    }
    if (_project.isTrackSeLayerId(id)) {
      final display = _project.rangeLayerById(id);
      return display != null && carriesBlockInRange(display)
          ? HopCast.sePassenger
          : HopCast.staysPut;
    }
    // Every other row has no row axis to travel: it STAYS, whatever it
    // carries, and keeps none of the rows above from travelling.
    //
    // · The camera and instruction rows (the transition included, via its
    //   display clone) are frame-axis riders — WHO rides was decided at
    //   begin ([_laneRiders], [_blockRiders] and [_transitionRiders],
    //   the same answers the plain slide consumes). Re-deriving them here is
    //   the copy that silently dropped the TRANSITION on rigid steps (C④):
    //   its clone's kind matched no arm, so the spans snapped home the
    //   moment the pointer crossed a row.
    // · ↩️F-276 (유저 2026-10-04): a SYNCED attach row and a picture row,
    //   whose blocks are not theirs to move. These were the last veto of
    //   the family R27 #8 retired: content on a row that was neither
    //   move-eligible nor a known rider routed the whole step to the plain
    //   slide ("its timing belongs to its base"), so a mirror selected
    //   along with its base switched the base's row change off. 「프레임
    //   블록은 이동가능한곳이라면 어디든 이동가능 … 그 경우 물론 싱크 레이어의
    //   그림이 있다면 사라지겠지. 안내문 안띄워도됨」 — the base's block goes,
    //   the mirror's picture of it stays behind unshown, and nothing is
    //   said. (Its link is kept — `cutWithReconciledAttachedMirrors`
    //   leaves an orphan link alone — so the picture is back the moment
    //   the block is.)
    return HopCast.staysPut;
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
      _hopOrigin,
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
  ({MultiRowRangeMovePlan? plan, MultiRowRangeMovePlan? sePlan})?
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
    MultiRowRangeMovePlan? sePlan;
    if (step.cast.sePassengerIds.isNotEmpty) {
      sePlan = _planMultiRowSePassengers(
        seSourceIds: step.cast.sePassengerIds,
        seLattice: step.lattices.seLattice,
        frameDelta: frameDelta,
        rowDelta: rowDelta,
      );
      if (sePlan == null) {
        return null; // An SE passenger cannot land — the whole move voids.
      }
    }
    return (plan: plan, sePlan: sePlan);
  }

  /// The frame-axis riders shifted by [frameDelta] — the band's lanes
  /// ([_lanesShiftedBy]), and every instruction source's events — or null
  /// when a rider cannot shift, which voids the whole move (P3b-2: KEY
  /// sources join the all-or-nothing contract). WHO rides was decided at
  /// begin; the plain slide and the rigid row hop both ask here.
  FrameAxisRiders? _shiftFrameAxisRiders(
    TimelineFrameRangeSelection selection,
    int frameDelta,
  ) {
    final lanes = _lanesShiftedBy(frameDelta);
    if (lanes == null) {
      return null;
    }
    final instructionShifted = <LayerId, Map<int, InstructionEvent>>{};
    // A direction row's spans are its blocks (R27): they ride as the
    // drawing rows' own slide, drawings and all — and the rows a folder
    // row holds beside them (F-311, [rowsHeldByFolderRowsOf]).
    final ridden = _slideExactly(_blockRiderRows, selection, frameDelta);
    if (ridden == null) {
      return null;
    }
    final rowsShifted = {
      for (final plan in ridden) plan.sourceAfter.id: plan.sourceAfter,
    };
    for (final (:row, :starts) in _transitionRiders) {
      final shifted = shiftInstructionEventsAt(
        events: row.instructions,
        starts: starts,
        frameDelta: frameDelta,
      );
      // …nor one that draws a cut past its camera keys: a のりしろ made
      // shorter stops short of them (🗣️I-73-camera-row-Q7).
      if (shifted == null ||
          !_transitions.keepsCameraKeys(
            row.copyWith(
              instructions: SplayTreeMap<int, InstructionEvent>.from(shifted),
            ),
          )) {
        return null;
      }
      instructionShifted[row.id] = shifted;
    }
    return (
      lanes: lanes,
      instructions: instructionShifted,
      blockRiders: rowsShifted,
    );
  }

  /// Every lane the band holds ([_laneRiders]) with its keys [frameDelta]
  /// frames on, by the lanes' own move ([laneSpanKeysMovedOn]) — or null
  /// when one cannot go: a landing blocked, or one its home will not take
  /// (a camera key put out of its cut, 🗣️I-73-camera-row-Q2). The move
  /// holds there, as it does for a block that cannot land: one rigid group.
  /// A lane none of whose keys moves rides along as nothing.
  List<LaneRide>? _lanesShiftedBy(int frameDelta) {
    final rides = <LaneRide>[];
    for (final (:row, :span, :laneIds) in _laneRiders) {
      final subject = _laneVerbs.laneEditSubjectOf(row);
      final edit = laneSpanKeysMovedOn(
        subject,
        laneIds: laneIds,
        span: span,
        to: (_, frame) => frame + frameDelta,
      );
      if (edit == null) {
        return null;
      }
      if (edit.isEmpty) {
        continue;
      }
      if (subject.preview(edit) == null) {
        return null;
      }
      rides.add((row: row, edit: edit));
    }
    return rides;
  }

  /// Publishes a valid step: [blocks] with its [lanes] riding
  /// ([_withLanesRiding]), and those lanes kept for the release — the one
  /// door every landing step's preview goes through, so what the hand sees
  /// is what the release lands.
  void _publishStep(BlockMoveDragPreview blocks, List<LaneRide> lanes) {
    _lanesShifted = lanes;
    _dragPreview.value = _withLanesRiding(blocks, lanes);
  }

  /// [blocks] with every lane ride's keys where the step put them: each
  /// riding row shown as both leave it — its blocks where [blocks] has them,
  /// its keys as its own lane edit shows them ([LaneEditSubject.preview]) —
  /// and a V track's chain and the cut's camera beside them, where those
  /// are the lanes' homes. The camera's marker comes as a lane edit's
  /// does, a FRESH clone per step (the P3b-2 contract — B4-①: a step
  /// handing the repository's instance over froze the camera's markers).
  BlockMoveDragPreview _withLanesRiding(
    BlockMoveDragPreview blocks,
    List<LaneRide> lanes,
  ) {
    if (lanes.isEmpty) {
      return blocks;
    }
    final shown = {...blocks.previewLayers};
    final global = {...blocks.previewGlobalLayers};
    final trackEffects = {...?blocks.previewTrackEffects};
    var camera = (
      cutId: blocks.cameraCutId,
      track: blocks.cameraTrack,
      marker: blocks.cameraMarkerLayer,
    );
    for (final (:row, :edit) in lanes) {
      // The row as the step left its blocks: its global form for a
      // track-owned row, the one form of any other.
      final moved = global[row.id] ?? shown[row.id] ?? row;
      switch (_laneVerbs.laneEditSubjectOf(moved).preview(edit)) {
        case LaneEditPreview(row: final edited?, :final globalRow):
          shown[edited.id] = edited;
          if (globalRow != null) {
            global[edited.id] = globalRow;
          }
        case LaneEditPreview(trackId: final id?, trackEffects: final fx?):
          trackEffects[id] = fx;
        case LaneEditPreview(
          cameraCutId: final cutId?,
          cameraTrack: final track?,
          :final cameraMarkerLayer,
        ):
          camera = (cutId: cutId, track: track, marker: cameraMarkerLayer);
        case _:
          break;
      }
    }
    return BlockMoveDragPreview(
      previewLayers: shown,
      rekeys: blocks.rekeys,
      picturesMoved: blocks.picturesMoved,
      previewGlobalLayers: global,
      previewTrackEffects: trackEffects.isEmpty ? null : trackEffects,
      cameraCutId: camera.cutId,
      cameraTrack: camera.track,
      cameraMarkerLayer: camera.marker,
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
    MultiRowRangeMovePlan? sePlan,
    FrameAxisRiders riders,
  ) {
    final instructionShifted = riders.instructions;
    _multiRowPlan = plan;
    _multiSeRowPlan = sePlan;
    _multiPlans = null;
    _seRowChange = null;
    _directionRowChange = null;
    _instructionShifted = instructionShifted.isEmpty
        ? null
        : instructionShifted;
    _rowsShifted = riders.blockRiders.isEmpty ? null : riders.blockRiders;
    final sePreviews = {
      for (final MapEntry(key: id, value: row)
          in sePlan?.layersAfter.entries ?? const <MapEntry<LayerId, Layer>>[])
        id: _trackSe.previewFormsOf(row),
      ..._transitionPreviewForms(instructionShifted),
    };
    _publishStep(
      BlockMoveDragPreview(
        previewLayers: _withFolderBands({
          if (plan != null)
            for (final entry in plan.layersAfter.entries)
              entry.key: rederiveRunBehaviors(
                entry.value,
                drawnFrameCount: _project.activeCutDrawnFrameCount,
              ),
          for (final entry in sePreviews.entries) entry.key: entry.value.shown,
          // R27 #8: the frame-axis riders preview in place — a block rider
          // as the row its shifted blocks make (a DIRECTION row: its spans
          // are its blocks; a folder's rows: F-311).
          // A riding TRANSITION is in [sePreviews] above, in the SE rows'
          // two forms.
          for (final entry in riders.blockRiders.entries)
            entry.key: rederiveRunBehaviors(
              entry.value,
              drawnFrameCount: _project.activeCutDrawnFrameCount,
            ),
        }),
        rekeys: plan?.rekeys ?? const [],
        // C2: the SE passengers' global forms, for the storyboard strips.
        previewGlobalLayers: {
          for (final entry in sePreviews.entries)
            entry.key: ?entry.value.global,
        },
      ),
      riders.lanes,
    );
  }

  /// Plans the SE passengers of a multi-row rigid move (R26 #2): every
  /// track-SE row in [seSourceIds] shifts [rowDelta] rows inside the SE
  /// lattice by the drawing rows' own plan ([planMultiRowRangeMove]) — the
  /// sounds ride their cels, and the blocks they land on go back across
  /// them (F-384). Null when ANY passenger cannot land — the whole move
  /// voids, the multi-row all-or-nothing rule.
  ///
  /// ↩️Each passenger was planned as a pair of its own, which pushed what
  /// it landed on and voided a landing on another passenger's row.
  MultiRowRangeMovePlan? _planMultiRowSePassengers({
    required List<LayerId> seSourceIds,
    required List<Layer> seLattice,
    required int frameDelta,
    required int rowDelta,
  }) {
    final selection = _selectionBefore;
    if (seSourceIds.any((id) => !seLattice.any((row) => row.id == id))) {
      return null;
    }
    return planMultiRowRangeMove(
      orderedLayers: seLattice,
      sourceLayerIds: seSourceIds,
      rangeStartIndex: selection.startIndex,
      rangeEndIndexExclusive: selection.endIndexExclusive,
      frameDelta: frameDelta,
      rowDelta: rowDelta,
      // A track-owned row is never linked, so no other lane shares its bank.
      bankOf: (_) => CelBankLanes.unshared,
      rangeOffsetOf: (id) => _commitOffset(id, selection.startIndex),
    );
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
    _multiSeRowPlan = null;
    _lanesShifted = const [];
    _instructionShifted = null;
    _rowsShifted = null;
    _dropPreviewChannels();
    _liveSpan = _selectionBefore;
  }

  /// [rows] with, beside them, the band of every folder one of them stands
  /// in: a folder's row shows what its rows make together (F-311), so it
  /// follows the hand as they do ([folderBandsFollowing]).
  Map<LayerId, Layer> _withFolderBands(Map<LayerId, Layer> rows) => {
    ...rows,
    ...folderBandsFollowing(_project.layers, rows),
  };

  /// Clears every channel this drag publishes to. They live OUTSIDE the
  /// drag (on the session and its collaborators), so dropping the object
  /// does not clear them — this is the one piece of forgetting the object
  /// cannot do by dying.
  void _dropPreviewChannels() {
    _dragPreview.value = null;
  }

  /// A range-moved TRANSITION row's in-flight forms, in the track-SE rows'
  /// shape ([Transitions.previewFormsOf]): the row projected onto the active
  /// cut for the cut's rows, the row itself for the storyboard's strip — so
  /// it rides the step's one preview beside the SE passengers.
  ///
  /// ↩️C1 (2026-08-17) gave it a channel of its own ("one preview channel
  /// per row family"), off this one because a global-keyed entry here would
  /// have leaked into the cut's projection. The cut form answers that the
  /// way it answers it for the SE rows (유저 2026-09-26: 「se블록이랑 똑같이
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
  /// the session's `dragPreview` (repository untouched), the selection
  /// outline riding the previewed landing.
  void update({required int frameDelta, LayerId? targetLayerId}) {
    if (_stepIsTheTrades(frameDelta, targetLayerId)) {
      return;
    }
    // 🚨F-276: the row pointed at is read as its SEAT — over a mirror, the
    // hand is over its base ([_seatRowOf]). Every step below reads this.
    final pointedAt = targetLayerId == null
        ? null
        : _seatRowOf(_project, targetLayerId);
    // R28 #5: back at the start = the origin, not a refusal. A row change
    // still owns the step (a delta-0 drop onto a sibling row is a real
    // move), so only same-row zero deltas reset.
    //
    // ↩️F-263: "same row" is the row the hop is measured from
    // ([_hopOrigin]). It was that row OR the selection's anchor, so a span
    // grabbed by another of its rows could not be carried one row toward
    // its anchor — the step landing there read as "back at the start". No
    // press reached that case while a press off the anchor dropped the
    // selection (`Standing._seatLayer`).
    if (frameDelta == 0 && (pointedAt == null || pointedAt == _hopOrigin)) {
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
      _updateMultiSource(pointedAt, frameDelta, multiSources);
      return;
    }

    final singleRow = _singleRow;
    if (singleRow == null) {
      return;
    }
    final source = singleRow.layer;
    final plan = _singleRowPlan(source, pointedAt, frameDelta);
    // The band's lanes go the frames its group went (H20), on their own row.
    final lanes = plan == null
        ? null
        : _lanesShiftedBy(plan.destinationStartIndex - singleRow.groupStart);
    if (plan == null || lanes == null) {
      // UI-R23 #10: a blocked / incompatible landing HOLDS the last valid
      // preview, outline and plan — the move stops at the last legal spot
      // and resumes on a legal return (no snap-back to the origin).
      return;
    }
    _publishSingleRowMove(plan, source, singleRow.groupStart, lanes);
  }

  /// Whether this step belongs to the picture trade (F-330): on the same
  /// frames, a hop among the rows of the span's attach group trades their
  /// pictures — counted on the rows themselves, where a mirror is one. With
  /// mirrors alone, every step is the trade's: one that trades nothing
  /// HOLDS the last trade (UI-R23 #10), and back on the row grabbed is the
  /// origin — mirrors move no block.
  bool _stepIsTheTrades(int frameDelta, LayerId? targetLayerId) {
    final trade = frameDelta == 0 ? _picturesTradedTo(targetLayerId) : null;
    if (trade != null) {
      _publishPictureTrade(trade.moves, trade.hop, landedOn: targetLayerId!);
      return true;
    }
    if (_refuseUntraded == null) {
      return false;
    }
    if (frameDelta == 0 &&
        (targetLayerId == null || targetLayerId == _grabbedRow)) {
      _resetPreviewToOrigin();
    }
    return true;
  }

  /// The pictures a step on the same frames trades with the hand on
  /// [pointedAt] (F-330): the span's rows carried as many rows of its attach
  /// group as the hand is from the row it grabbed ([_attachTrade]), and that
  /// hop. Null when the span holds no group, the hand is on the row it
  /// grabbed or on none of the group, or the carry trades nothing
  /// ([picturesTradedInAttachGroup]) — or no picture can be written yet,
  /// so the release could not land what the step would show.
  ({List<CelPictureMove> moves, int hop})? _picturesTradedTo(
    LayerId? pointedAt,
  ) {
    final trade = _attachTrade;
    final cut = _project.activeCutOrNull;
    if (trade == null || pointedAt == null || cut == null) {
      return null;
    }
    final hop = layerIndexDelta(
      trade.group,
      _grabbedRow ?? _selectionBefore.layerId,
      pointedAt,
    );
    if (hop == null || hop == 0) {
      return null;
    }
    final moves = picturesTradedInAttachGroup(
      group: trade.group,
      sources: _selectionBefore.spanLayerIds,
      rowDelta: hop,
      baseCels: trade.baseCels,
    );
    return moves == null || _blockMove.pictureMoveCommand(cut, moves) == null
        ? null
        : (moves: moves, hop: hop);
  }

  /// Publishes a trade of [moves]: no row changes, so none is previewed —
  /// a cel a picture goes to reads it where it still is
  /// ([BlockMoveDragPreview.picturesMoved]) — and the selection follows the
  /// pictures [hop] rows of the group on, anchored where the hand is
  /// ([landedOn]).
  void _publishPictureTrade(
    List<CelPictureMove> moves,
    int hop, {
    required LayerId landedOn,
  }) {
    // A step of the hand that trades the same pictures shows the same
    // preview, so what reads it by identity (the canvas) sleeps through it.
    if (_dragPreview.value case BlockMoveDragPreview(:final picturesMoved)
        when listEquals(picturesMoved, moves)) {
      return;
    }
    _resetPreviewToOrigin();
    _dragPreview.value = BlockMoveDragPreview(
      previewLayers: const {},
      picturesMoved: moves,
    );
    final group = [for (final row in _attachTrade!.group) row.id];
    LayerId carried(LayerId row) => group[group.indexOf(row) + hop];
    _slideSelectionOutline(
      _selectionBefore,
      landedLayerId: landedOn,
      shift: 0,
      layerIds: [for (final row in _selectionBefore.spanLayerIds) carried(row)],
    );
  }

  /// [source]'s span [frameDelta] frames along, onto the row the hand is
  /// over where it may land there ([_singleRowMoveTarget]) — null where it
  /// lands nowhere.
  DrawingBlockMovePlan? _singleRowPlan(
    Layer source,
    LayerId? pointedAt,
    int frameDelta,
  ) {
    final target = _singleRowMoveTarget(
      source,
      _carriedRow(source.id, pointedAt),
    );
    if (target == null) {
      return null;
    }
    final selection = _selectionBefore;
    return planDrawingRangeMove(
      source: source,
      target: target,
      rangeStartIndex: selection.startIndex,
      rangeEndIndexExclusive: selection.endIndexExclusive,
      frameDelta: frameDelta,
      sourceBank: _controllers.timelineController.bankLanesOf(source.id),
      landing: _swapsOn(target.id),
      cutFrameCount: _project.activeCutFrameCount,
    );
  }

  /// The row a single-row range move lands on: [source] itself, or the
  /// row [targetLayerId] names when it is move-eligible and in the same
  /// section — else none, and the step has no plan.
  Layer? _singleRowMoveTarget(Layer source, LayerId? targetLayerId) {
    Layer? target = source;
    if (targetLayerId != null && targetLayerId != source.id) {
      target = _retime.blockMoveEligible(targetLayerId)
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

  /// Publishes a single-row [plan]: the plan itself, the preview layers
  /// with the band's [lanes] riding, and the selection moved to where the
  /// group landed.
  void _publishSingleRowMove(
    DrawingBlockMovePlan plan,
    Layer source,
    int groupStart,
    List<LaneRide> lanes,
  ) {
    _plan = plan;
    _publishStep(
      BlockMoveDragPreview(
        previewLayers: _withFolderBands({
          plan.sourceAfter.id: rederiveRunBehaviors(
            plan.sourceAfter,
            drawnFrameCount: _project.activeCutDrawnFrameCount,
          ),
          if (plan.targetAfter != null)
            plan.targetAfter!.id: rederiveRunBehaviors(
              plan.targetAfter!,
              drawnFrameCount: _project.activeCutDrawnFrameCount,
            ),
        }),
        rekeys: plan.rekeys,
      ),
      lanes,
    );
    _slideSelectionOutline(
      _selectionBefore,
      landedLayerId: plan.isCrossLayer ? plan.targetAfter!.id : source.id,
      shift: plan.destinationStartIndex - groupStart,
      // A slide along its own row keeps the rows it was selected on: the
      // mirrors selected with their base (F-276) show the block where it
      // went. A row change leaves them — they are the row it left.
      layerIds: plan.isCrossLayer ? const [] : _selectionBefore.layerIds,
    );
  }

  void _updateMultiSource(
    LayerId? targetLayerId,
    int frameDelta,
    List<({Layer commit, int offset})> multiSources,
  ) {
    final selection = _selectionBefore;
    final landing = selection.spanLayerIds.length == 1
        ? _carriedRow(selection.layerId, targetLayerId)
        : null;
    if (landing != null &&
        landing != selection.layerId &&
        _updateRowChange(frameDelta, landing)) {
      return;
    }
    // MULTI-ROW rigid move (UI-R23 #9): a multi-layer drawing selection
    // dragged onto a different row carries every selected row together.
    if (targetLayerId != null &&
        selection.spanLayerIds.length > 1 &&
        _updateMultiRow(frameDelta, targetLayerId)) {
      return;
    }
    _forgetTheRowHop();
    final went = _rigidSlideDelta(
      _slidingRows(multiSources),
      selection,
      frameDelta,
    );
    if (went == 0) {
      // Nowhere to go this way — or asked to go nowhere: the group is
      // where it started (R28 #5: the origin is no refused landing).
      _resetPreviewToOrigin();
      return;
    }
    final plans = _slideExactly(multiSources, selection, went);
    final riders = plans == null
        ? null
        : _shiftFrameAxisRiders(selection, went);
    if (plans == null || riders == null) {
      // UI-R23 #10: a blocked landing HOLDS the last valid preview,
      // outline and stored plans — no snap-back to the origin.
      return;
    }
    final instructionShifted = riders.instructions;
    _multiPlans = plans.isEmpty ? null : plans;
    _instructionShifted = instructionShifted.isEmpty
        ? null
        : instructionShifted;
    _rowsShifted = riders.blockRiders.isEmpty ? null : riders.blockRiders;
    _publishSlidePreview(plans, riders);
    _slideSelectionOutline(
      selection,
      landedLayerId: selection.layerId,
      shift: went,
      layerIds: selection.layerIds,
    );
  }

  /// What a step that falls to the plain slide leaves behind it: any prior
  /// row-change / multi-row plan is stale now (the slide, not the row
  /// change, is last valid).
  void _forgetTheRowHop() {
    final aRowHopWasLast = _multiRowPlan != null || _multiSeRowPlan != null;
    _seRowChange = null;
    _directionRowChange = null;
    _multiRowPlan = null;
    _multiSeRowPlan = null;
    // …and the rigid step's RIDER shifts die WITH its plans: a stale
    // shift surviving here commits alone when the slide step holds —
    // the rigid group torn in one silent undo step (transition spans
    // moving while the blocks stay home). A valid slide step re-derives
    // them fresh.
    //
    // 🚨WITH ITS PLANS, and only then. They were dropped before every
    // slide step, so a slide that HELD kept the last slide's blocks
    // ([_multiPlans]) and lost its riders: released there, the blocks
    // landed and the camera's keys stayed home — the same group torn the
    // other way (🧪2026-10-07: a row and the camera row slid +3, then a
    // step the keys could not take; the block went to 3 and the keys
    // stayed at 2 and 9).
    if (aRowHopWasLast) {
      _lanesShifted = const [];
      _instructionShifted = null;
      _rowsShifted = null;
    }
  }

  /// Cross-layer slide (UI-R18 #1): every one of [rows] plans the SAME
  /// frame delta on itself, in [rows]' order — or null when one of them
  /// does not land exactly that far, and then the step has no plan
  /// (all-or-nothing, the single-layer discipline: an illegal landing HOLDS
  /// the last valid preview). KEY sources (P3b-2) join the same contract:
  /// camera keys and instruction spans shift by the same delta or the
  /// whole move voids.
  ///
  /// The sources of a slide ask with the delta the group agreed on
  /// ([_rigidSlideDelta]); the rows riding a row hop ask with the hop's.
  List<DrawingBlockMovePlan>? _slideExactly(
    Iterable<({Layer commit, int offset})> rows,
    TimelineFrameRangeSelection selection,
    int frameDelta,
  ) {
    final plans = <DrawingBlockMovePlan>[];
    for (final row in rows) {
      final slid = _slideOnOwnRow(
        row.commit,
        selection,
        frameDelta,
        offset: row.offset,
      );
      if (slid == null || slid.went != frameDelta) {
        return null;
      }
      plans.add(slid.plan);
    }
    return plans;
  }

  /// [row]'s blocks in [selection] slid along their own row when asked for
  /// [frameDelta] — the row they leave, and how far they WENT. Null when
  /// they do not move. [offset] is the display→commit offset of a row keyed
  /// on another axis ([_commitOffsetFor]).
  ///
  /// A same-row slide stops at contact with a neighbour and takes the seat
  /// beyond it only once it reaches it ([planDrawingRangeMove]), so `went`
  /// can fall short of what was asked. One row alone shows that as it is;
  /// several agree on it first ([_rigidSlideDelta]).
  /// A landing on [layerId]'s row: the blocks it lands on go back to the
  /// row the move left (F-384), unless another lane of that row's bank
  /// still shows their cels.
  LandingSwapsThem _swapsOn(LayerId layerId) =>
      LandingSwapsThem(_controllers.timelineController.bankLanesOf(layerId));

  ({DrawingBlockMovePlan plan, int went})? _slideOnOwnRow(
    Layer row,
    TimelineFrameRangeSelection selection,
    int frameDelta, {
    int offset = 0,
  }) {
    final start = selection.startIndex + offset;
    final endExclusive = selection.endIndexExclusive + offset;
    final plan = planDrawingRangeMove(
      source: row,
      target: row,
      rangeStartIndex: start,
      rangeEndIndexExclusive: endExclusive,
      frameDelta: frameDelta,
      sourceBank: _controllers.timelineController.bankLanesOf(row.id),
      // A slide along its own row lands on nothing of another's — the
      // move's law all the same.
      landing: _swapsOn(row.id),
      cutFrameCount: _project.activeCutFrameCount,
    );
    if (plan == null) {
      return null;
    }
    final first = drawingBlocks(
      row.timeline,
    ).firstWhere((block) => _wholeBlockIn(block, start, endExclusive));
    return (plan: plan, went: plan.destinationStartIndex - first.startIndex);
  }

  /// Every row whose BLOCKS a slide carries along its own row: the sources
  /// and the rows riding as blocks — direction rows, and the rows a folder
  /// row holds.
  Iterable<({Layer commit, int offset})> _slidingRows(
    List<({Layer commit, int offset})> multiSources,
  ) => [...multiSources, ..._blockRiderRows];

  /// The block riders as rows of a slide. They are cut rows, keyed on the
  /// axis the span is stated in — no offset.
  Iterable<({Layer commit, int offset})> get _blockRiderRows => [
    for (final rider in _blockRiders ?? const <Layer>[])
      (commit: rider, offset: 0),
  ];

  /// The frames [rows] go as ONE group when asked for [frameDelta]: that
  /// far when every row lands there, else as far as the row that stops
  /// first lets them all go. Zero when the group stays where it is.
  ///
  /// 🚨A rigid group has one delta, and each row used to be planned with
  /// the delta the hand asked for and left to land where it could. That
  /// was all-or-nothing while a blocked row answered null; since the frame
  /// axis took the cut's move rule (2026-07-27, `planBlockRunMove`) a
  /// blocked row answers with where it STOPPED — so in the frames between
  /// touching a neighbour and reaching the seat beyond it, that row stayed
  /// at contact while the others went on, and the outline went with the
  /// hand (🧪2026-10-07: two rows asked for +5, one landed at +4 and one at
  /// +5). The group stops where its first row does, the way one row stops,
  /// and takes the step again once every row can.
  int _rigidSlideDelta(
    Iterable<({Layer commit, int offset})> rows,
    TimelineFrameRangeSelection selection,
    int frameDelta,
  ) {
    var delta = frameDelta;
    while (delta != 0) {
      var reach = delta;
      for (final row in rows) {
        // Zero when the row does not move at all, else where it stopped.
        final went =
            _slideOnOwnRow(
              row.commit,
              selection,
              delta,
              offset: row.offset,
            )?.went ??
            0;
        if (went.abs() < reach.abs()) {
          reach = went;
        }
      }
      if (reach == delta) {
        return delta;
      }
      // Nearer home each time round, so the walk ends.
      delta = reach;
    }
    return 0;
  }

  /// Publishes a valid slide step: every plan's commit form (windowed for
  /// the track-SE rows), the shifted instruction rows and a riding
  /// transition in the same two forms, and the band's lanes
  /// ([_publishStep]).
  void _publishSlidePreview(
    List<DrawingBlockMovePlan> plans,
    FrameAxisRiders riders,
  ) {
    final instructionShifted = riders.instructions;
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
        drawnFrameCount: _project.activeCutDrawnFrameCount,
      );
      final forms = _trackSe.previewFormsOf(commitForm);
      previewLayers[commitForm.id] = forms.shown;
      final global = forms.global;
      if (global != null) {
        previewGlobalLayers[commitForm.id] = global;
      }
    }
    // A block rider previews as the row its shifted blocks make — a
    // DIRECTION row's spans are its blocks (R27), so the cells row reads
    // them there; the rows a folder row holds are rows of blocks (F-311).
    for (final entry in riders.blockRiders.entries) {
      previewLayers[entry.key] = rederiveRunBehaviors(
        entry.value,
        drawnFrameCount: _project.activeCutDrawnFrameCount,
      );
    }
    for (final entry in _transitionPreviewForms(instructionShifted).entries) {
      previewLayers[entry.key] = entry.value.shown;
      final global = entry.value.global;
      if (global != null) {
        previewGlobalLayers[entry.key] = global;
      }
    }
    _publishStep(
      BlockMoveDragPreview(
        previewLayers: _withFolderBands(previewLayers),
        previewGlobalLayers: previewGlobalLayers,
      ),
      riders.lanes,
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
    final shown = _dragPreview.value;
    _dropPreviewChannels();
    if (_releaseIsTheTrades(shown, landedSelection)) {
      return;
    }
    _project.historyManager.runAsOneStep('Move frame range', () {
      _commitBlocks(landedSelection);
      // The band's lanes land AFTER its blocks, each through its row's own
      // lane commit: a block move writes its rows whole (`replaceLayer`),
      // and a key written before it would go with the row it replaced.
      for (final (:row, :edit) in _lanesShifted) {
        _laneVerbs.laneEditSubjectOf(row).commit(edit, 'Move frame range');
      }
    });
  }

  /// The release's blocks, by the path the drag's steps took.
  void _commitBlocks(TimelineFrameRangeSelection? landedSelection) {
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
    if (_multiRowPlan != null || _multiSeRowPlan != null) {
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
      // composite undo across blocks and instruction spans — the band's
      // lanes beside them ([commit]).
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

  /// Whether the release belongs to the picture trade (F-330), landed or
  /// refused here: a trade lands the very pictures its step showed moving —
  /// asked of [shown], the preview, which a later step of another kind
  /// replaced — and mirrors alone that traded nothing refuse.
  bool _releaseIsTheTrades(
    TimelineDragPreview? shown,
    TimelineFrameRangeSelection? landedSelection,
  ) {
    if (shown case BlockMoveDragPreview(:final picturesMoved)
        when picturesMoved.isNotEmpty) {
      _commitPictureTrade(picturesMoved, landedSelection);
      return true;
    }
    if (_refuseUntraded case final refuse?) {
      refuse();
      _liveSpan = _selectionBefore;
      return true;
    }
    return false;
  }

  /// Lands a trade of [moves] as ONE undo step — the pictures change cels,
  /// and no row, cel or name does (F-330) — and stands on the row the hand
  /// carried the selection's anchor to.
  void _commitPictureTrade(
    List<CelPictureMove> moves,
    TimelineFrameRangeSelection? landedSelection,
  ) {
    final cut = _project.activeCutOrNull;
    final land = cut == null
        ? null
        : _blockMove.pictureMoveCommand(cut, moves);
    _landStandingOnTheAnchor([?land], landedSelection);
  }

  void _commitMultiSourceMove(
    List<({Layer commit, int offset})> multiSources,
    TimelineFrameRangeSelection? landedSelection,
  ) {
    final multiPlans = _multiPlans;
    final commands = <Command>[
      if (multiPlans != null)
        for (var i = 0; i < multiPlans.length; i += 1)
          UpdateLayerTimelineCommand(
            repository: _project.repository,
            before: multiSources[i].commit,
            after: rederiveRunBehaviors(
              multiPlans[i].sourceAfter,
              drawnFrameCount: _project.activeCutDrawnFrameCount,
            ),
          ),
      ..._riderCommands(),
    ];
    if (!_commitRangeMoveCommands(commands, landedSelection)) {
      return;
    }
    _changes.warmActiveCut();
    _changes.notifyChanged();
  }

  /// R27 #8: the frame-axis riders (instruction spans, block riders) land
  /// in the SAME undo step as the rigid row move — through the ONE
  /// two-armed projection the plain slide commits with, so a riding
  /// TRANSITION lands too (C④: this branch used to carry a cut-gated copy
  /// with the transition arm missing). The band's lanes land beside them
  /// ([commit]).
  List<Command> _riderCommands() {
    final instructionShifted = _instructionShifted;
    final rowsShifted = _rowsShifted;
    return [
      if (instructionShifted != null)
        ..._instructionShiftCommands(instructionShifted),
      // A block rider lands as the timeline write any block move makes —
      // a DIRECTION row's spans are its blocks (R27), a folder's rows hold
      // them (F-311).
      if (rowsShifted != null)
        for (final MapEntry(key: id, value: after) in rowsShifted.entries)
          if (_project.commitLayerById(id) case final before?)
            UpdateLayerTimelineCommand(
              repository: _project.repository,
              before: before,
              after: rederiveRunBehaviors(
                after,
                drawnFrameCount: _project.activeCutDrawnFrameCount,
              ),
            ),
    ];
  }

  /// Executes a range move's [commands] as ONE undo step and leaves the
  /// selection on the frames where they landed. False when there was
  /// nothing to commit, the band's lanes included ([_lanesShifted]) — the
  /// selection goes back to where the drag started and the caller stops.
  bool _commitRangeMoveCommands(
    List<Command> commands,
    TimelineFrameRangeSelection? landedSelection,
  ) {
    if (commands.isEmpty && _lanesShifted.isEmpty) {
      _liveSpan = _selectionBefore;
      return false;
    }
    _project.historyManager.executeAsOneStep('Move frame range', commands);
    _liveSpan = landedSelection;
    return true;
  }

  void _commitMultiRowMove(TimelineFrameRangeSelection? landedSelection) {
    final cut = _project.activeCutOrNull;
    final multiRowPlan = _multiRowPlan;
    final commands = <Command>[];
    commands.addAll(_seRowMoveCommands(_multiSeRowPlan));
    commands.addAll(_multiRowLayerCommands(multiRowPlan));
    commands.addAll(_riderCommands());
    if (cut != null && (multiRowPlan?.rekeys.isNotEmpty ?? false)) {
      commands.add(_blockMove.celRekeyCommand(cut, multiRowPlan!.rekeys));
    }
    _landStandingOnTheAnchor(commands, landedSelection);
  }

  /// Lands [commands] as ONE undo step ([_commitRangeMoveCommands]) and
  /// stands on the row the selection's anchor landed on — the rows a move
  /// of several rows, or a trade of their pictures, carried it to.
  void _landStandingOnTheAnchor(
    List<Command> commands,
    TimelineFrameRangeSelection? landedSelection,
  ) {
    if (!_commitRangeMoveCommands(commands, landedSelection)) {
      return;
    }
    if (landedSelection != null) {
      _controllers.layerController.selectLayer(landedSelection.layerId);
    }
    _changes.warmActiveCut();
    _changes.notifyChanged();
  }

  /// The timeline commands of the SE rows a multi-row move changed, in
  /// their global form — none for a row the plan left as it was.
  List<Command> _seRowMoveCommands(MultiRowRangeMovePlan? sePlan) => [
    for (final MapEntry(key: id, value: after)
        in sePlan?.layersAfter.entries ?? const <MapEntry<LayerId, Layer>>[])
      if (_project.trackSeGlobalLayerById(id) case final before?
          when before != after)
        UpdateLayerTimelineCommand(
          repository: _project.repository,
          before: before,
          after: after,
        ),
  ];

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
        drawnFrameCount: _project.activeCutDrawnFrameCount,
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
  /// ([BlockMoveCommands.singleRowMoveCommand]).
  void _commitDirectionRowMove(
    ({DrawingBlockMovePlan plan, Layer source}) change,
    TimelineFrameRangeSelection? landedSelection,
  ) {
    _project.historyManager.execute(
      _blockMove.singleRowMoveCommand(
        change.plan,
        source: change.source,
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
    _project.historyManager.executeAsOneStep('Move frame range', [
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
    ]);
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
    final landed = _rowWalkedTo(rows, layerId, displayDelta);
    return landed == null
        ? null
        : layerIndexDelta(lattice, layerId, landed.id);
  }

  /// The display row [hop] rows from [layerId] in [rows] — the walk a row
  /// hop takes on screen — or null when it leaves the screen.
  static Layer? _rowWalkedTo(List<Layer> rows, LayerId layerId, int hop) {
    final rowIndex = rows.indexWhere((layer) => layer.id == layerId);
    if (rowIndex == -1) {
      return null;
    }
    final landingIndex = rowIndex + hop;
    if (landingIndex < 0 || landingIndex >= rows.length) {
      return null;
    }
    return rows[landingIndex];
  }
}
