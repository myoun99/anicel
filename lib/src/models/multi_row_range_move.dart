import 'dart:collection';

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

  /// (from, to, frameId) triples: a cel that changed owning layer, so its
  /// brush frame must re-key from the source row to the target row.
  final List<({LayerId from, LayerId to, FrameId frameId})> rekeys;
}

/// Plans a MULTI-ROW range move (UI-R23 #9): the selected blocks on a
/// contiguous run of drawing rows shift RIGIDLY by [rowDelta] rows and
/// [frameDelta] frames — every source row's selected blocks leave and the
/// row [rowDelta] away receives them at the shifted frames, cels and
/// breakdown dots riding along. "If a block is movable, it moves no matter
/// how many rows you select."
///
/// [orderedLayers] is the display-ordered lattice of move-eligible drawing
/// rows (all one section, so no cross-section landing is possible);
/// [sourceLayerIds] is the selection's span (a contiguous subset).
///
/// Null when the rigid shift cannot land — any illegal landing voids the
/// WHOLE move (multi-row rejects rather than pushing, unlike a single-row
/// slide): a source row maps off the lattice, a landing dips below frame 0,
/// a moved cel is linked from outside the moved set, the range is not
/// block-snapped on some row, or an incoming block would overlap a block
/// that STAYS on the target row.
MultiRowRangeMovePlan? planMultiRowRangeMove({
  required List<Layer> orderedLayers,
  required List<LayerId> sourceLayerIds,
  required int rangeStartIndex,
  required int rangeEndIndexExclusive,
  required int frameDelta,
  required int rowDelta,
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
  );
  if (!planner.gather(sourceLayerIds)) {
    return null;
  }
  if (planner.selectedByLayer.isEmpty) {
    return null; // Nothing but empty cells across every row.
  }
  return planner.rebuild();
}

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
  }) : indexById = <LayerId, int>{
         for (var i = 0; i < orderedLayers.length; i += 1)
           orderedLayers[i].id: i,
       };

  final List<Layer> orderedLayers;
  final int rangeStartIndex;
  final int rangeEndIndexExclusive;
  final int frameDelta;
  final int rowDelta;
  final Map<LayerId, int> indexById;

  /// Gathered per source row: its selected blocks + travelling cels.
  /// Rows with NOTHING selected contribute nothing and need no target
  /// mapping (UI-R24 #3: the selection's empty parts never block the move —
  /// only the frames inside it travel).
  final selectedByLayer = <LayerId, List<TimelineDrawingBlock>>{};
  final framesByLayer = <LayerId, List<Frame>>{};
  final frameIdsByLayer = <LayerId, Set<FrameId>>{};
  final sourceIndexes = <int>{};

  /// (from, to, frameId) triples the rebuild writes: a cel that changed
  /// owning layer, so its brush frame must re-key.
  final rekeys = <({LayerId from, LayerId to, FrameId frameId})>[];

  /// Phase 1: each source row's selected blocks + travelling cels,
  /// validating the block-snap and the link-safety of every cel that
  /// would travel. False when a rule voids the whole move.
  bool gather(List<LayerId> sourceLayerIds) {
    for (final sourceId in sourceLayerIds) {
      final sourceIndex = indexById[sourceId];
      if (sourceIndex == null) {
        continue; // Off the lattice — carries nothing (empty rows only; the
        // caller keeps content-bearing ineligible rows out).
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
    final selected = _blockSnappedSelection(base);
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
    if (_linkedFromOutside(base, selected, frameIds)) {
      return false;
    }
    final frames = _framesOf(source, frameIds);
    if (frames == null) {
      return false;
    }
    selectedByLayer[sourceId] = selected;
    framesByLayer[sourceId] = frames;
    frameIdsByLayer[sourceId] = frameIds;
    return true;
  }

  /// The blocks inside the range; null when a block straddles its edge.
  List<TimelineDrawingBlock>? _blockSnappedSelection(
    SplayTreeMap<int, TimelineExposure> base,
  ) {
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
  bool _linkedFromOutside(
    SplayTreeMap<int, TimelineExposure> base,
    List<TimelineDrawingBlock> selected,
    Set<FrameId> frameIds,
  ) {
    for (final entry in base.entries) {
      if (selected.any((block) => block.startIndex == entry.key)) {
        continue;
      }
      if (entry.value.isDrawing && frameIds.contains(entry.value.frameId)) {
        return true;
      }
    }
    return false;
  }

  /// The source's frames for [frameIds]; null when one is missing.
  List<Frame>? _framesOf(Layer source, Set<FrameId> frameIds) {
    final frames = <Frame>[];
    for (final frameId in frameIds) {
      Frame? found;
      found = source.frameById(frameId);
      if (found == null) {
        return null;
      }
      frames.add(found);
    }
    return frames;
  }

  /// Phase 2: every affected row rebuilt — sources lose their selected
  /// blocks, targets receive the mapped source's. Null when an incoming
  /// block cannot land.
  MultiRowRangeMovePlan? rebuild() {
    final affectedIndexes = <int>{};
    for (final sourceIndex in sourceIndexes) {
      affectedIndexes.add(sourceIndex);
      affectedIndexes.add(sourceIndex + rowDelta);
    }

    final layersAfter = <LayerId, Layer>{};
    for (final layerIndex in affectedIndexes) {
      final layer = orderedLayers[layerIndex];
      final isSource = sourceIndexes.contains(layerIndex);
      final incomingSourceIndex = layerIndex - rowDelta;
      final isTarget = sourceIndexes.contains(incomingSourceIndex);

      final timeline = ghostFreeTimeline(layer);
      var frames = [...layer.frames];

      // This row is a SOURCE: its own selected blocks (and cels) leave.
      if (isSource) {
        frames = _withoutCarried(layer, timeline, frames);
      }

      // This row is a TARGET: the mapped source's selected blocks arrive.
      if (isTarget) {
        final landed = _landIncoming(
          from: orderedLayers[incomingSourceIndex],
          onto: layer,
          timeline: timeline,
        );
        if (landed == null) {
          return null;
        }
        frames = [...frames, ...landed];
      }

      layersAfter[layer.id] = layer.copyWith(
        timeline: timeline,
        frames: frames,
      );
    }

    return MultiRowRangeMovePlan(layersAfter: layersAfter, rekeys: rekeys);
  }

  /// Lifts the source row's selected blocks out of [timeline]; the frames
  /// that stay.
  List<Frame> _withoutCarried(
    Layer layer,
    SplayTreeMap<int, TimelineExposure> timeline,
    List<Frame> frames,
  ) {
    for (final block in selectedByLayer[layer.id]!) {
      timeline.remove(block.startIndex);
    }
    final removedIds = frameIdsByLayer[layer.id]!;
    return [
      for (final frame in frames)
        if (!removedIds.contains(frame.id)) frame,
    ];
  }

  /// Lands the mapped source's selected blocks on [timeline] at the
  /// shifted frames and records their re-keys; the frames they bring, or
  /// null when a landing is illegal.
  List<Frame>? _landIncoming({
    required Layer from,
    required Layer onto,
    required SplayTreeMap<int, TimelineExposure> timeline,
  }) {
    for (final block in selectedByLayer[from.id]!) {
      final landing = block.startIndex + frameDelta;
      if (landing < 0) {
        return null;
      }
      final landingEnd = landing + block.length;
      for (final other in drawingBlocks(timeline)) {
        if (landing < other.endIndexExclusive && other.startIndex < landingEnd) {
          return null; // Overlaps a block that stays — multi-row voids.
        }
      }
      timeline[landing] = block.entry;
    }
    for (final frameId in frameIdsByLayer[from.id]!) {
      rekeys.add((from: from.id, to: onto.id, frameId: frameId));
    }
    return framesByLayer[from.id]!;
  }
}
