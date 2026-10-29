import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/separable_blend_mode.dart';
import 'package:anicel/src/services/brush_dab_interpolator.dart';
import 'package:anicel/src/services/brush_second_stroke.dart';

/// 🚨THE SECOND TIP IS A STROKE OF ITS OWN (board
/// an-imported-pencil-drops-its-second-brush Q3 b, 「두 번째 획으로 다시
/// 만든다」): [BrushSecondStroke] walks the first tip's path at the second
/// tip's own size, and lays dabs of the second tip that bite at one — how
/// hard they bite is the view's density, once over the stroke.
void main() {
  final grain = BrushTipMask(
    id: 'second-stroke-grain',
    size: 8,
    alpha: Uint8List.fromList([for (var i = 0; i < 64; i += 1) i * 4]),
  );
  final shape = BrushShape(
    size: 40,
    spacing: 0.2,
    dualMask: grain,
    dualMaskScale: 0.5,
    dualDensity: 0.7,
    dualCompositeMode: SeparableBlendMode.overlay,
  );

  BrushDab pathDab(double x, {double pressure = 1, int sequence = 0}) =>
      BrushDab(
        center: CanvasPoint(x: x, y: 20),
        color: 0xFF2A5599,
        size: 40,
        opacity: 0.6,
        flow: 0.4,
        hardness: 0.3,
        pressure: pressure,
        sequence: sequence,
        dual: shape.dualView,
      );

  test('a brush without a second tip has no second stroke', () {
    expect(BrushSecondStroke.of(const BrushShape()), isNull);
  });

  test('the second tip lays whole, at its own size, under the view', () {
    final laid = BrushSecondStroke.of(shape)!.follow([
      pathDab(10, pressure: 0.4),
    ], firstSequence: 7);
    expect(laid, hasLength(1));
    final dab = laid.single;
    expect(dab.center, CanvasPoint(x: 10, y: 20));
    expect(dab.size, 20, reason: 'the first tip\'s size times the scale');
    expect(dab.color, 0xFF000000);
    expect(dab.opacity, 1);
    expect(dab.flow, 1);
    expect(dab.pressure, 0.4);
    expect(dab.hardness, 0.3);
    expect(dab.sequence, 7);
    expect(dab.tipMask, grain);
    expect(dab.second, isTrue);
    expect(
      dab.dual,
      const BrushDualView(
        compositeMode: SeparableBlendMode.overlay,
        density: 0.7,
      ),
    );
  });

  test('the second stroke spaces its dabs by its own size', () {
    final laid = BrushSecondStroke.of(shape)!.follow([
      pathDab(0),
      pathDab(30, sequence: 1),
    ], firstSequence: 0);
    // 20 px tip at 20% — a dab every 4 px over 30 px: eight steps.
    final step = const BrushDabInterpolator().spacingForBrushSize(20, 0.2);
    expect(step, 4);
    expect(laid, hasLength(1 + 8));
    expect([for (final dab in laid) dab.sequence], [
      for (var i = 0; i < 9; i += 1) i,
    ]);
    expect(laid.last.center, CanvasPoint(x: 30, y: 20));
  });

  test('the walk carries over from one segment to the next', () {
    final path = [
      for (var i = 0; i < 6; i += 1) pathDab(i * 2.5, sequence: i),
    ];
    final whole = BrushSecondStroke.of(shape)!.follow(path, firstSequence: 0);
    final pieces = BrushSecondStroke.of(shape)!;
    final inTurn = [
      for (final dab in path)
        ...pieces.follow([dab], firstSequence: 0),
    ];
    expect(
      [for (final dab in inTurn) dab.center],
      [for (final dab in whole) dab.center],
      reason: 'a short step waits for the next instead of starting over',
    );
  });
}
