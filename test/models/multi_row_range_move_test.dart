import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/cel_bank_lanes.dart';
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

/// [layer]'s blocks as `start: cel×length`.
Map<int, String> shown(Layer layer) => {
  for (final MapEntry(:key, :value) in layer.timeline.entries)
    key: '${value.frameId!.value}×${value.length}',
};

/// [rows] moved [rowDelta] rows and [frameDelta] frames from [sources],
/// over `[0, rangeEnd)` — each row after, as [shown] reads it.
Map<String, Map<int, String>>? moved(
  List<Layer> rows,
  List<String> sources, {
  required int rowDelta,
  int frameDelta = 0,
  int rangeEnd = 1,
}) {
  final plan = planMultiRowRangeMove(
    orderedLayers: rows,
    sourceLayerIds: [for (final id in sources) LayerId(id)],
    rangeStartIndex: 0,
    rangeEndIndexExclusive: rangeEnd,
    frameDelta: frameDelta,
    rowDelta: rowDelta,
    bankOf: (_) => CelBankLanes.unshared,
  );
  if (plan == null) {
    return null;
  }
  return {
    for (final row in rows)
      row.id.value: shown(plan.layersAfter[row.id] ?? row),
  };
}

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
      bankOf: (_) => CelBankLanes.unshared,
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
      bankOf: (_) => CelBankLanes.unshared,
    );
    expect(plan, isNotNull);
    expect(blockStarts(plan!.layersAfter[const LayerId('b')]!), [3]);
  });

  // 🗣️F-384-Q1 (유저 2026-10-21): 「덮인 블록이 떠난 자리로 — 자리 바꾸기
  // … 여러 행을 함께 옮기면 덮인 블록이 그 묶음을 건너 반대편 행으로」.
  // ↩️A landing on a block that stays voided the whole move.
  group('🚨the blocks a landing lands on go back across the moved rows', () {
    test('one row: to the row it left, on their own frames', () {
      final a = drawingLayer('a', {0: ('a0', 2)});
      final b = drawingLayer('b', {1: ('b1', 1), 5: ('b5', 1)});
      final plan = planMultiRowRangeMove(
        orderedLayers: [a, b],
        sourceLayerIds: const [LayerId('a')],
        rangeStartIndex: 0,
        rangeEndIndexExclusive: 2,
        frameDelta: 0,
        rowDelta: 1,
        bankOf: (_) => CelBankLanes.unshared,
      )!;
      expect(shown(plan.layersAfter[const LayerId('a')]!), {1: 'b1×1'});
      expect(shown(plan.layersAfter[const LayerId('b')]!), {
        0: 'a0×2',
        5: 'b5×1',
      });
      expect(
        plan.layersAfter[const LayerId('a')]!.frames.map((f) => f.id),
        [const FrameId('b1')],
      );
      expect(plan.rekeys, contains((
        from: const LayerId('b'),
        to: const LayerId('a'),
        frameId: const FrameId('b1'),
      )));
    });

    test('two rows one down: the row entered hands its block to the row '
        'left empty, over the pair', () {
      final rows = [
        drawingLayer('a', {0: ('a0', 1)}),
        drawingLayer('b', {0: ('b0', 1)}),
        drawingLayer('c', {0: ('c0', 1)}),
      ];
      expect(moved(rows, ['a', 'b'], rowDelta: 1), {
        'a': {0: 'c0×1'},
        'b': {0: 'a0×1'},
        'c': {0: 'b0×1'},
      });
      expect(moved(rows, ['b', 'c'], rowDelta: -1), {
        'a': {0: 'b0×1'},
        'b': {0: 'c0×1'},
        'c': {0: 'a0×1'},
      });
    });

    test('rows entered keep their order on the other side — the first '
        'entered to the first left', () {
      final rows = [
        drawingLayer('a', {0: ('a0', 1)}),
        drawingLayer('b', {0: ('b0', 1)}),
        drawingLayer('c', {0: ('c0', 1)}),
        drawingLayer('d', {0: ('d0', 1)}),
        drawingLayer('e', {0: ('e0', 1)}),
      ];
      expect(moved(rows, ['a', 'b', 'c'], rowDelta: 2), {
        'a': {0: 'd0×1'},
        'b': {0: 'e0×1'},
        'c': {0: 'a0×1'},
        'd': {0: 'b0×1'},
        'e': {0: 'c0×1'},
      });
      expect(moved(rows, ['a', 'b'], rowDelta: 3), {
        'a': {0: 'd0×1'},
        'b': {0: 'e0×1'},
        'c': {0: 'c0×1'},
        'd': {0: 'a0×1'},
        'e': {0: 'b0×1'},
      }, reason: 'a row passed over and not landed on is left as it is');
    });

    test('a row the move enters, and not one it still stands on, hands its '
        'blocks over — the first entered to the first left', () {
      final rows = [
        drawingLayer('a', {0: ('a0', 1)}),
        drawingLayer('b', {0: ('b0', 1)}),
        drawingLayer('c', {0: ('c0', 1)}),
        drawingLayer('d', {0: ('d0', 1)}),
        drawingLayer('e', {}),
      ];
      expect(moved(rows, ['a', 'b', 'c'], rowDelta: 2), {
        'a': {0: 'd0×1'},
        'b': <int, String>{},
        'c': {0: 'a0×1'},
        'd': {0: 'b0×1'},
        'e': {0: 'c0×1'},
      });
    });

    test('rows the moved rows still stand on, landed on by the slide, hand '
        'their blocks on down the line to a row left empty — the rows '
        'entered first, then in row order', () {
      final rows = [
        drawingLayer('a', {0: ('a0', 2)}),
        drawingLayer('b', {0: ('b0', 2), 2: ('b2', 2)}),
        drawingLayer('c', {0: ('c0', 2), 2: ('c2', 2)}),
        drawingLayer('d', {2: ('d2', 2)}),
      ];
      expect(
        moved(rows, ['a', 'b', 'c'], rowDelta: 1, frameDelta: 2, rangeEnd: 2),
        {
          'a': {2: 'c2×2', 4: 'b2×2', 6: 'd2×2'},
          'b': {2: 'a0×2'},
          'c': {2: 'b0×2'},
          'd': {2: 'c0×2'},
        },
      );
    });

    test('the sounds go with their cels, both ways', () {
      Layer sounding(Layer row, String cel, String file) => row.copyWith(
        audioClips: [AudioClip(filePath: file, frameId: FrameId(cel))],
      );
      final a = sounding(drawingLayer('a', {0: ('a0', 1)}), 'a0', 'a.wav');
      final b = sounding(drawingLayer('b', {0: ('b0', 1)}), 'b0', 'b.wav');
      final plan = planMultiRowRangeMove(
        orderedLayers: [a, b],
        sourceLayerIds: const [LayerId('a')],
        rangeStartIndex: 0,
        rangeEndIndexExclusive: 1,
        frameDelta: 0,
        rowDelta: 1,
        bankOf: (_) => CelBankLanes.unshared,
      )!;
      List<String> files(String id) => [
        for (final clip in plan.layersAfter[LayerId(id)]!.audioClips)
          clip.filePath,
      ];
      expect(files('a'), ['b.wav']);
      expect(files('b'), ['a.wav']);
    });

    test('a block in a row the moved rows still stand on, landed on only by '
        'the slide along the frames, goes back the way its lander came — '
        'to a row left empty', () {
      final rows = [
        drawingLayer('a', {0: ('a0', 2)}),
        drawingLayer('b', {0: ('b0', 2), 2: ('b2', 2)}),
        drawingLayer('c', {}),
      ];
      expect(moved(rows, ['a', 'b'], rowDelta: 1, frameDelta: 2, rangeEnd: 2), {
        'a': {2: 'b2×2'},
        'b': {2: 'a0×2'},
        'c': {2: 'b0×2'},
      });
    });

    test('a block sent back that meets one staying on its new row: that one '
        'makes way later', () {
      final rows = [
        drawingLayer('a', {0: ('a0', 2), 2: ('a2', 2)}),
        drawingLayer('b', {0: ('b0', 3)}),
      ];
      expect(moved(rows, ['a'], rowDelta: 1, rangeEnd: 2), {
        'a': {0: 'b0×3', 3: 'a2×2'},
        'b': {0: 'a0×2'},
      });
    });
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
      bankOf: (_) => CelBankLanes.unshared,
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
      bankOf: (_) => CelBankLanes.unshared,
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
      bankOf: (_) => CelBankLanes.unshared,
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
      bankOf: (_) => CelBankLanes.unshared,
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
      bankOf: (_) => CelBankLanes.unshared,
    );
    expect(plan, isNull);
  });
}
