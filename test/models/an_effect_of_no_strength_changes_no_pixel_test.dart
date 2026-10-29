import 'package:flutter/painting.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';

/// 🗣️fx-made-light-by-one-law (유저 2026-10-29 「fx들 가볍게 하는 로직은
/// 서로 최대한 법 통일하면서 알아서해줘. 근본구조적으로」): an effect at its
/// kind's strength of nothing changes no pixel whatever its other values say
/// — ONE law ([EffectKind.strength]) where each blur used to ask its own
/// `<= 0` — so the resolver drops it and nothing downstream pays for it.
void main() {
  /// [kind] at its defaults but [moved], an index each.
  ResolvedLayerEffect sample(EffectKind kind, Map<String, double> moved) =>
      ResolvedLayerEffect(
        kind: kind,
        values: [
          for (final spec in kind.parameters)
            moved[spec.id] ?? spec.defaultValue,
        ],
      );

  // A strength of nothing with something else moved: the case the defaults
  // alone never caught.
  final noStrength = <String, ResolvedLayerEffect>{
    'a Gaussian of no blurriness, repeating the edge': sample(
      EffectKind.blur,
      {'blurriness': 0, 'repeatEdgePixels': 1},
    ),
    'a directional blur of no length, turned': sample(
      EffectKind.directionalBlur,
      {'blurLength': 0, 'direction': 45},
    ),
    'a radial blur of no amount, zooming': sample(EffectKind.radialBlur, {
      'amount': 0,
      'type': 1,
    }),
    'a camera lens blur of no radius, its iris turned': sample(
      EffectKind.cameraLensBlur,
      {'blurRadius': 0, 'irisRotation': 30},
    ),
    'a colour key of no amount, wide': sample(EffectKind.colorKey, {
      'amount': 0,
      'tolerance': 90,
    }),
  };

  for (final MapEntry(key: name, value: effect) in noStrength.entries) {
    test('$name changes no pixel', () {
      expect(
        effect.kind.parameters.any(
          (spec) => effect.parameter(spec.id) != spec.defaultValue,
        ),
        isTrue,
        reason: '⛔전제: a value other than its strength is moved',
      );
      expect(effect.isNoOp, isTrue);
    });
  }

  // A chain handed one past the resolver — a test's, a reader's of its own
  // — asks the same question once, where its paint is resolved.
  for (final MapEntry(key: name, value: effect) in noStrength.entries) {
    if (effect.kind == EffectKind.colorKey) {
      // Split off before a paint is resolved (splitSourceEffects).
      continue;
    }
    test('$name takes no step and grows no buffer', () {
      final plan = resolveCompositeEffectPlan([
        effect,
      ], paper: const Rect.fromLTWH(0, 0, 64, 48));
      expect(plan.isSingleDraw, isTrue);
      expect(plan.outsetPixels, 0);
      expect(plan.finalPaint.isEmpty, isTrue);
    });
  }

  test('a strength above nothing changes pixels', () {
    for (final kind in EffectKind.values) {
      final strength = kind.strength;
      if (strength == null) {
        continue;
      }
      expect(
        sample(kind, {strength: 1}).isNoOp,
        isFalse,
        reason: '$kind at a $strength of 1',
      );
    }
  });

  test('a kind with no strength is a no-op only at its defaults', () {
    expect(EffectKind.brightnessContrast.strength, isNull);
    expect(sample(EffectKind.brightnessContrast, const {}).isNoOp, isTrue);
    expect(
      sample(EffectKind.brightnessContrast, const {'brightness': 10}).isNoOp,
      isFalse,
    );
  });
}
