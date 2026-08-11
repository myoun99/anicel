import 'dart:math' as math;

import '../core/collection_equality.dart';
import 'layer.dart';
import 'layer_id.dart';
import 'range_snap.dart';
import 'timeline_coverage.dart';
import 'timeline_row_address.dart';

/// One layer's selected frame RANGE (UI-R8, TVP-style): [startIndex,
/// endIndexExclusive) snapped to whole exposure blocks. View state — never
/// persisted.
class TimelineFrameRangeSelection {
  const TimelineFrameRangeSelection({
    required this.layerId,
    required this.startIndex,
    required this.endIndexExclusive,
    this.layerIds = const [],
    this.rows = const [],
  }) : assert(endIndexExclusive > startIndex, 'Range must cover frames.');

  /// The ANCHOR layer (where the drag started) — single-layer flows keep
  /// reading this.
  final LayerId layerId;
  final int startIndex;
  final int endIndexExclusive;

  /// The Excel-style layer SPAN (UI-R17 #8): display-ordered eligible
  /// layers from anchor to head. Empty = the anchor layer alone.
  ///
  /// ⚠️Derived from [rows] whenever the drag supplied them — the layer rows
  /// of the span, in order. It stays because the many single-kind consumers
  /// ask exactly this question.
  final List<LayerId> layerIds;

  /// 🚨★★★ WHAT THE DRAG ACTUALLY SWEPT — every row it crossed, in the order
  /// the rail draws them, whatever KIND those rows are (유저 확정 2026-08-12:
  /// 「선택 객체 하나가 종류 섞인 행들을 담고, 각 동사가 행 종류별로 알아서 처리」).
  ///
  /// This is the authoritative span. [layerIds] used to be, and being a list
  /// of `LayerId` it could not spell a lane row or a group header at all —
  /// which is why a span drawn straight through them left them out.
  ///
  /// Empty when no row list was in reach of the drag (the storyboard's cut
  /// axis, older tests); [coversRow] then falls back to the layer question,
  /// so nothing reads differently than it did before rows existed.
  final List<TimelineRowAddress> rows;

  /// The layers this selection covers, anchor-only selections included.
  List<LayerId> get spanLayerIds => layerIds.isEmpty ? [layerId] : layerIds;

  bool coversLayer(LayerId id) =>
      layerIds.isEmpty ? id == layerId : layerIds.contains(id);

  /// Whether THIS row — of any kind — is in the swept run.
  bool coversRow(TimelineRowAddress row) {
    if (rows.isNotEmpty) {
      return rows.contains(row);
    }
    return switch (row) {
      LayerRowAddress(:final layerId) => coversLayer(layerId),
      LaneRowAddress(:final layerId) => coversLayer(layerId),
      TrackRowAddress() => false,
    };
  }

  int get lengthFrames => endIndexExclusive - startIndex;

  bool contains(int frameIndex) =>
      frameIndex >= startIndex && frameIndex < endIndexExclusive;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineFrameRangeSelection &&
          other.layerId == layerId &&
          other.startIndex == startIndex &&
          other.endIndexExclusive == endIndexExclusive &&
          listEquals(other.layerIds, layerIds) &&
          // [rows] joins the identity, or a drag that grows from a layer row
          // onto its lanes — same layers, same frames, more rows — would
          // compare EQUAL and the notifier would never publish it.
          listEquals(other.rows, rows);

  @override
  int get hashCode => Object.hash(
    layerId,
    startIndex,
    endIndexExclusive,
    Object.hashAll(layerIds),
    Object.hashAll(rows),
  );

  @override
  String toString() =>
      'TimelineFrameRangeSelection($layerId, [$startIndex, '
      '$endIndexExclusive), span: $spanLayerIds)';
}

/// A property-lane selected frame RANGE (UI-R23 #3 part 2; MULTI-LANE
/// since R26 #3): the lane-scoped selection domain within ONE layer's
/// lane group — INDEPENDENT of the layer's frame-range selection (frame
/// selection ⊥ transform keys; the two are mutually exclusive, starting
/// one clears the other). Raw cells, no block snapping (lane keys are
/// points). View state — never persisted.
class TimelineLaneSelection {
  const TimelineLaneSelection({
    required this.layerId,
    required this.laneId,
    required this.startIndex,
    required this.endIndexExclusive,
    this.laneIds = const [],
  }) : assert(endIndexExclusive > startIndex, 'Range must cover frames.');

  final LayerId layerId;

  /// The ANCHOR lane id [transformPropertyLanes] emits ('position',
  /// 'scale', …) — single-lane flows keep reading this.
  final String laneId;
  final int startIndex;
  final int endIndexExclusive;

  /// The lane-row SPAN (R26 #3, the cell selection's layerIds idiom):
  /// display-ordered lanes of the SAME layer from anchor to head. Empty
  /// = the anchor lane alone.
  final List<String> laneIds;

  /// The lanes this selection covers, anchor-only selections included.
  List<String> get spanLaneIds => laneIds.isEmpty ? [laneId] : laneIds;

  int get lengthFrames => endIndexExclusive - startIndex;

  bool contains(int frameIndex) =>
      frameIndex >= startIndex && frameIndex < endIndexExclusive;

  bool coversLane(LayerId layer, String lane) =>
      layer == layerId &&
      (laneIds.isEmpty ? lane == laneId : laneIds.contains(lane));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineLaneSelection &&
          other.layerId == layerId &&
          other.laneId == laneId &&
          other.startIndex == startIndex &&
          other.endIndexExclusive == endIndexExclusive &&
          listEquals(other.laneIds, laneIds);

  @override
  int get hashCode => Object.hash(
    layerId,
    laneId,
    startIndex,
    endIndexExclusive,
    Object.hashAll(laneIds),
  );

  @override
  String toString() =>
      'TimelineLaneSelection($layerId/$laneId, [$startIndex, '
      '$endIndexExclusive), span: $spanLaneIds)';
}

/// The layer's EXPOSURE lane as snap material. Ghost entries are text-only
/// (UI-R23 #6: repeat/hold instances and synced attach mirrors "aren't
/// blocks, they only carry text"), so they resolve as non-extending —
/// a span may land on them, it just never grows for them.
///
/// Resolves through the timeline's SplayTreeMap navigation, so a long row
/// costs O(log n) per drag step rather than a rebuilt block list.
RangeBlock? exposureBlockAt(Layer layer, int index) {
  final block = coveringDrawingBlockAt(layer.timeline, index);
  if (block == null) {
    return null;
  }
  return RangeBlock(
    startIndex: block.startIndex,
    endIndexExclusive: block.endIndexExclusive,
    extendsSelection: !block.entry.ghost,
  );
}

/// The layer's INSTRUCTION lane as snap material (UI-R22 #4: covering one
/// cell of a CAM event selects its whole span, the block rule).
///
/// Scanned rather than navigated: an instruction row holds a handful of
/// chips, and a plain scan keeps the answer right even if two events ever
/// overlap — it returns their UNION, which is what growing for each in turn
/// used to arrive at.
RangeBlock? instructionBlockAt(Layer layer, int index) {
  int? start;
  int? endExclusive;
  for (final entry in layer.instructions.entries) {
    final eventEnd = entry.key + entry.value.length;
    if (entry.key > index || eventEnd <= index) {
      continue;
    }
    start = start == null ? entry.key : math.min(start, entry.key);
    endExclusive = endExclusive == null
        ? eventEnd
        : math.max(endExclusive, eventEnd);
  }
  if (start == null || endExclusive == null) {
    return null;
  }
  return RangeBlock(startIndex: start, endIndexExclusive: endExclusive);
}

/// The block covering [index] in a merged run list — a FOLDER row's lane
/// (R9 #1). A folder holds no timeline of its own: what its band draws is
/// the union of its subtree members' exposures, so that union is also what
/// a range drag on it must snap to. Anything else would snap the selection
/// to blocks the row does not show.
RangeBlock? aggregateRunBlockAt(
  List<({int start, int endExclusive})> runs,
  int index,
) {
  for (final run in runs) {
    if (index >= run.start && index < run.endExclusive) {
      return RangeBlock(
        startIndex: run.start,
        endIndexExclusive: run.endExclusive,
      );
    }
  }
  return null;
}

/// Snaps a raw dragged span to WHOLE blocks on [layer] — THE shared rule
/// ([snapSpanToBlocks]), handed this row's lanes.
///
/// [aggregateRuns] is the folder case: a row whose blocks are derived from
/// its members rather than owned. Empty for every ordinary row.
TimelineFrameRangeSelection? snapFrameRangeToBlocks({
  required Layer layer,
  required int anchorIndex,
  required int headIndex,
  List<({int start, int endExclusive})> aggregateRuns = const [],
}) {
  final span = snapSpanToBlocks(
    lanes: [
      (index) => exposureBlockAt(layer, index),
      (index) => instructionBlockAt(layer, index),
      if (aggregateRuns.isNotEmpty)
        (index) => aggregateRunBlockAt(aggregateRuns, index),
    ],
    anchorIndex: anchorIndex,
    headIndex: headIndex,
  );
  if (span == null) {
    return null;
  }

  return TimelineFrameRangeSelection(
    layerId: layer.id,
    startIndex: span.startIndex,
    endIndexExclusive: span.endIndexExclusive,
  );
}
