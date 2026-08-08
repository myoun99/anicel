import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/drawing_block_move.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// Whole-block move planning. A SAME-LAYER slide follows the shared rank
/// rule — free space re-times, a neighbour's midpoint reorders, nothing is
/// pushed — while a CROSS-LAYER drop carries the cel and shoves the blocks
/// it lands among (leftward pushes clamp at the frame-0 wall).
void main() {
  Layer layerWith(
    String id,
    Map<int, TimelineExposure> timeline, {
    List<String> frameIds = const [],
  }) => Layer(
    id: LayerId(id),
    name: id,
    frames: [
      for (final frameId in frameIds)
        Frame(id: FrameId(frameId), duration: 1, strokes: const []),
    ],
    timeline: timeline,
  );

  group('same-layer slide', () {
    test('remaps the entry and keeps the frames list', () {
      final layer = layerWith(
        'a',
        {0: const TimelineExposure.drawing(FrameId('a-f1'), length: 3)},
        frameIds: ['a-f1'],
      );

      final plan = planDrawingBlockMove(
        source: layer,
        target: layer,
        blockStartIndex: 0,
        frameDelta: 4,
      );

      expect(plan, isNotNull);
      expect(plan!.isCrossLayer, isFalse);
      expect(plan.destinationStartIndex, 4);
      expect(plan.sourceAfter.timeline[0], isNull);
      expect(plan.sourceAfter.timeline[4]!.frameId, const FrameId('a-f1'));
      expect(plan.sourceAfter.timeline[4]!.length, 3);
      expect(plan.sourceAfter.frames, layer.frames);
      expect(plan.movedFrameIds, isEmpty);
    });

    test('rejects a no-op and a fully clamped leftward move', () {
      final layer = layerWith(
        'a',
        {
          0: const TimelineExposure.drawing(FrameId('a-f1'), length: 2),
          5: const TimelineExposure.drawing(FrameId('a-f2'), length: 2),
        },
        frameIds: ['a-f1', 'a-f2'],
      );

      DrawingBlockMovePlan? plan(int delta) => planDrawingBlockMove(
        source: layer,
        target: layer,
        blockStartIndex: 0,
        frameDelta: delta,
      );

      expect(plan(0), isNull, reason: 'zero delta is a no-op');
      expect(
        plan(-1),
        isNull,
        reason: 'the frame-0 wall clamps the move back to its own start',
      );
    });

    test('a drag stops at contact instead of pushing the neighbour', () {
      // a[2,4) b[6,8): dragging b three frames left would put it over a, so
      // it lands touching a instead — and a does not move. The frame axis
      // used to bulldoze here, shoving a toward the wall to make room.
      final layer = layerWith(
        'a',
        {
          2: const TimelineExposure.drawing(FrameId('a-f1'), length: 2),
          6: const TimelineExposure.drawing(FrameId('a-f2'), length: 2),
        },
        frameIds: ['a-f1', 'a-f2'],
      );

      final plan = planDrawingBlockMove(
        source: layer,
        target: layer,
        blockStartIndex: 6,
        frameDelta: -3,
      );

      expect(plan, isNotNull);
      expect(plan!.destinationStartIndex, 4);
      expect(plan.sourceAfter.timeline[2]!.frameId, const FrameId('a-f1'));
      expect(plan.sourceAfter.timeline[4]!.frameId, const FrameId('a-f2'));
      expect(plan.sourceAfter.timeline.length, 2);
    });

    test('reaching past the neighbour\'s midpoint REORDERS instead, and the '
        'two blocks TRADE PLACES (R5 #13)', () {
      // a[0,2) b[3,5) c[6,8). Dragging a three right puts its own midpoint
      // level with b's, so a lands where b was — and b lands where a was.
      // The leading gaps belong to the POSITIONS, so the pair swaps and c
      // never moves. (They used to travel with their block, which put b at
      // 1: neither where a had been nor where b had been.)
      final layer = layerWith(
        'a',
        {
          0: const TimelineExposure.drawing(FrameId('a-f1'), length: 2),
          3: const TimelineExposure.drawing(FrameId('a-f2'), length: 2),
          6: const TimelineExposure.drawing(FrameId('a-f3'), length: 2),
        },
        frameIds: ['a-f1', 'a-f2', 'a-f3'],
      );

      final plan = planDrawingBlockMove(
        source: layer,
        target: layer,
        blockStartIndex: 0,
        frameDelta: 3,
      );

      expect(plan, isNotNull);
      final timeline = plan!.sourceAfter.timeline;
      expect(plan.destinationStartIndex, 3);
      expect(timeline[0]!.frameId, const FrameId('a-f2'));
      expect(timeline[3]!.frameId, const FrameId('a-f1'));
      expect(timeline[6]!.frameId, const FrameId('a-f3'));
      expect(timeline.length, 3);
    });

    test('a far drag is a reorder, not a landing in the space beyond', () {
      // Rightward: a dragged well past b does not park in the empty space
      // out there — it takes b's place, and b takes a's.
      final rightward = layerWith(
        'a',
        {
          0: const TimelineExposure.drawing(FrameId('a-f1'), length: 2),
          5: const TimelineExposure.drawing(FrameId('a-f2'), length: 2),
        },
        frameIds: ['a-f1', 'a-f2'],
      );
      final right = planDrawingBlockMove(
        source: rightward,
        target: rightward,
        blockStartIndex: 0,
        frameDelta: 8,
      );
      expect(right, isNotNull);
      // A clean exchange: a moves to 5 where b was, b to 0 where a was.
      expect(right!.destinationStartIndex, 5);
      expect(right.sourceAfter.timeline[0]!.frameId, const FrameId('a-f2'));
      expect(right.sourceAfter.timeline[5]!.frameId, const FrameId('a-f1'));
      expect(right.sourceAfter.timeline.length, 2);

      // Leftward reads the same way, which is the case the user hit: with
      // eighteen empty frames ahead of the pair, carrying the gaps along
      // dropped the dragged block onto the head of the row instead of into
      // its neighbour's place.
      final leftward = layerWith(
        'a',
        {
          4: const TimelineExposure.drawing(FrameId('a-f1'), length: 2),
          8: const TimelineExposure.drawing(FrameId('a-f2'), length: 2),
        },
        frameIds: ['a-f1', 'a-f2'],
      );
      final left = planDrawingBlockMove(
        source: leftward,
        target: leftward,
        blockStartIndex: 8,
        frameDelta: -7,
      );
      expect(left, isNotNull);
      expect(left!.destinationStartIndex, 4);
      expect(left.sourceAfter.timeline[4]!.frameId, const FrameId('a-f2'));
      expect(left.sourceAfter.timeline[8]!.frameId, const FrameId('a-f1'));
      expect(left.sourceAfter.timeline.length, 2);
    });

    test('R5 #13: the user\'s row — an empty head in front of the pair no '
        'longer swallows the block being dragged', () {
      // Two blocks at the far end of a row that is empty in front of them,
      // which is where the old rule showed itself: the second block's own
      // leading gap is 0, so carrying it to the front parked the block on
      // frame 0 and pushed the eighteen empty frames BETWEEN the two.
      final layer = layerWith(
        'a',
        {
          18: const TimelineExposure.drawing(FrameId('a-f1'), length: 3),
          21: const TimelineExposure.drawing(FrameId('a-f2'), length: 3),
        },
        frameIds: ['a-f1', 'a-f2'],
      );

      final plan = planDrawingBlockMove(
        source: layer,
        target: layer,
        blockStartIndex: 21,
        // Past its neighbour's midpoint, which is what asks for a reorder;
        // -3 alone lands exactly ON it and the rule keeps the order.
        frameDelta: -4,
      );

      expect(plan, isNotNull);
      final timeline = plan!.sourceAfter.timeline;
      expect(plan.destinationStartIndex, 18);
      expect(timeline[18]!.frameId, const FrameId('a-f2'));
      expect(timeline[21]!.frameId, const FrameId('a-f1'));
      expect(
        timeline.length,
        2,
        reason: 'the pair trades places and the empty head stays a head',
      );
    });

    test('a row with no gaps has no free space, so every move is a reorder '
        'and the row\'s total length never changes', () {
      // The storyboard row's shape: blocks tile their span edge to edge.
      final layer = layerWith(
        'a',
        {
          0: const TimelineExposure.drawing(FrameId('a-f1'), length: 3),
          3: const TimelineExposure.drawing(FrameId('a-f2'), length: 2),
          5: const TimelineExposure.drawing(FrameId('a-f3'), length: 4),
        },
        frameIds: ['a-f1', 'a-f2', 'a-f3'],
      );

      final plan = planDrawingBlockMove(
        source: layer,
        target: layer,
        blockStartIndex: 0,
        frameDelta: 3,
      );

      expect(plan, isNotNull);
      final timeline = plan!.sourceAfter.timeline;
      // a and b swapped; the row still tiles [0,9) with no hole and no
      // overhang, which is why a gapless row can never overflow its cut.
      expect(timeline.keys, [0, 2, 5]);
      expect(timeline[0]!.frameId, const FrameId('a-f2'));
      expect(timeline[2]!.frameId, const FrameId('a-f1'));
      expect(timeline[5]!.frameId, const FrameId('a-f3'));
      expect(
        timeline.keys.last + timeline[timeline.keys.last]!.length!,
        9,
        reason: 'the total span is preserved exactly',
      );
    });

    test('a row that TILES its cut cannot drag its last block past the cut '
        'end — the only direction that had no neighbour to stop it', () {
      // A storyboard row covering [0,9): the last block has open axis to
      // its right, so without the cut's end nothing would hold it.
      final layer = Layer(
        id: const LayerId('sb'),
        name: 'SB',
        kind: LayerKind.storyboard,
        frames: [
          Frame(id: const FrameId('sb-f1'), duration: 1, strokes: const []),
          Frame(id: const FrameId('sb-f2'), duration: 1, strokes: const []),
        ],
        timeline: const {
          0: TimelineExposure.drawing(FrameId('sb-f1'), length: 5),
          5: TimelineExposure.drawing(FrameId('sb-f2'), length: 4),
        },
      );

      expect(
        planDrawingBlockMove(
          source: layer,
          target: layer,
          blockStartIndex: 5,
          frameDelta: 3,
          cutFrameCount: 9,
        ),
        isNull,
        reason: 'the row already fills the cut: there is nowhere to go',
      );

      // An ordinary drawing row keeps the open axis — a block may sit past
      // the end of its cut, which is data the cut simply does not show.
      final cel = layerWith(
        'a',
        {
          0: const TimelineExposure.drawing(FrameId('a-f1'), length: 5),
          5: const TimelineExposure.drawing(FrameId('a-f2'), length: 4),
        },
        frameIds: ['a-f1', 'a-f2'],
      );
      final past = planDrawingBlockMove(
        source: cel,
        target: cel,
        blockStartIndex: 5,
        frameDelta: 3,
        cutFrameCount: 9,
      );
      expect(past, isNotNull);
      expect(past!.destinationStartIndex, 8);
    });

    test('block-owned dots ride the moved block for free', () {
      final layer = layerWith(
        'a',
        {
          0: const TimelineExposure.drawing(
            FrameId('a-f1'),
            length: 2,
            breakdownOffsets: [1],
          ),
          6: const TimelineExposure.drawing(FrameId('a-f1'), length: 1),
        },
        frameIds: ['a-f1'],
      );

      final plan = planDrawingBlockMove(
        source: layer,
        target: layer,
        blockStartIndex: 0,
        frameDelta: 3,
      );
      expect(plan, isNotNull);
      expect(plan!.sourceAfter.timeline[3]!.frameId, const FrameId('a-f1'));
      expect(plan.sourceAfter.timeline[3]!.breakdownOffsets, const [1]);
      expect(plan.sourceAfter.timeline.containsKey(0), isFalse);
    });
  });

  group('cross-layer move', () {
    test('carries the cel: timelines and frames update on both layers', () {
      final source = layerWith(
        'a',
        {2: const TimelineExposure.drawing(FrameId('a-f1'), length: 3)},
        frameIds: ['a-f1'],
      );
      final target = layerWith(
        'b',
        {0: const TimelineExposure.drawing(FrameId('b-f1'), length: 2)},
        frameIds: ['b-f1'],
      );

      final plan = planDrawingBlockMove(
        source: source,
        target: target,
        blockStartIndex: 2,
        frameDelta: 1,
      );

      expect(plan, isNotNull);
      expect(plan!.isCrossLayer, isTrue);
      expect(plan.destinationStartIndex, 3);
      expect(plan.movedFrameIds, [const FrameId('a-f1')]);
      expect(plan.sourceAfter.timeline, isEmpty);
      expect(plan.sourceAfter.frames, isEmpty);
      expect(plan.targetAfter!.timeline[3]!.frameId, const FrameId('a-f1'));
      expect(plan.targetAfter!.timeline[3]!.length, 3);
      expect(plan.targetAfter!.frames, hasLength(2));
      // The untouched target block survives.
      expect(plan.targetAfter!.timeline[0]!.frameId, const FrameId('b-f1'));
    });

    test('an occupied landing pushes the target block out of the way '
        '(rightward default)', () {
      final source = layerWith(
        'a',
        {0: const TimelineExposure.drawing(FrameId('a-f1'), length: 3)},
        frameIds: ['a-f1'],
      );
      final target = layerWith(
        'b',
        {2: const TimelineExposure.drawing(FrameId('b-f1'), length: 2)},
        frameIds: ['b-f1'],
      );

      final plan = planDrawingBlockMove(
        source: source,
        target: target,
        blockStartIndex: 0,
        frameDelta: 0,
      );

      expect(plan, isNotNull);
      expect(plan!.destinationStartIndex, 0);
      expect(plan.targetAfter!.timeline[0]!.frameId, const FrameId('a-f1'));
      // [2,4) pushed behind the landed block: [3,5).
      expect(plan.targetAfter!.timeline[3]!.frameId, const FrameId('b-f1'));
      expect(plan.targetAfter!.timeline.length, 2);
    });

    test('rejects a linked cel (another entry references the frame)', () {
      final source = layerWith(
        'a',
        {
          0: const TimelineExposure.drawing(FrameId('a-f1'), length: 2),
          5: const TimelineExposure.drawing(FrameId('a-f1'), length: 1),
        },
        frameIds: ['a-f1'],
      );
      final target = layerWith('b', const {});

      expect(
        planDrawingBlockMove(
          source: source,
          target: target,
          blockStartIndex: 0,
          frameDelta: 0,
        ),
        isNull,
        reason: 'moving the cel would break the link at frame 5',
      );
    });
  });
}
