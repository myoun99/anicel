import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_order.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_stroke_dynamics.dart';

/// F-176-Q3: a brush's tips are taken in turn by the stroke's dabs — 「dab
/// 하나마다 다음 장으로 가고, 획마다 처음부터」 — where the stroke's other
/// placement dynamics are thrown (`BrushStrokeDynamics`), so both of the
/// canvas's emission sites, the press and the moves, take the same turns.
void main() {
  BrushTipMask tip(String id) =>
      BrushTipMask(id: id, size: 2, alpha: Uint8List.fromList([9, 8, 7, 6]));

  final abc = [tip('a'), tip('b'), tip('c')];

  BrushDab dab(int index) => BrushDab(
    center: CanvasPoint(x: 10.0 + index, y: 10),
    color: 0xFF000000,
    size: 10,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: index,
    tipMask: abc.first,
  );

  List<BrushDab> dabs(int count) => [
    for (var index = 0; index < count; index += 1) dab(index),
  ];

  BrushStrokeDynamics strokeOf(
    BrushTipOrder order, {
    List<BrushTipMask>? tips,
    double scatter = 0,
    int scatterCount = 1,
    int seed = 3,
  }) => BrushStrokeDynamics(
    settings: BrushEditCanvasInputSettings(
      tips: tips ?? abc,
      tipOrder: order,
      scatterRadiusRatio: scatter,
      scatterCount: scatterCount,
    ),
    random: math.Random(seed),
    tipRandom: math.Random(seed + 100),
  );

  String tipsOf(List<BrushDab> laid) =>
      [for (final dab in laid) dab.tipMask?.id ?? '?'].join();

  test('every dab takes the next tip — each of a spray\'s too', () {
    final stroke = strokeOf(
      BrushTipOrder.repeat,
      scatter: 0.5,
      scatterCount: 2,
    );

    final laid = stroke.apply(dabs(3), firstSequence: 0);

    expect(tipsOf(laid), 'abcabc');
    expect([for (final dab in laid) dab.sequence], [0, 1, 2, 3, 4, 5]);
  });

  test('the turns run on across a stroke\'s steps, and start over with the '
      'next stroke', () {
    final stroke = strokeOf(BrushTipOrder.repeat);
    expect(tipsOf(stroke.apply(dabs(2), firstSequence: 0)), 'ab');
    expect(tipsOf(stroke.apply(dabs(2), firstSequence: 2)), 'ca');

    final next = strokeOf(BrushTipOrder.repeat);
    expect(tipsOf(next.apply(dabs(2), firstSequence: 0)), 'ab');
  });

  test('a lap that ran out lays nothing more, and the numbers close up', () {
    final stroke = strokeOf(BrushTipOrder.oneLap);

    final laid = stroke.apply(dabs(5), firstSequence: 4);

    expect(tipsOf(laid), 'abc');
    expect([for (final dab in laid) dab.sequence], [4, 5, 6]);
    expect(stroke.apply(dabs(3), firstSequence: 7), isEmpty);
  });

  test('🚨the tips throw dice of their own: a spray lands where it did '
      'whatever order its tips take', () {
    List<CanvasPoint> sprayOf(BrushTipOrder order) => [
      for (final dab in strokeOf(
        order,
        scatter: 0.8,
        scatterCount: 3,
      ).apply(dabs(6), firstSequence: 0))
        dab.center,
    ];

    expect(sprayOf(BrushTipOrder.random), sprayOf(BrushTipOrder.repeat));
  });

  test('a brush whose tips take no turns passes its dabs through', () {
    final stroke = strokeOf(BrushTipOrder.random, tips: [abc.first]);
    final unchanged = dabs(3);

    expect(
      identical(stroke.apply(unchanged, firstSequence: 0), unchanged),
      isTrue,
    );
  });
}
