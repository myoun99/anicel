import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';

void main() {
  LayerEffect blur({double x = 0, double y = 0}) => LayerEffect(
    id: const EffectId('e-blur'),
    kind: EffectKind.blur,
    parameters: {
      'blurX': EffectParameter(value: x),
      'blurY': EffectParameter(value: y),
    },
  );

  group('the parameter shape', () {
    test('an unkeyed parameter answers its static value at every frame', () {
      final parameter = EffectParameter(value: 12);
      expect(parameter.isAnimated, isFalse);
      expect(parameter.resolveAt(0), 12);
      expect(parameter.resolveAt(999), 12);
    });

    test('keys WIN over the static value and interpolate between them', () {
      final parameter = EffectParameter(
        value: 99,
        track: PropertyTrack<double>(
          keys: {
            0: const PropertyKey<double>(0),
            10: const PropertyKey<double>(20),
          },
        ),
      );
      expect(parameter.isAnimated, isTrue);
      expect(parameter.resolveAt(0), 0);
      expect(parameter.resolveAt(5), 10);
      expect(parameter.resolveAt(10), 20);
      expect(parameter.resolveAt(50), 20, reason: 'past the last key it holds');
    });

    test('a HOLD key freezes until the next one', () {
      final parameter = EffectParameter(
        track: PropertyTrack<double>(
          keys: {
            0: const PropertyKey<double>(
              4,
              interpolation: PropertyKeyInterpolation.hold,
            ),
            10: const PropertyKey<double>(20),
          },
        ),
      );
      expect(parameter.resolveAt(9), 4);
      expect(parameter.resolveAt(10), 20);
    });
  });

  group('LayerEffect.defaults', () {
    test(
      'every parameter starts at its spec default, so adding is a no-op',
      () {
        for (final kind in EffectKind.values) {
          final effect = LayerEffect.defaults(
            id: const EffectId('e1'),
            kind: kind,
          );
          for (final spec in effectParametersOf(kind)) {
            expect(effect.parameterOf(spec.id).value, spec.defaultValue);
          }
          expect(
            resolveLayerEffectsAt(effects: [effect], frameIndex: 0),
            isEmpty,
            reason: 'a fresh $kind must change no pixel until a value moves',
          );
        }
      },
    );

    test('the constructor NORMALIZES to the kind\'s full spec set', () {
      final partial = LayerEffect(
        id: const EffectId('e1'),
        kind: EffectKind.hueSaturation,
        parameters: {
          'hue': EffectParameter(value: 30),
          // Not a hue/saturation parameter at all: dropped.
          'blurX': EffectParameter(value: 9),
        },
      );
      expect(partial.parameters.keys, ['hue', 'saturation', 'lightness']);
      expect(partial.parameterOf('saturation').value, 0);
      // …which is what makes equality mean "the same pixels".
      expect(
        partial,
        LayerEffect(
          id: const EffectId('e1'),
          kind: EffectKind.hueSaturation,
          parameters: {
            'hue': EffectParameter(value: 30),
            'saturation': EffectParameter(value: 0),
            'lightness': EffectParameter(value: 0),
          },
        ),
      );
    });
  });

  group('resolveLayerEffectsAt', () {
    test('samples in list order and drops the no-ops', () {
      final resolved = resolveLayerEffectsAt(
        effects: [
          LayerEffect.defaults(
            id: const EffectId('a'),
            kind: EffectKind.brightnessContrast,
          ),
          blur(x: 6, y: 2),
        ],
        frameIndex: 0,
      );
      expect(resolved, hasLength(1));
      expect(resolved.single.kind, EffectKind.blur);
      expect(resolved.single.parameter('blurX'), 6);
      expect(resolved.single.parameter('blurY'), 2);
    });

    test('a DISABLED effect resolves to nothing but keeps its keys', () {
      final disabled = blur(x: 6).copyWith(enabled: false);
      expect(
        resolveLayerEffectsAt(effects: [disabled], frameIndex: 0),
        isEmpty,
      );
      expect(disabled.parameterOf('blurX').value, 6);
    });

    test('values clamp to the spec range', () {
      final wild = LayerEffect(
        id: const EffectId('e'),
        kind: EffectKind.brightnessContrast,
        parameters: {'brightness': EffectParameter(value: 5000)},
      );
      final resolved = resolveLayerEffectsAt(effects: [wild], frameIndex: 0);
      expect(resolved.single.parameter('brightness'), 100);
    });

    test('an animated parameter samples per frame — held frames differ', () {
      final animated = LayerEffect(
        id: const EffectId('e'),
        kind: EffectKind.blur,
        parameters: {
          'blurX': EffectParameter(
            track: PropertyTrack<double>(
              keys: {
                0: const PropertyKey<double>(0),
                10: const PropertyKey<double>(10),
              },
            ),
          ),
        },
      );
      expect(
        resolveLayerEffectsAt(effects: [animated], frameIndex: 0),
        isEmpty,
        reason: 'sampled at its default at frame 0 — nothing to paint',
      );
      expect(
        resolveLayerEffectsAt(
          effects: [animated],
          frameIndex: 5,
        ).single.parameter('blurX'),
        5,
      );
    });

    test('resolvedEffectsSpreadPixels only answers for a blur', () {
      final colour = LayerEffect(
        id: const EffectId('c'),
        kind: EffectKind.brightnessContrast,
        parameters: {'brightness': EffectParameter(value: 10)},
      );
      expect(
        resolvedEffectsSpreadPixels(
          resolveLayerEffectsAt(effects: [colour], frameIndex: 0),
        ),
        isFalse,
      );
      expect(
        resolvedEffectsSpreadPixels(
          resolveLayerEffectsAt(effects: [blur(x: 3)], frameIndex: 0),
        ),
        isTrue,
      );
    });
  });

  group('JSON', () {
    test('a chain round-trips with keys, defaults and the enable switch', () {
      final effects = [
        LayerEffect(
          id: const EffectId('e-1'),
          kind: EffectKind.hueSaturation,
          enabled: false,
          parameters: {
            'hue': EffectParameter(
              value: 30,
              track: PropertyTrack<double>(
                keys: {
                  2: const PropertyKey<double>(
                    -10,
                    interpolation: PropertyKeyInterpolation.hold,
                  ),
                },
              ),
            ),
          },
        ),
        blur(x: 4),
      ];
      final layer = Layer(
        id: const LayerId('l1'),
        name: 'A',
        frames: const [],
        kind: LayerKind.animation,
        effects: effects,
      );
      final restored = Layer.fromJson(layer.toJson());
      expect(restored.effects, effects);
      expect(restored, layer);
      expect(restored.effects.first.enabled, isFalse);
      expect(
        restored.effects.first.parameterOf('hue').track.keyAt(2)!.interpolation,
        PropertyKeyInterpolation.hold,
      );
    });

    test('an empty chain writes no key at all (old files read back equal)', () {
      final layer = Layer(
        id: const LayerId('l1'),
        name: 'A',
        frames: const [],
        kind: LayerKind.animation,
      );
      expect(layer.toJson().containsKey('effects'), isFalse);
      expect(Layer.fromJson(layer.toJson()).effects, isEmpty);
    });

    test('parameters sitting at their default are omitted from JSON', () {
      final json = LayerEffect.defaults(
        id: const EffectId('e'),
        kind: EffectKind.blur,
      ).toJson();
      expect(json['parameters'], isEmpty);
      // …and still load as full defaults.
      expect(LayerEffect.fromJson(json).parameterOf('blurY').value, 0);
    });

    test('an unknown effect kind is a FormatException, not a silent drop', () {
      expect(
        () => LayerEffect.fromJson({
          'id': const EffectId('e').toJson(),
          'kind': 'timeWarp',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('labels', () {
    test('ja localizes, the other languages keep the shared vocabulary', () {
      expect(
        EffectKind.blur.labelFor(AppLanguage.ja),
        isNot(EffectKind.blur.label),
      );
      for (final language in AppLanguage.values) {
        if (language == AppLanguage.ja) {
          continue;
        }
        for (final kind in EffectKind.values) {
          expect(kind.labelFor(language), kind.label);
        }
      }
    });
  });

  group('layer equality', () {
    test('two layers differing only in an effect value are NOT equal', () {
      Layer withBlur(double radius) => Layer(
        id: const LayerId('l1'),
        name: 'A',
        frames: const [],
        effects: [blur(x: radius)],
      );
      expect(withBlur(4) == withBlur(4), isTrue);
      expect(withBlur(4) == withBlur(5), isFalse);
      expect(withBlur(4).hashCode == withBlur(5).hashCode, isFalse);
    });
  });

  group('the kind predicate', () {
    test('a row authors an effect chain unless it has no picture to filter', () {
      // The camera is the frame rather than a thing inside it, and the
      // TRANSITION row is read-only notation on the track's axis — a grade
      // on a boundary annotation would have nothing to grade.
      const chainless = {LayerKind.camera, LayerKind.transition};
      for (final kind in LayerKind.values) {
        expect(
          layerKindHasLayerEffects(kind),
          !chainless.contains(kind),
          reason: kind.name,
        );
      }
    });
  });
}
