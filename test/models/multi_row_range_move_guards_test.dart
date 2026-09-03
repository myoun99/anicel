// A MULTI-ROW MOVE REFUSES A ROW WHOSE CELS ARE LINKED FROM OUTSIDE THE
// RANGE, AND A ROW WHOSE BLOCKS POINT AT CELS THE LAYER DOES NOT HOLD —
// AND ONLY THOSE.
//
// Two survivors of the mutation campaign (2026-09-03): the outside-link
// test's `isDrawing && sameCel` became `||` (ANY drawing outside the range
// refused the move), and the missing-cels guard's `return false` became
// `return true` (the planner carried on without the cels). These pins put
// one cel outside the range each way.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/multi_row_range_move.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

Layer _drawingLayer(String id, Map<int, (String, int)> blocks) {
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

MultiRowRangeMovePlan? _moveRowDown(Layer a) => planMultiRowRangeMove(
  orderedLayers: [a, _drawingLayer('b', {})],
  sourceLayerIds: const [LayerId('a')],
  rangeStartIndex: 0,
  rangeEndIndexExclusive: 1,
  frameDelta: 0,
  rowDelta: 1,
);

void main() {
  test('a different cel outside the range does not block the move', () {
    final a = _drawingLayer('a', {0: ('a0', 1), 5: ('a5', 1)});
    expect(_moveRowDown(a), isNotNull);
  });

  test('the same cel exposed again outside the range blocks the move', () {
    final a = _drawingLayer('a', {0: ('a0', 1), 5: ('a0', 1)});
    expect(_moveRowDown(a), isNull);
  });

  test('a block pointing at a cel the layer does not hold blocks the move', () {
    // Two source rows, and the broken one SECOND: a single broken row is
    // refused by the "nothing selected" guard as well, which is what let
    // the mutant through. With a sound row beside it, only the missing-cel
    // guard refuses — the mutant would move the sound row and drop the
    // broken one on the floor.
    final sound = _drawingLayer('a', {0: ('a0', 1)});
    final broken = Layer(
      id: const LayerId('c'),
      name: 'c',
      frames: const [],
      timeline: {
        0: const TimelineExposure.drawing(FrameId('ghost'), length: 1),
      },
    );
    final plan = planMultiRowRangeMove(
      orderedLayers: [
        sound,
        broken,
        _drawingLayer('b', {}),
        _drawingLayer('d', {}),
      ],
      sourceLayerIds: const [LayerId('a'), LayerId('c')],
      rangeStartIndex: 0,
      rangeEndIndexExclusive: 1,
      frameDelta: 0,
      rowDelta: 2,
    );
    expect(plan, isNull);
  });
}
