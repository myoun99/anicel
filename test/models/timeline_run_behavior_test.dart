import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';

import '../helpers/run_edge_fixtures.dart';

Frame _frame(String id) =>
    Frame(id: FrameId(id), duration: 1, strokes: const []);

Layer _layer({
  required Map<int, TimelineExposure> timeline,
  List<String> frameIds = const ['a', 'b', 'c'],
}) {
  return Layer(
    id: const LayerId('layer-1'),
    name: 'L',
    frames: [for (final id in frameIds) _frame(id)],
    timeline: timeline,
  );
}

/// A block of drawing [id] carrying [start] and [end] marks.
TimelineExposure _draw(
  String id,
  int length, {
  TimelineRunEdgeMark start = TimelineRunEdgeMark.none,
  TimelineRunEdgeMark end = TimelineRunEdgeMark.none,
}) => TimelineExposure.drawing(
  FrameId(id),
  length: length,
  startEdge: start,
  endEdge: end,
);

void main() {
  test('no marks and no ghosts returns the SAME layer instance', () {
    final layer = _layer(timeline: {0: _draw('a', 3)});
    expect(
      identical(rederiveRunBehaviors(layer, cutFrameCount: 12), layer),
      isTrue,
    );
  });

  test('end HOLD fills ONE ghost of the last frameId to the cut end — '
      'whichever block of the run carries it', () {
    final layer = _layer(
      timeline: {0: _draw('a', 2, end: holdMark), 2: _draw('b', 2)},
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 10);
    final ghost = derived.timeline[4]!;
    expect(ghost.ghostOf, endHoldGhost);
    expect(ghost.frameId, const FrameId('b'));
    expect(ghost.length, 6, reason: 'one block filling [4,10)');
    expect(derived.timeline.keys.where((k) => k > 4), isEmpty);
    expect(derived.timeline[0]!.endEdge, holdMark, reason: 'the mark stays');
  });

  test('end REPEAT cycles the whole run to the cut end, truncating the '
      'tail', () {
    final layer = _layer(
      timeline: {0: _draw('a', 2, end: repeatMark), 2: _draw('b', 1)},
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
      expect(derived.timeline[key]!.ghostOf, endRepeatGhost, reason: 'key $key');
    }
  });

  test('end ghosts CLAMP before the next authored block', () {
    final layer = _layer(
      timeline: {0: _draw('a', 2, end: holdMark), 5: _draw('c', 1)},
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 12);
    expect(derived.timeline[2]!.ghost, isTrue);
    expect(derived.timeline[2]!.length, 3, reason: 'clamped at 5');
    expect(derived.timeline[5]!.ghost, isFalse);
  });

  test('a fully occluded side keeps its mark (self-restoring)', () {
    final atCutEnd = rederiveRunBehaviors(
      _layer(timeline: {0: _draw('a', 2, end: holdMark)}),
      cutFrameCount: 2,
    );
    expect(atCutEnd.timeline.values.any((entry) => entry.ghost), isFalse);
    expect(atCutEnd.timeline[0]!.endEdge, holdMark, reason: 'mark survives');

    // Room opens up again: the tail comes back.
    final reopened = rederiveRunBehaviors(atCutEnd, cutFrameCount: 6);
    expect(reopened.timeline[2]!.ghost, isTrue);
    expect(reopened.timeline[2]!.length, 4);
  });

  test('a deleted carrier takes its property with it (self-healing)', () {
    final held = rederiveRunBehaviors(
      _layer(timeline: {0: _draw('a', 2), 2: _draw('b', 1, end: holdMark)}),
      cutFrameCount: 12,
    );
    expect(held.timeline[3]!.ghost, isTrue, reason: 'LIVENESS — it holds');

    final withoutCarrier = rederiveRunBehaviors(
      held.copyWith(timeline: {0: held.timeline[0]!}),
      cutFrameCount: 12,
    );
    expect(withoutCarrier.timeline.keys, [0]);
    expect(withoutCarrier.timeline[0]!.endEdge.isNone, isTrue);
  });

  test('start HOLD fills one ghost of the FIRST frameId back to frame 0', () {
    final layer = _layer(
      timeline: {4: _draw('a', 2, start: holdMark), 6: _draw('b', 1)},
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 12);
    final ghost = derived.timeline[0]!;
    expect(ghost.ghostOf, startHoldGhost);
    expect(ghost.frameId, const FrameId('a'));
    expect(ghost.length, 4);
  });

  test('start REPEAT tiles FLUSH against the run start: the partial '
      'lead-in cycle shows the pattern TAIL', () {
    final layer = _layer(
      timeline: {5: _draw('a', 2, start: repeatMark), 7: _draw('b', 1)},
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
      expect(
        derived.timeline[key]!.ghostOf,
        startRepeatGhost,
        reason: 'key $key',
      );
    }
  });

  test('start ghosts clamp against the previous authored block', () {
    final layer = _layer(
      timeline: {0: _draw('c', 2), 6: _draw('a', 2, start: holdMark)},
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 12);
    expect(derived.timeline[2]!.ghost, isTrue);
    expect(derived.timeline[2]!.length, 4, reason: 'fills [2,6) only');
    expect(derived.timeline[0]!.ghost, isFalse);
  });

  test('the pattern bound scopes an end repeat to the selection span', () {
    final layer = _layer(
      timeline: {
        0: _draw('a', 1),
        1: _draw('b', 1, end: boundMark),
        2: _draw('c', 1, end: repeatMark),
      },
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
      _layer(timeline: {0: _draw('a', 4, end: repeatMark)}),
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
      _layer(timeline: {0: _draw('a', 2, end: holdMark)}),
      cutFrameCount: 6,
    );
    expect(layer.timeline[2]!.length, 4);

    final longer = rederiveRunBehaviors(layer, cutFrameCount: 10);
    expect(longer.timeline[2]!.length, 8);

    final shorter = rederiveRunBehaviors(layer, cutFrameCount: 3);
    expect(shorter.timeline[2]!.length, 1);
  });

  test('ghost copies carry the source block dots, clamped to the ghost '
      'length — and never its marks', () {
    final layer = _layer(
      timeline: {
        0: const TimelineExposure.drawing(
          FrameId('a'),
          length: 3,
          breakdownOffsets: [1, 2],
          endEdge: repeatMark,
        ),
      },
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 8);
    expect(derived.timeline[3]!.breakdownOffsets, const [1, 2]);
    // The truncated cycle at 6 keeps only what its length spares.
    expect(derived.timeline[6]!.length, 2);
    expect(derived.timeline[6]!.breakdownOffsets, const [1]);
    expect(
      derived.timeline[3]!.endEdge.isNone,
      isTrue,
      reason: 'a ghost is a property\'s output, never a carrier',
    );
  });

  test('both edges of one run derive together; holds apply first, and the '
      'end repeat cycles the DISPLAYED run — front hold included '
      '(UI-R13 #5)', () {
    final layer = _layer(
      timeline: {4: _draw('a', 2, start: holdMark, end: repeatMark)},
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 10);
    expect(derived.timeline[0]!.ghost, isTrue);
    expect(derived.timeline[0]!.length, 4, reason: 'the front-hold lead-in');
    // The repeated unit is hold(4f) + block(2f) = 6 frames; the tail
    // space [6,10) fits the cycle's first part — the 4f hold copy.
    expect(derived.timeline[6]!.ghost, isTrue);
    expect(derived.timeline[6]!.length, 4);
    expect(
      timelineIndexIsGhost(derived, 8),
      isTrue,
      reason: 'covered by the cycled hold copy, not a separate entry',
    );
    expect(derived.timeline[8], isNull);
  });

  test('a START repeat cycles the displayed run too: the rear-hold tail '
      'joins the pattern (UI-R13 #5 mirror)', () {
    final layer = _layer(
      timeline: {6: _draw('a', 2, start: repeatMark, end: holdMark)},
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
    expect(
      derived.timeline[0]!.length,
      2,
      reason: 'partial lead-in keeps the pattern tail (the hold part)',
    );
  });

  test('a pattern bound ON the run\'s first block is INSIDE the run', () {
    // ⛔The carrier's OWN bound counts. The first block of the run is a legal
    // pattern bound — picking it is how a start repeat says "cycle just this
    // one frame" — and a resolution that looked only past the carrier
    // silently falls back to the whole run, which looks plausible on screen.
    final layer = _layer(
      timeline: {
        5: _draw('a', 1, start: repeatBoundMark),
        6: _draw('b', 1),
        7: _draw('c', 1),
      },
    );

    final derived = rederiveRunBehaviors(layer, cutFrameCount: 8);
    // Pattern = [a] alone, tiled leftward over [0,5).
    for (var index = 0; index < 5; index += 1) {
      expect(
        derived.timeline[index]!.frameId,
        const FrameId('a'),
        reason: 'frame $index cycles the bound block alone',
      );
    }
  });

  group('several carriers on one side — two runs glued into one', () {
    test('the carrier NEAREST the edge wins, and the other gives its mark '
        'up', () {
      final layer = _layer(
        timeline: {
          0: _draw('a', 2, end: repeatMark),
          2: _draw('b', 1, end: holdMark),
        },
      );

      final derived = rederiveRunBehaviors(layer, cutFrameCount: 8);
      expect(derived.timeline[3]!.ghostOf, endHoldGhost);
      expect(derived.timeline[3]!.length, 5, reason: 'one hold block');
      expect(
        derived.timeline[0]!.endEdge.isNone,
        isTrue,
        reason: 'the inner carrier is stripped',
      );
      expect(derived.timeline[2]!.endEdge, holdMark);
    });

    test('the START side mirrors it: the leftmost carrier wins', () {
      final layer = _layer(
        timeline: {
          4: _draw('a', 1, start: repeatMark),
          5: _draw('b', 1, start: holdMark),
        },
      );

      final derived = rederiveRunBehaviors(layer, cutFrameCount: 8);
      // The whole run [4,6) tiles flush leftward over [0,4).
      expect(derived.timeline[0]!.ghostOf, startRepeatGhost);
      expect(derived.timeline[0]!.frameId, const FrameId('a'));
      expect(derived.timeline[4]!.startEdge, repeatMark);
      expect(derived.timeline[5]!.startEdge.isNone, isTrue);
    });

    test('a bound past ANOTHER carrier is stray: the pattern is the whole '
        'run, and the bound is stripped', () {
      final layer = _layer(
        timeline: {
          0: _draw('a', 1, end: boundMark),
          1: _draw('b', 1, end: holdMark),
          2: _draw('c', 1, end: repeatMark),
        },
      );

      final derived = rederiveRunBehaviors(layer, cutFrameCount: 9);
      // c wins; walking back from it meets b — another carrier — before a's
      // bound, so the pattern is the whole run [0,3).
      for (final (index, id) in [(3, 'a'), (4, 'b'), (5, 'c'), (6, 'a')]) {
        expect(derived.timeline[index]!.frameId, FrameId(id), reason: '$index');
      }
      expect(derived.timeline[0]!.endEdge.isNone, isTrue);
      expect(derived.timeline[1]!.endEdge.isNone, isTrue);
      expect(derived.timeline[2]!.endEdge, repeatMark);
    });

    test('a run no carrier speaks for keeps no bound', () {
      final derived = rederiveRunBehaviors(
        _layer(timeline: {0: _draw('a', 1, end: boundMark)}),
        cutFrameCount: 4,
      );
      expect(derived.timeline.keys, [0]);
      expect(derived.timeline[0]!.endEdge.isNone, isTrue);
    });
  });

  group('F-134: the property belongs to the BLOCK, not to its drawing', () {
    test('a block showing the carrier\'s drawing EARLIER on the row does not '
        'take the property', () {
      // 「붙여넣어진 프레임의 +버튼이나 성질버튼이 없음」 — a spec that named its
      // run by the drawing settled on the LOWEST block showing it.
      final layer = _layer(
        timeline: {
          0: _draw('b', 1),
          5: _draw('a', 1),
          6: _draw('b', 1, end: holdMark),
        },
      );

      final derived = rederiveRunBehaviors(layer, cutFrameCount: 10);
      expect(
        derived.timeline[1],
        isNull,
        reason: 'the copy at 0 holds nothing',
      );
      expect(derived.timeline[7]!.ghostOf, endHoldGhost);
      expect(derived.timeline[7]!.length, 3);
    });

    test('changing the drawing under a carrier keeps its property — the '
        'relink a join by name makes', () {
      // 「이름바꿔서 링크프레임 작동시키면 성질 사라짐」.
      final held = rederiveRunBehaviors(
        _layer(timeline: {0: _draw('a', 1, end: holdMark)}),
        cutFrameCount: 4,
      );
      final relinked = rederiveRunBehaviors(
        held.copyWith(
          timeline: {
            0: held.timeline[0]!.copyWith(frameId: const FrameId('b')),
          },
        ),
        cutFrameCount: 4,
      );
      expect(relinked.timeline[0]!.endEdge, holdMark);
      expect(relinked.timeline[1]!.ghostOf, endHoldGhost);
      expect(relinked.timeline[1]!.frameId, const FrameId('b'));
    });
  });

  test('run edge marks round-trip through Layer JSON; the retired spec lists '
      'and the ghosts saved before F-134 are dropped', () {
    final layer = rederiveRunBehaviors(
      _layer(timeline: {0: _draw('a', 2, end: repeatBoundMark)}),
      cutFrameCount: 6,
    );
    expect(layer.timeline[2]!.ghostOf, endRepeatGhost, reason: 'LIVENESS');

    final restored = Layer.fromJson(layer.toJson());
    expect(restored, layer);
    expect(restored.timeline[0]!.endEdge, repeatBoundMark);

    final legacyJson = _layer(timeline: {0: _draw('a', 2)}).toJson();
    legacyJson['repeatRegions'] = [
      {
        'id': 'r1',
        'anchor': {'value': 'a'},
        'sourceSpanFrames': 2,
        'frameCount': 4,
      },
    ];
    legacyJson['runBehaviors'] = [
      {
        'anchor': {'value': 'a'},
        'side': 'end',
        'mode': 'hold',
      },
    ];
    (legacyJson['timeline'] as List).add({
      'index': 2,
      'exposure': {
        'type': 'drawing',
        'frameId': {'value': 'a'},
        'length': 4,
        'ghost': true,
        'ghostOwner': 'a:end',
      },
    });
    final legacy = Layer.fromJson(legacyJson);
    expect(
      legacy.timeline.keys,
      [0],
      reason: 'a pre-F-134 ghost must not read back as an AUTHORED block',
    );
    expect(legacy.timeline[0]!.endEdge.isNone, isTrue);
  });

  test('runEdgeBehaviorAt resolves the edge through the LIVE run', () {
    final layer = rederiveRunBehaviors(
      _layer(timeline: {0: _draw('a', 2), 2: _draw('b', 1, end: holdMark)}),
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
