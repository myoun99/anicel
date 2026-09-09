import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_rotation_mode.dart';

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
  curves: brushPressureCurves(
    size: BrushPressureCurve.linearFrom(0.2),
    opacity: BrushPressureCurve.linearFrom(0.3),
    flow: BrushPressureCurve.linearFrom(0.4),
    hardness: BrushPressureCurve.identity(),
  ),
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
  textureMaskSource: _maskFor('texture'),
  textureInvert: true,
  textureBrightness: -0.4,
  textureContrast: 0.6,
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
      expect(base.copyWith(textureMaskSource: _maskFor('other')), isNot(base));
      expect(base.copyWith(textureInvert: false), isNot(base));
      expect(base.copyWith(textureBrightness: 0.0), isNot(base));
      expect(base.copyWith(textureContrast: 0.0), isNot(base));
      expect(base.copyWith(textureScale: 1.0), isNot(base));
      expect(base.copyWith(textureDensity: 1.0), isNot(base));
      // The pressure curves too.
      expect(
        base.withPressureCurve(
          BrushPressureTarget.size,
          BrushPressureCurve.identity(),
        ),
        isNot(base),
      );
      expect(
        base.withPressureCurve(
          BrushPressureTarget.opacity,
          BrushPressureCurve.identity(),
        ),
        isNot(base),
      );
      expect(
        base.withPressureCurve(
          BrushPressureTarget.flow,
          BrushPressureCurve.identity(),
        ),
        isNot(base),
      );
      expect(
        base.withPressureCurve(
          BrushPressureTarget.hardness,
          BrushPressureCurve.linearFrom(0.1),
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

      final withSize = shape.withPressureCurve(
        BrushPressureTarget.size,
        BrushPressureCurve.identity(),
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

    group('the paper texture as picked vs as painted', () {
      test('🚨the levels are applied to the PAINTED mask and nothing else', () {
        final source = BrushTipMask(
          id: 'paper',
          size: 2,
          alpha: Uint8List.fromList(const [0, 80, 160, 255]),
        );
        final shape = BrushShape(
          textureMaskSource: source,
          textureInvert: true,
        );

        expect(
          shape.textureMaskSource,
          same(source),
          reason: 'the picked texture is kept, untouched, to re-bake from',
        );
        expect(shape.textureMask!.alpha, [255, 175, 95, 0]);
      });

      test('neutral levels hand back the source ITSELF, with no bake', () {
        final source = BrushTipMask(
          id: 'paper',
          size: 2,
          alpha: Uint8List.fromList(const [0, 80, 160, 255]),
        );

        expect(BrushShape(textureMaskSource: source).textureMask, same(source));
      });

      test('🚨the same shape bakes ONCE, and reading it twice is free', () {
        // The derived mask is read on the path a dab is built on, which runs
        // thousands of times a stroke while a 256×256 texture is 65k pixels.
        // A getter that re-baked per read would be a per-dab cost.
        final shape = BrushShape(
          textureMaskSource: BrushTipMask(
            id: 'paper',
            size: 2,
            alpha: Uint8List.fromList(const [0, 80, 160, 255]),
          ),
          textureContrast: 0.5,
        );

        expect(shape.textureMask, same(shape.textureMask));
      });

      test('a different level is a different bake', () {
        final source = BrushTipMask(
          id: 'paper',
          size: 2,
          alpha: Uint8List.fromList(const [0, 80, 160, 255]),
        );
        final dim = BrushShape(
          textureMaskSource: source,
          textureBrightness: 0.5,
        );
        final dimmer = BrushShape(
          textureMaskSource: source,
          textureBrightness: 0.8,
        );

        expect(dim.textureMask, isNot(same(dimmer.textureMask)));
        expect(dim.textureMask!.alpha[3], greaterThan(dimmer.textureMask!.alpha[3]));
      });
    });
  });
}
