import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/multi_row_range_move.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// A drawing layer whose [blocks] map each start index to (frameId, length).
Layer drawingLayer(String id, Map<int, (String, int)> blocks) {
  final frameIds = <String>{for (final block in blocks.values) block.$1};
  return Layer(
    id: LayerId(id),
    name: id,
    frames: [
      for (final frameId in frameIds)
        Frame(id: FrameId(frameId), duration: 1, strokes: const []),
    ],
    timeline: {
      for (final entry in blocks.entries)
        entry.key: TimelineExposure.drawing(
          FrameId(entry.value.$1),
          length: entry.value.$2,
        ),
    },
  );
}

List<int> blockStarts(Layer layer) =>
    [for (final block in drawingBlocks(layer.timeline)) block.startIndex];

void main() {
  test('rigid down-shift: two source rows carry their blocks one row down', () {
    final a = drawingLayer('a', {0: ('a0', 1)});
    final b = drawingLayer('b', {0: ('b0', 1)});
    final c = drawingLayer('c', {});
    final plan = planMultiRowRangeMove(
      orderedLayers: [a, b, c],
      sourceLayerIds: const [LayerId('a'), LayerId('b')],
      rangeStartIndex: 0,
      rangeEndIndexExclusive: 1,
      frameDelta: 0,
      rowDelta: 1,
    );
    expect(plan, isNotNull);
    // A empties; B receives A's cel; C receives B's cel.
    expect(blockStarts(plan!.layersAfter[const LayerId('a')]!), isEmpty);
    expect(plan.layersAfter[const LayerId('b')]!.timeline[0]!.frameId,
        const FrameId('a0'));
    expect(plan.layersAfter[const LayerId('c')]!.timeline[0]!.frameId,
        const FrameId('b0'));
    // The cels (and their brush frames) travel with their blocks.
    expect(
      plan.layersAfter[const LayerId('b')]!.frames.map((f) => f.id),
      contains(const FrameId('a0')),
    );
    expect(plan.rekeys, contains((
      from: const LayerId('a'),
      to: const LayerId('b'),
      frameId: const FrameId('a0'),
    )));
    expect(plan.rekeys, contains((
      from: const LayerId('b'),
      to: const LayerId('c'),
      frameId: const FrameId('b0'),
    )));
  });

  test('the frame axis rides along: rowDelta and frameDelta compose', () {
    final a = drawingLayer('a', {0: ('a0', 1)});
    final b = drawingLayer('b', {});
    final plan = planMultiRowRangeMove(
      orderedLayers: [a, b],
      sourceLayerIds: const [LayerId('a')],
      rangeStartIndex: 0,
      rangeEndIndexExclusive: 1,
      frameDelta: 3,
      rowDelta: 1,
    );
    expect(plan, isNotNull);
    expect(blockStarts(plan!.layersAfter[const LayerId('b')]!), [3]);
  });

  test('any illegal landing voids the WHOLE move: an incoming block '
      'overlapping a block that STAYS is rejected (no push)', () {
    final a = drawingLayer('a', {0: ('a0', 2)});
    // B keeps a block at 1 that A's [0,2) landing would overlap.
    final b = drawingLayer('b', {1: ('b1', 1)});
    final plan = planMultiRowRangeMove(
      orderedLayers: [a, b],
      sourceLayerIds: const [LayerId('a')],
      rangeStartIndex: 0,
      rangeEndIndexExclusive: 2,
      frameDelta: 0,
      rowDelta: 1,
    );
    expect(plan, isNull);
  });

  test('a CONTENT row mapping off the lattice voids the move', () {
    final a = drawingLayer('a', {0: ('a0', 1)});
    final b = drawingLayer('b', {0: ('b0', 1)});
    final plan = planMultiRowRangeMove(
      orderedLayers: [a, b],
      sourceLayerIds: const [LayerId('a'), LayerId('b')],
      rangeStartIndex: 0,
      rangeEndIndexExclusive: 1,
      frameDelta: 0,
      rowDelta: 1, // b -> off the bottom
    );
    expect(plan, isNull);
  });

  test('EMPTY rows in the span never block (UI-R24 #3): only the frames '
      'inside the selection move — an empty last row needs no landing', () {
    final a = drawingLayer('a', {0: ('a0', 1)});
    final b = drawingLayer('b', {}); // selected but empty
    final plan = planMultiRowRangeMove(
      orderedLayers: [a, b],
      sourceLayerIds: const [LayerId('a'), LayerId('b')],
      rangeStartIndex: 0,
      rangeEndIndexExclusive: 1,
      frameDelta: 0,
      rowDelta: 1, // b would map off the bottom — but it carries nothing
    );
    expect(plan, isNotNull);
    expect(plan!.layersAfter[const LayerId('a')]!.timeline.keys, isEmpty);
    expect(
      plan.layersAfter[const LayerId('b')]!.timeline[0]!.frameId,
      const FrameId('a0'),
    );
    // The empty row contributed nothing — no rekeys from it.
    expect(plan.rekeys.map((r) => r.from).toSet(), {const LayerId('a')});
  });

  test('a landing below frame 0 voids the move', () {
    final a = drawingLayer('a', {2: ('a2', 1)});
    final b = drawingLayer('b', {});
    final plan = planMultiRowRangeMove(
      orderedLayers: [a, b],
      sourceLayerIds: const [LayerId('a')],
      rangeStartIndex: 2,
      rangeEndIndexExclusive: 3,
      frameDelta: -5,
      rowDelta: 1,
    );
    expect(plan, isNull);
  });

  test('a cel linked from OUTSIDE the moved set voids the move', () {
    // a0 is exposed both inside the range (0) and outside it (5): moving it
    // cross-row would split the link.
    final a = drawingLayer('a', {0: ('a0', 1), 5: ('a0', 1)});
    final b = drawingLayer('b', {});
    final plan = planMultiRowRangeMove(
      orderedLayers: [a, b],
      sourceLayerIds: const [LayerId('a')],
      rangeStartIndex: 0,
      rangeEndIndexExclusive: 1,
      frameDelta: 0,
      rowDelta: 1,
    );
    expect(plan, isNull);
  });

  test('rowDelta 0 (a pure slide) is not a multi-row move', () {
    final a = drawingLayer('a', {0: ('a0', 1)});
    final plan = planMultiRowRangeMove(
      orderedLayers: [a],
      sourceLayerIds: const [LayerId('a')],
      rangeStartIndex: 0,
      rangeEndIndexExclusive: 1,
      frameDelta: 2,
      rowDelta: 0,
    );
    expect(plan, isNull);
  });
}
