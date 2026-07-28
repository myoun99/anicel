import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_rotation_mode.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';

BrushTipMask _maskFor(String id) => BrushTipMask(
  id: id,
  size: 2,
  alpha: Uint8List.fromList(const [10, 20, 30, 40]),
);

/// Every one of the 26 parameters at a NON-default value, so that any field a
/// copy/compare drops flips back to its default and the assertion below fails
/// loudly (the same trap-proof shape the converter round-trip test uses).
BrushShape _everyFieldNonDefault() => BrushShape(
  color: 0xFF1E88E5,
  size: 14,
  opacity: 0.7,
  flow: 0.5,
  hardness: 0.6,
  spacing: 0.3,
  tipShape: BrushTipShape.square,
  sizePressureCurve: BrushPressureCurve.linearFrom(0.2),
  opacityPressureCurve: BrushPressureCurve.linearFrom(0.3),
  flowPressureCurve: BrushPressureCurve.linearFrom(0.4),
  hardnessPressureCurve: BrushPressureCurve.identity(),
  roundness: 0.4,
  angleDegrees: 60,
  tipMask: _maskFor('tip'),
  rotationMode: BrushTipRotationMode.direction,
  sizeJitter: 0.2,
  opacityJitter: 0.3,
  angleJitter: 0.4,
  scatterRadiusRatio: 0.5,
  scatterCount: 3,
  scatterBothAxes: false,
  dualMask: _maskFor('dual'),
  dualMaskScale: 0.7,
  textureMask: _maskFor('texture'),
  textureScale: 1.2,
  textureDensity: 0.9,
);

void main() {
  group('BrushShape', () {
    test('copyWith with no arguments carries every field', () {
      // A dropped field in copyWith turns its non-default value back into the
      // default, so this equality (and hashCode) breaks if any field is
      // missing from copyWith.
      final shape = _everyFieldNonDefault();
      expect(shape.copyWith(), shape);
      expect(shape.copyWith().hashCode, shape.hashCode);
    });

    test('every field participates in equality', () {
      final base = _everyFieldNonDefault();
      // Each single-field change must make the shape unequal — catches a field
      // missing from operator ==.
      expect(base.copyWith(color: 0xFF000000), isNot(base));
      expect(base.copyWith(size: 1), isNot(base));
      expect(base.copyWith(opacity: 1.0), isNot(base));
      expect(base.copyWith(flow: 1.0), isNot(base));
      expect(base.copyWith(hardness: 1.0), isNot(base));
      expect(base.copyWith(spacing: 0.1), isNot(base));
      expect(base.copyWith(tipShape: BrushTipShape.round), isNot(base));
      expect(base.copyWith(roundness: 1.0), isNot(base));
      expect(base.copyWith(angleDegrees: 0), isNot(base));
      expect(base.copyWith(tipMask: _maskFor('other')), isNot(base));
      expect(
        base.copyWith(rotationMode: BrushTipRotationMode.fixed),
        isNot(base),
      );
      expect(base.copyWith(sizeJitter: 0), isNot(base));
      expect(base.copyWith(opacityJitter: 0), isNot(base));
      expect(base.copyWith(angleJitter: 0), isNot(base));
      expect(base.copyWith(scatterRadiusRatio: 0), isNot(base));
      expect(base.copyWith(scatterCount: 1), isNot(base));
      expect(base.copyWith(scatterBothAxes: true), isNot(base));
      expect(base.copyWith(dualMask: _maskFor('other')), isNot(base));
      expect(base.copyWith(dualMaskScale: 1.0), isNot(base));
      expect(base.copyWith(textureMask: _maskFor('other')), isNot(base));
      expect(base.copyWith(textureScale: 1.0), isNot(base));
      expect(base.copyWith(textureDensity: 1.0), isNot(base));
      // The pressure curves too.
      expect(
        base.copyWith(sizePressureCurve: BrushPressureCurve.identity()),
        isNot(base),
      );
      expect(
        base.copyWith(opacityPressureCurve: BrushPressureCurve.identity()),
        isNot(base),
      );
      expect(
        base.copyWith(flowPressureCurve: BrushPressureCurve.identity()),
        isNot(base),
      );
      expect(
        base.copyWith(
          hardnessPressureCurve: BrushPressureCurve.linearFrom(0.1),
        ),
        isNot(base),
      );
    });

    test('equal shapes share a hashCode', () {
      expect(_everyFieldNonDefault(), _everyFieldNonDefault());
      expect(
        _everyFieldNonDefault().hashCode,
        _everyFieldNonDefault().hashCode,
      );
    });

    test('pressureCurveFor reads each channel', () {
      const shape = BrushShape();
      expect(shape.pressureCurveFor(BrushPressureTarget.size), isNull);

      final withSize = shape.copyWith(
        sizePressureCurve: BrushPressureCurve.identity(),
      );
      expect(
        withSize.pressureCurveFor(BrushPressureTarget.size),
        BrushPressureCurve.identity(),
      );
    });

    test('withPressureCurve sets and CLEARS one channel, leaving others', () {
      const shape = BrushShape();

      // copyWith cannot clear (null preserves); withPressureCurve(null) can.
      final both = shape
          .withPressureCurve(
            BrushPressureTarget.size,
            BrushPressureCurve.identity(),
          )
          .withPressureCurve(
            BrushPressureTarget.flow,
            BrushPressureCurve.linearFrom(0.5),
          );
      expect(both.sizePressureCurve, BrushPressureCurve.identity());
      expect(both.flowPressureCurve, BrushPressureCurve.linearFrom(0.5));

      final cleared = both.withPressureCurve(BrushPressureTarget.flow, null);
      expect(cleared.flowPressureCurve, isNull);
      // The other channel survives the clear.
      expect(cleared.sizePressureCurve, BrushPressureCurve.identity());
    });

    test('withPressureCurve leaves the 26 non-curve fields untouched', () {
      final base = _everyFieldNonDefault();
      final swapped = base.withPressureCurve(
        BrushPressureTarget.hardness,
        BrushPressureCurve.linearFrom(0.15),
      );
      expect(
        swapped.hardnessPressureCurve,
        BrushPressureCurve.linearFrom(0.15),
      );
      // Everything except the one channel is carried, so restoring it returns
      // the original shape.
      expect(
        swapped.withPressureCurve(
          BrushPressureTarget.hardness,
          base.hardnessPressureCurve,
        ),
        base,
      );
    });
  });
}
