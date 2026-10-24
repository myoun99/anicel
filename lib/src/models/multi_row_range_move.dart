import 'dart:collection';

import 'audio_clip.dart';
import 'block_row_swap.dart';
import 'cel_bank_lanes.dart';
import 'cel_rekey.dart';
import 'frame.dart';
import 'frame_id.dart';
import 'layer.dart';
import 'layer_id.dart';
import 'timeline_coverage.dart';
import 'timeline_exposure.dart';
import 'timeline_repeat.dart' show ghostFreeTimeline;

/// The resolved result of a multi-row range move (UI-R23 #9): the affected
/// drawing layers with their blocks relocated, plus the cross-row cel
/// re-key pairs the brush store must follow.
class MultiRowRangeMovePlan {
  const MultiRowRangeMovePlan({required this.layersAfter, required this.rekeys});

  /// Every affected layer's ghost-free timeline after the shift (the caller
  /// re-derives run behaviors). Keyed by layer id; unchanged layers are
  /// omitted.
  final Map<LayerId, Layer> layersAfter;

  /// The cels that changed owning layer, so their brush frames re-key from
  /// the source row to the target row ([CelRekey]).
  final List<CelRekey> rekeys;
}

/// Plans a MULTI-ROW range move (UI-R23 #9): the selected blocks on a
/// contiguous run of rows shift RIGIDLY by [rowDelta] rows and [frameDelta]
/// frames — every source row's selected blocks leave and the row
/// [rowDelta] away receives them at the shifted frames, cels, breakdown
/// dots and the sounds anchored to the cels riding along. "If a block is
/// movable, it moves no matter how many rows you select."
///
/// The blocks they land on go back across the moved rows, to the rows the
/// move left empty, each on its own frames ([LandingSwapsThem], F-384-Q1:
/// 「여러 행을 함께 옮기면 덮인 블록이 그 묶음을 건너 반대편 행으로」) —
/// see [rowLandedOnGoesBackTo]. ↩️An incoming block that
/// met a block staying on its row voided the whole move.
///
/// [orderedLayers] is the display-ordered lattice of move-eligible rows
/// (all one section, so no cross-section landing is possible);
/// [sourceLayerIds] is the selection's span (a contiguous subset).
///
/// Null when the rigid shift cannot land — any illegal landing voids the
/// WHOLE move: a source row maps off the lattice, a landing dips below
/// frame 0, a moved or a returned cel is linked from outside the blocks
/// that carry it, or the range is not block-snapped on some row.
///
/// [bankOf] answers a row's OTHER lanes — outside the moved set too
/// (F-136, see [CelBankLanes]). [rangeOffsetOf] is where the range stands
/// on a row's own frames, past where it is stated — a track's SE row
/// holds a sound spilled in from an earlier cut at its own start (the
/// move's commit offset), and a cut's row is where the range says.
MultiRowRangeMovePlan? planMultiRowRangeMove({
  required List<Layer> orderedLayers,
  required List<LayerId> sourceLayerIds,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
  required int rowDelta,
  required CelBankLanes Function(LayerId layerId) bankOf,
  int Function(LayerId layerId) rangeOffsetOf = _whereTheRangeSays,
}) {
  if (rowDelta == 0 || rangeEndIndexExclusive <= rangeStartIndex) {
    return null;
  }
  final planner = _MultiRowRangeMovePlanner(
    orderedLayers: orderedLayers,
    rangeStartIndex: rangeStartIndex,
    rangeEndIndexExclusive: rangeEndIndexExclusive,
    frameDelta: frameDelta,
    rowDelta: rowDelta,
    bankOf: bankOf,
    rangeOffsetOf: rangeOffsetOf,
  );
  if (!planner.gather(sourceLayerIds)) {
    return null;
  }
  if (planner.selectedByLayer.isEmpty) {
    return null; // Nothing but empty cells across every row.
  }
  return planner.rebuild();
}

int _whereTheRangeSays(LayerId _) => 0;

/// [planMultiRowRangeMove]'s two phases with one view of the lattice:
/// GATHER what every source row carries (refusing the move where a rule
/// says so), then REBUILD every affected row. (The audit's 2026-09-03
/// restructure of one 157-line function; every rule and its comment
/// moved verbatim.)
class _MultiRowRangeMovePlanner {
  _MultiRowRangeMovePlanner({
    required this.orderedLayers,
    required this.rangeStartIndex,
    required this.rangeEndIndexExclusive,
    required this.frameDelta,
    required this.rowDelta,
    required this.bankOf,
    required this.rangeOffsetOf,
  }) : indexById = <LayerId, int>{
         for (var i = 0; i < orderedLayers.length; i += 1)
           orderedLayers[i].id: i,
       };

  final List<Layer> orderedLayers;
  final int rangeStartIndex;
  final int rangeEndIndexExclusive;
  final int frameDelta;
  final int rowDelta;
  final CelBankLanes Function(LayerId layerId) bankOf;
  final int Function(LayerId layerId) rangeOffsetOf;
  final Map<LayerId, int> indexById;

  /// Gathered per source row: its selected blocks + travelling cels.
  /// Rows with NOTHING selected contribute nothing and need no target
  /// mapping (UI-R24 #3: the selection's empty parts never block the move —
  /// only the frames inside it travel).
  final selectedByLayer = <LayerId, List<TimelineDrawingBlock>>{};
  final framesByLayer = <LayerId, List<Frame>>{};
  final frameIdsByLayer = <LayerId, Set<FrameId>>{};
  final sourceIndexes = <int>{};

  /// The cels the rebuild carries onto another row ([CelRekey]).
  final rekeys = <CelRekey>[];

  /// The rows the rebuild has taken in hand, by index — each taken the
  /// first time it is asked for ([_rowAt]).
  final _rows = <int, _RowInHand>{};

  _RowInHand _rowAt(int index) =>
      _rows[index] ??= _RowInHand(orderedLayers[index]);

  /// Phase 1: each source row's selected blocks + travelling cels,
  /// validating the block-snap and the link-safety of every cel that
  /// would travel. False when a rule voids the whole move.
  bool gather(List<LayerId> sourceLayerIds) {
    for (final sourceId in sourceLayerIds) {
      final sourceIndex = indexById[sourceId];
      if (sourceIndex == null) {
        // Off the lattice — a row that holds no block, or whose blocks are
        // not its own to move (a synced mirror, a picture row). It stays
        // where it is and keeps the rows on the lattice from nothing
        // (F-276).
        continue;
      }
      if (!_gatherRow(sourceId, sourceIndex)) {
        return false;
      }
    }
    return true;
  }

  bool _gatherRow(LayerId sourceId, int sourceIndex) {
    final source = orderedLayers[sourceIndex];
    final base = ghostFreeTimeline(source);
    final selected = _blockSnappedSelection(base, rangeOffsetOf(sourceId));
    if (selected == null) {
      return false; // The range was not block-snapped on this row.
    }
    if (selected.isEmpty) {
      return true; // An empty row rides along without mapping anywhere.
    }
    final targetIndex = sourceIndex + rowDelta;
    if (targetIndex < 0 || targetIndex >= orderedLayers.length) {
      return false;
    }
    sourceIndexes.add(sourceIndex);
    final frameIds = <FrameId>{for (final block in selected) block.frameId};
    if (_linkedFromOutside(base, selected, frameIds, bankOf(sourceId))) {
      return false;
    }
    final frames = framesNamed(source, frameIds);
    if (frames == null) {
      return false;
    }
    selectedByLayer[sourceId] = selected;
    framesByLayer[sourceId] = frames;
    frameIdsByLayer[sourceId] = frameIds;
    return true;
  }

  /// The blocks inside the range, [offset] along; null when a block
  /// straddles its edge.
  List<TimelineDrawingBlock>? _blockSnappedSelection(
    SplayTreeMap<int, TimelineExposure> base,
    int offset,
  ) {
    final rangeStartIndex = this.rangeStartIndex + offset;
    final rangeEndIndexExclusive = this.rangeEndIndexExclusive + offset;
    final selected = <TimelineDrawingBlock>[];
    for (final block in drawingBlocks(base)) {
      final inRange =
          block.startIndex >= rangeStartIndex &&
          block.endIndexExclusive <= rangeEndIndexExclusive;
      final overlaps =
          block.startIndex < rangeEndIndexExclusive &&
          block.endIndexExclusive > rangeStartIndex;
      if (inRange) {
        selected.add(block);
      } else if (overlaps) {
        return null;
      }
    }
    return selected;
  }

  /// A cel referenced from OUTSIDE the moved set stays put (link intact) —
  /// the whole move is rejected rather than splitting the link.
  ///
  /// 🚨F-136: outside is every lane of the row's [bank] — its own lane
  /// without the selected blocks, and each 겸용 sibling's.
  bool _linkedFromOutside(
    SplayTreeMap<int, TimelineExposure> base,
    List<TimelineDrawingBlock> selected,
    Set<FrameId> frameIds,
    CelBankLanes bank,
  ) {
    final rest = SplayTreeMap<int, TimelineExposure>.of(base)
      ..removeWhere(
        (start, _) => selected.any((block) => block.startIndex == start),
      );
    return frameIds.any((frameId) => bank.exposes(frameId, lane: rest));
  }

  /// Phase 2: every affected row rebuilt — sources lose their selected
  /// blocks, targets receive the mapped source's, and the blocks those land
  /// on go back to the rows the move left ([rowLandedOnGoesBackTo]). Null
  /// when an incoming block dips below frame 0, or a cel going back is one
  /// another lane of its row still shows (F-136).
  MultiRowRangeMovePlan? rebuild() {
    // Every SOURCE: its own selected blocks (and cels) leave.
    for (final sourceIndex in sourceIndexes) {
      final id = orderedLayers[sourceIndex].id;
      _rowAt(
        sourceIndex,
      ).lift(selectedByLayer[id]!, cels: frameIdsByLayer[id]!);
    }

    // Every TARGET: what its blocks land on is lifted, then they arrive.
    final landedOn = <int, _LandedOn>{};
    for (final sourceIndex in sourceIndexes) {
      final landed = _arrive(sourceIndex);
      if (landed == null) {
        return null;
      }
      landedOn[sourceIndex + rowDelta] = landed;
    }
    _sendBack(landedOn);

    return MultiRowRangeMovePlan(
      layersAfter: {for (final row in _rows.values) row.layer.id: row.after},
      rekeys: rekeys,
    );
  }

  /// [sourceIndex]'s selected blocks laid on the row [rowDelta] from it,
  /// what they land on lifted first: what they landed on, to go back — null
  /// when one dips below frame 0, or a cel landed on is one another lane of
  /// that row still shows (F-136).
  _LandedOn? _arrive(int sourceIndex) {
    final from = orderedLayers[sourceIndex];
    final onto = _rowAt(sourceIndex + rowDelta);
    final incoming = selectedByLayer[from.id]!;
    final spans = [
      for (final block in incoming)
        (start: block.startIndex + frameDelta, length: block.length),
    ];
    if (spans.any((span) => span.start < 0)) {
      return null;
    }
    final covered = blocksLandedOn(drawingBlocks(onto.timeline), spans);
    final coveredCels = {for (final block in covered) block.frameId};
    final lifted = onto.lift(covered, cels: coveredCels);
    final bank = bankOf(onto.layer.id);
    if (coveredCels.any((id) => bank.exposes(id, lane: onto.timeline))) {
      return null;
    }
    final frameIds = frameIdsByLayer[from.id]!;
    onto.lay(
      [
        for (final (position, block) in incoming.indexed)
          TimelineDrawingBlock(
            startIndex: spans[position].start,
            entry: block.entry,
          ),
      ],
      cels: (
        frames: framesByLayer[from.id]!,
        clips: clipsAnchoredTo(from.audioClips, frameIds),
      ),
    );
    for (final frameId in frameIds) {
      rekeys.add((from: from.id, to: onto.layer.id, frameId: frameId));
    }
    return (blocks: covered, cels: lifted);
  }

  /// The blocks [landedOn] holds, by the row they were landed on, go back
  /// to the rows the move left ([rowLandedOnGoesBackTo]) — the rows the
  /// move enters first, whose blocks have a row left empty each.
  void _sendBack(Map<int, _LandedOn> landedOn) {
    final entered = _entered;
    final order = [...landedOn.keys]
      ..sort((a, b) {
        final enteredFirst = (entered.contains(a) ? 0 : 1).compareTo(
          entered.contains(b) ? 0 : 1,
        );
        return enteredFirst != 0 ? enteredFirst : a.compareTo(b);
      });
    for (final targetIndex in order) {
      final (:blocks, :cels) = landedOn[targetIndex]!;
      if (blocks.isEmpty) {
        continue;
      }
      final back = _rowAt(
        rowLandedOnGoesBackTo(
          targetIndex,
          sources: sourceIndexes,
          rowDelta: rowDelta,
        ),
      );
      back.takeBack(blocks, cels: cels);
      for (final frame in cels.frames) {
        rekeys.add((
          from: orderedLayers[targetIndex].id,
          to: back.layer.id,
          frameId: frame.id,
        ));
      }
    }
  }

  /// The rows the moved blocks land on.
  Set<int> get _targets => {
    for (final sourceIndex in sourceIndexes) sourceIndex + rowDelta,
  };

  /// The rows the move enters — landed on, and no source of its own.
  Set<int> get _entered => _targets.difference(sourceIndexes);
}

/// The cels a row gives up, and the sounds anchored to them.
typedef _Lifted = ({List<Frame> frames, List<AudioClip> clips});

/// The blocks a move landed on a row, and the cels they took off it.
typedef _LandedOn = ({List<TimelineDrawingBlock> blocks, _Lifted cels});

/// One row of a multi-row move while the rebuild works on it: what it
/// shows, the cels it owns and the sounds anchored to them.
class _RowInHand {
  _RowInHand(this.layer)
    : timeline = ghostFreeTimeline(layer),
      frames = [...layer.frames],
      clips = [...layer.audioClips];

  final Layer layer;
  SplayTreeMap<int, TimelineExposure> timeline;
  List<Frame> frames;
  List<AudioClip> clips;

  /// [blocks] lifted out, and with them [cels] and their sounds — which
  /// it hands back.
  _Lifted lift(
    Iterable<TimelineDrawingBlock> blocks, {
    required Set<FrameId> cels,
  }) {
    for (final block in blocks) {
      timeline.remove(block.startIndex);
    }
    final lifted = (
      frames: [
        for (final frame in frames)
          if (cels.contains(frame.id)) frame,
      ],
      clips: clipsAnchoredTo(clips, cels),
    );
    frames = [
      for (final frame in frames)
        if (!cels.contains(frame.id)) frame,
    ];
    clips = [
      for (final clip in clips)
        if (!cels.contains(clip.frameId)) clip,
    ];
    return lifted;
  }

  /// [blocks] laid in where they stand, with the [cels] they bring.
  void lay(Iterable<TimelineDrawingBlock> blocks, {required _Lifted cels}) {
    for (final block in blocks) {
      timeline[block.startIndex] = block.entry;
    }
    _own(cels);
  }

  /// [blocks] taken back on their own frames ([timelineTakingBack]), with
  /// the [cels] they bring.
  void takeBack(List<TimelineDrawingBlock> blocks, {required _Lifted cels}) {
    timeline = timelineTakingBack(timeline, blocks);
    _own(cels);
  }

  void _own(_Lifted cels) {
    frames = [...frames, ...cels.frames];
    clips = [...clips, ...cels.clips];
  }

  Layer get after =>
      layer.copyWith(timeline: timeline, frames: frames, audioClips: clips);
}
