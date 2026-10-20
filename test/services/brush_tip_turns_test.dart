import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_order.dart';
import 'package:anicel/src/services/brush_tip_turns.dart';

/// F-176-Q3 (「클튜 여섯 전부 + 끌어서 순서」): which tip each dab of one
/// stroke takes, by Clip Studio's 繰り返し方法 — the six orders, written
/// once (`BrushTipTurns`) for the canvas and the swatch alike.
void main() {
  BrushTipMask tip(String id) =>
      BrushTipMask(id: id, size: 2, alpha: Uint8List.fromList([1, 2, 3, 4]));

  final abc = [tip('a'), tip('b'), tip('c')];

  /// The tips [count] dabs take, one letter each — `-` for a dab that is
  /// not drawn.
  String taken(
    List<BrushTipMask> tips,
    BrushTipOrder order,
    int count, {
    int seed = 7,
  }) {
    final turns = BrushTipTurns.of(tips, order, random: math.Random(seed))!;
    return [
      for (var dab = 0; dab < count; dab += 1) turns.next()?.id ?? '-',
    ].join();
  }

  test('繰り返し goes round and round', () {
    expect(taken(abc, BrushTipOrder.repeat, 7), 'abcabca');
  });

  test('折り返し comes back the way it went, the end tips once each', () {
    expect(taken(abc, BrushTipOrder.pingPong, 9), 'abcbabcba');
    expect(taken(abc.take(2).toList(), BrushTipOrder.pingPong, 4), 'abab');
  });

  test('繰り返さない keeps the last tip once the others ran', () {
    expect(taken(abc, BrushTipOrder.holdLast, 6), 'abcccc');
  });

  test('一巡のみ draws each tip once and then nothing', () {
    expect(taken(abc, BrushTipOrder.oneLap, 6), 'abc---');
  });

  test('ランダムに一巡 draws every tip once, shuffled, and then nothing', () {
    final lap = taken(abc, BrushTipOrder.shuffledLap, 6);
    expect(lap.substring(0, 3).split('').toSet(), {'a', 'b', 'c'});
    expect(lap.substring(3), '---');
    // The stroke's dice decide the shuffle: one throw, one order.
    expect(
      taken(abc, BrushTipOrder.shuffledLap, 3, seed: 11),
      taken(abc, BrushTipOrder.shuffledLap, 3, seed: 11),
    );
  });

  test('ランダム throws any tip, each dab, by the stroke\'s dice', () {
    final thrown = taken(abc, BrushTipOrder.random, 300);
    expect(thrown.split('').toSet(), {'a', 'b', 'c'});
    expect(thrown.contains('-'), isFalse, reason: 'it never runs out');
    expect(taken(abc, BrushTipOrder.random, 300), thrown);
    expect(
      taken(abc, BrushTipOrder.random, 300, seed: 8),
      isNot(thrown),
      reason: 'another stroke, another throw',
    );
  });

  test('a lap with one tip draws it once — the only order one tip feels', () {
    expect(taken([tip('a')], BrushTipOrder.oneLap, 3), 'a--');
    expect(taken([tip('a')], BrushTipOrder.shuffledLap, 3), 'a--');
  });

  test('no turns where every dab would take the first tip anyway', () {
    final random = math.Random(1);
    expect(
      BrushTipTurns.of(const [], BrushTipOrder.oneLap, random: random),
      isNull,
    );
    for (final order in [
      BrushTipOrder.repeat,
      BrushTipOrder.pingPong,
      BrushTipOrder.holdLast,
      BrushTipOrder.random,
    ]) {
      expect(
        BrushTipTurns.of([tip('a')], order, random: random),
        isNull,
        reason: '$order',
      );
    }
  });
}
