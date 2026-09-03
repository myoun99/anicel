// A DAB'S JSON CARRIES ITS TEXTURE MASK ONLY WHEN IT HAS ONE, AND TWO DABS
// THAT DIFFER IN OPACITY ARE NOT THE SAME DAB.
//
// Two survivors of the mutation campaign (2026-09-03): the texture guard's
// `!=` became `==` (a dab without a mask crashed encoding, one with a mask
// dropped it) and `==`'s opacity comparison became `!=`. Nothing noticed;
// these pins do.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';

BrushDab _dab({double opacity = 1, BrushTipMask? textureMask}) => BrushDab(
  center: CanvasPoint(x: 4, y: 4),
  color: 0xFF102030,
  size: 8,
  opacity: opacity,
  flow: 1,
  hardness: 0.5,
  tipShape: BrushTipShape.round,
  pressure: 1,
  sequence: 0,
  textureMask: textureMask,
);

void main() {
  test('toJson leaves the texture mask out when the dab has none', () {
    expect(_dab().toJson().containsKey('textureMask'), isFalse);
  });

  test('toJson carries the texture mask when the dab has one', () {
    final mask = BrushTipMask.square(
      id: 'm',
      width: 2,
      height: 2,
      pixels: Uint8List.fromList([255, 255, 255, 255]),
    );
    expect(_dab(textureMask: mask).toJson()['textureMask'], isNotNull);
  });

  test('opacity is part of a dab\'s identity', () {
    expect(_dab(opacity: 1), equals(_dab(opacity: 1)));
    expect(_dab(opacity: 1), isNot(equals(_dab(opacity: 0.5))));
  });
}
