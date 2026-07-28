import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';

Frame _frame(String id) =>
    Frame(id: FrameId(id), duration: 1, strokes: const []);

Layer _layer({
  required Map<int, TimelineExposure> timeline,
  List<TimelineRunBehavior> behaviors = const [],
  List<String> frameIds = const ['a', 'b', 'c'],
}) {
  return Layer(
    id: const LayerId('layer-1'),
    name: 'L',
    frames: [for (final id in frameIds) _frame(id)],
    timeline: timeline,
    runBehaviors: behaviors,
  );
}

TimelineExposure _draw(String id, int length) =>
    TimelineExposure.drawing(FrameId(id), length: length);

const _endHold = TimelineRunBehavior(
  anchorFrameId: FrameId('a'),
  side: TimelineRunEdgeSide.end,
  mode: TimelineRunEdgeMode.hold,
);
const _endRepeat = TimelineRunBehavior(
  anchorFrameId: FrameId('a'),
  side: TimelineRunEdgeSide.end,
  mode: TimelineRunEdgeMode.repeat,
);
const _startHold = TimelineRunBehavior(
  anchorFrameId: FrameId('a'),
  side: TimelineRunEdgeSide.start,
  mode: TimelineRunEdgeMode.hold,
);
const _startRepeat = TimelineRunBehavior(
  anchorFrameId: FrameId('a'),
  side: TimelineRunEdgeSide.start,
  mode: TimelineRunEdgeMode.repeat,
);

void main() {
  test('no behaviors and no ghosts returns the SAME layer instance', () {
    final layer = _layer(timeline: {0: _draw('a', 3)});
    expect(
      identical(rederiveRunBehaviors(layer, cutFrameCount: 12), layer),
      isTrue,
    );
  });

  test('end HOLD fills ONE ghost of the last frameId to the cut end', () {
    final layer = _layer(
      timeline: {0: _draw('a', 2), 2: _draw('b', 2)},
      behaviors: const [_endHold],
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 10);
    final ghost = derived.timeline[4]!;
    expect(ghost.ghost, isTrue);
    expect(ghost.frameId, const FrameId('b'));
    expect(ghost.length, 6, reason: 'one block filling [4,10)');
    expect(derived.timeline.keys.where((k) => k > 4), isEmpty);
    expect(derived.runBehaviors, layer.runBehaviors);
  });

  test('end REPEAT cycles the whole run to the cut end, truncating the '
      'tail', () {
    final layer = _layer(
      timeline: {0: _draw('a', 2), 2: _draw('b', 1)},
      behaviors: const [_endRepeat],
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 10);
    // Span 3 cycles at 3 and 6; the cycle at 9 truncates to one frame.
    expect(derived.timeline[3]!.frameId, const FrameId('a'));
    expect(derived.timeline[3]!.length, 2);
    expect(derived.timeline[5]!.frameId, const FrameId('b'));
    expect(derived.timeline[6]!.frameId, const FrameId('a'));
    expect(derived.timeline[8]!.frameId, const FrameId('b'));
    expect(derived.timeline[9]!.frameId, const FrameId('a'));
    expect(derived.timeline[9]!.length, 1);
    for (final key in derived.timeline.keys.where((k) => k >= 3)) {
      expect(derived.timeline[key]!.ghost, isTrue, reason: 'key $key');
    }
  });

  test('end ghosts CLAMP before the next authored block', () {
    final layer = _layer(
      timeline: {0: _draw('a', 2), 5: _draw('c', 1)},
      behaviors: const [_endHold],
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 12);
    expect(derived.timeline[2]!.ghost, isTrue);
    expect(derived.timeline[2]!.length, 3, reason: 'clamped at 5');
    expect(derived.timeline[5]!.ghost, isFalse);
  });

  test('a fully occluded behavior keeps its spec (self-restoring)', () {
    final atCutEnd = rederiveRunBehaviors(
      _layer(timeline: {0: _draw('a', 2)}, behaviors: const [_endHold]),
      cutFrameCount: 2,
    );
    expect(atCutEnd.timeline.values.any((entry) => entry.ghost), isFalse);
    expect(atCutEnd.runBehaviors, hasLength(1), reason: 'spec survives');

    // Room opens up again: the tail comes back.
    final reopened = rederiveRunBehaviors(atCutEnd, cutFrameCount: 6);
    expect(reopened.timeline[2]!.ghost, isTrue);
    expect(reopened.timeline[2]!.length, 4);
  });

  test('a vanished anchor drops the behavior (self-healing)', () {
    final layer = _layer(
      timeline: {0: _draw('b', 2)},
      behaviors: const [_endHold], // Anchored on missing frame a.
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 12);
    expect(derived.runBehaviors, isEmpty);
  });

  test('start HOLD fills one ghost of the FIRST frameId back to frame 0', () {
    final layer = _layer(
      timeline: {4: _draw('a', 2), 6: _draw('b', 1)},
      behaviors: const [_startHold],
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 12);
    final ghost = derived.timeline[0]!;
    expect(ghost.ghost, isTrue);
    expect(ghost.frameId, const FrameId('a'));
    expect(ghost.length, 4);
  });

  test('start REPEAT tiles FLUSH against the run start: the partial '
      'lead-in cycle shows the pattern TAIL', () {
    final layer = _layer(
      timeline: {5: _draw('a', 2), 7: _draw('b', 1)},
      behaviors: const [_startRepeat],
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 12);
    // Span 3 tiles left from 5: cycle [2,5) = a@2,b@4; the partial cycle
    // [-1,2) clips to its visible tail: a@0 (one frame of two), b@1.
    expect(derived.timeline[2]!.frameId, const FrameId('a'));
    expect(derived.timeline[2]!.length, 2);
    expect(derived.timeline[4]!.frameId, const FrameId('b'));
    expect(derived.timeline[0]!.frameId, const FrameId('a'));
    expect(derived.timeline[0]!.length, 1, reason: 'clipped lead-in');
    expect(derived.timeline[1]!.frameId, const FrameId('b'));
    for (final key in derived.timeline.keys.where((k) => k < 5)) {
      expect(derived.timeline[key]!.ghost, isTrue, reason: 'key $key');
    }
  });

  test('start ghosts clamp against the previous authored block', () {
    final layer = _layer(
      timeline: {0: _draw('c', 2), 6: _draw('a', 2)},
      behaviors: const [_startHold],
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 12);
    expect(derived.timeline[2]!.ghost, isTrue);
    expect(derived.timeline[2]!.length, 4, reason: 'fills [2,6) only');
    expect(derived.timeline[0]!.ghost, isFalse);
  });

  test('the pattern anchor scopes an end repeat to the selection span', () {
    final layer = _layer(
      timeline: {0: _draw('a', 1), 1: _draw('b', 1), 2: _draw('c', 1)},
      behaviors: const [
        TimelineRunBehavior(
          anchorFrameId: FrameId('a'),
          side: TimelineRunEdgeSide.end,
          mode: TimelineRunEdgeMode.repeat,
          patternAnchorFrameId: FrameId('b'),
        ),
      ],
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 7);
    // Pattern = [b, c] → b,c cycling after the run.
    expect(derived.timeline[3]!.frameId, const FrameId('b'));
    expect(derived.timeline[4]!.frameId, const FrameId('c'));
    expect(derived.timeline[5]!.frameId, const FrameId('b'));
    expect(derived.timeline[6]!.frameId, const FrameId('c'));
    expect(derived.timeline.containsKey(7), isFalse);
  });

  test('GHOST GLUE: a comma shrink of the source run re-glues the tail '
      'with no gap (the pattern IS the live run)', () {
    final layer = rederiveRunBehaviors(
      _layer(timeline: {0: _draw('a', 4)}, behaviors: const [_endRepeat]),
      cutFrameCount: 12,
    );
    expect(layer.timeline[4]!.ghost, isTrue);

    // Shrink the source block 4 → 2 (what a comma drag commits), then
    // rederive (the edit choke point does this on every commit).
    final shrunk = rederiveRunBehaviors(
      layer.copyWith(
        timeline: {
          for (final entry in layer.timeline.entries)
            if (!entry.value.ghost)
              entry.key: entry.key == 0
                  ? entry.value.copyWith(length: 2)
                  : entry.value,
        },
      ),
      cutFrameCount: 12,
    );

    // The tail re-attaches at the NEW run end — zero gap.
    expect(shrunk.timeline[2]!.ghost, isTrue);
    expect(shrunk.timeline[2]!.length, 2);
    expect(shrunk.timeline[4]!.ghost, isTrue);
    var covered = 0;
    for (final entry in shrunk.timeline.entries) {
      expect(entry.key, covered, reason: 'no gap before ${entry.key}');
      covered = entry.key + entry.value.length!;
    }
    expect(covered, 12, reason: 'ghosts refill to the cut end');
  });

  test('a cut duration change refills the tail (longer AND shorter)', () {
    final layer = rederiveRunBehaviors(
      _layer(timeline: {0: _draw('a', 2)}, behaviors: const [_endHold]),
      cutFrameCount: 6,
    );
    expect(layer.timeline[2]!.length, 4);

    final longer = rederiveRunBehaviors(layer, cutFrameCount: 10);
    expect(longer.timeline[2]!.length, 8);

    final shorter = rederiveRunBehaviors(layer, cutFrameCount: 3);
    expect(shorter.timeline[2]!.length, 1);
  });

  test('ghost copies carry the source block dots, clamped to the ghost '
      'length', () {
    final layer = _layer(
      timeline: {
        0: TimelineExposure.drawing(
          const FrameId('a'),
          length: 3,
          breakdownOffsets: const [1, 2],
        ),
      },
      behaviors: const [_endRepeat],
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 8);
    expect(derived.timeline[3]!.breakdownOffsets, const [1, 2]);
    // The truncated cycle at 6 keeps only what its length spares.
    expect(derived.timeline[6]!.length, 2);
    expect(derived.timeline[6]!.breakdownOffsets, const [1]);
  });

  test('both edges of one run derive together; holds apply first, and the '
      'end repeat cycles the DISPLAYED run — front hold included '
      '(UI-R13 #5)', () {
    final layer = _layer(
      timeline: {4: _draw('a', 2)},
      behaviors: const [_startHold, _endRepeat],
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 10);
    expect(derived.timeline[0]!.ghost, isTrue);
    expect(derived.timeline[0]!.length, 4, reason: 'the front-hold lead-in');
    // The repeated unit is hold(4f) + block(2f) = 6 frames; the tail
    // space [6,10) fits the cycle's first part — the 4f hold copy.
    expect(derived.timeline[6]!.ghost, isTrue);
    expect(derived.timeline[6]!.length, 4);
    expect(timelineIndexIsGhost(derived, 8), isTrue,
        reason: 'covered by the cycled hold copy, not a separate entry');
    expect(derived.timeline[8], isNull);
  });

  test('a START repeat cycles the displayed run too: the rear-hold tail '
      'joins the pattern (UI-R13 #5 mirror)', () {
    final layer = _layer(
      timeline: {6: _draw('a', 2)},
      behaviors: const [
        TimelineRunBehavior(
          anchorFrameId: FrameId('a'),
          side: TimelineRunEdgeSide.end,
          mode: TimelineRunEdgeMode.hold,
        ),
        TimelineRunBehavior(
          anchorFrameId: FrameId('a'),
          side: TimelineRunEdgeSide.start,
          mode: TimelineRunEdgeMode.repeat,
        ),
      ],
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 10);
    // Rear hold: [8,10) ghost. Pattern = block(2f) + hold(2f) = 4 frames,
    // tiled flush leftward over the [0,6) lead-in: cycle at 2 = block copy
    // [2,4) + hold copy [4,6); the leftmost partial keeps the TAIL — the
    // hold copy lands [0,2) (the block part is fully cut off).
    expect(derived.timeline[8]!.ghost, isTrue, reason: 'the rear hold');
    expect(derived.timeline[8]!.length, 2);
    expect(derived.timeline[2]!.ghost, isTrue);
    expect(derived.timeline[2]!.length, 2, reason: 'cycled block copy');
    expect(derived.timeline[4]!.ghost, isTrue);
    expect(derived.timeline[4]!.length, 2, reason: 'cycled hold copy');
    expect(derived.timeline[0]!.ghost, isTrue);
    expect(derived.timeline[0]!.length, 2,
        reason: 'partial lead-in keeps the pattern tail (the hold part)');
  });

  test('setting the same edge twice: the LAST spec wins the dedupe', () {
    final layer = _layer(
      timeline: {0: _draw('a', 2)},
      behaviors: const [_endRepeat, _endHold],
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 8);
    expect(derived.runBehaviors, const [_endHold]);
    expect(derived.timeline[2]!.length, 6, reason: 'one hold block');
  });

  test('run behaviors round-trip through Layer JSON; legacy repeatRegions '
      'JSON is ignored', () {
    final layer = _layer(
      timeline: {0: _draw('a', 2)},
      behaviors: const [
        TimelineRunBehavior(
          anchorFrameId: FrameId('a'),
          side: TimelineRunEdgeSide.end,
          mode: TimelineRunEdgeMode.repeat,
          patternAnchorFrameId: FrameId('a'),
        ),
      ],
    );

    final restored = Layer.fromJson(layer.toJson());
    expect(restored, layer);
    expect(
      restored.runBehaviors.single.patternAnchorFrameId,
      const FrameId('a'),
    );

    final legacyJson = _layer(timeline: {0: _draw('a', 2)}).toJson();
    legacyJson['repeatRegions'] = [
      {
        'id': 'r1',
        'anchor': {'value': 'a'},
        'sourceSpanFrames': 2,
        'frameCount': 4,
      },
    ];
    expect(Layer.fromJson(legacyJson).runBehaviors, isEmpty);
  });

  test('runEdgeBehaviorAt resolves the edge through the LIVE run', () {
    final layer = rederiveRunBehaviors(
      _layer(
        timeline: {0: _draw('a', 2), 2: _draw('b', 1)},
        behaviors: const [_endHold],
      ),
      cutFrameCount: 8,
    );

    // Both blocks of the glued run answer for the run's edges.
    expect(
      runEdgeBehaviorAt(layer, 0, TimelineRunEdgeSide.end)?.mode,
      TimelineRunEdgeMode.hold,
    );
    expect(
      runEdgeBehaviorAt(layer, 2, TimelineRunEdgeSide.end)?.mode,
      TimelineRunEdgeMode.hold,
    );
    expect(runEdgeBehaviorAt(layer, 0, TimelineRunEdgeSide.start), isNull);
  });
}
