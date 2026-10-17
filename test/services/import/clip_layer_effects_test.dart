import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/import/clip_layer_effects.dart';

import 'clip_test_builder.dart';

/// A layer's `LayerEffectInfo` read for an effect that is on — against
/// blobs built in the shape one sample's held ([layerEffectInfoBytes]).
void main() {
  test('the sample\'s blob — every effect off, the tone reflecting the '
      'layer\'s opacity — turns none on', () {
    expect(clipEffectsOn(layerEffectInfoBytes()), isFalse);
  });

  test('each effect\'s switch alone turns it on: the border\'s two, the '
      'tone, extracted lines and the texture', () {
    for (final name in [
      'EffectEdge',
      'EffectTone',
      'EffectWaterEdge',
      'EffectLine',
      'EffectTextureMap',
    ]) {
      expect(
        clipEffectsOn(layerEffectInfoBytes(on: {name})),
        isTrue,
        reason: name,
      );
    }
  });

  test('the tone\'s own settings are no effects: posterized, its area '
      'coloured and reflecting the opacity, nothing is on while the tone '
      'is off', () {
    expect(
      clipEffectsOn(layerEffectInfoBytes(reflectOpacity: 1, posterize: 1)),
      isFalse,
    );
  });

  test('a blob that holds no record, or ends inside one, turns none on', () {
    expect(clipEffectsOn(Uint8List(8)), isFalse);
    // The border's switch on, and the blob cut two bytes into it.
    const into = 8 + 4 + 2 * 'EffectEdge'.length + 2;
    expect(
      clipEffectsOn(
        Uint8List.sublistView(
          layerEffectInfoBytes(on: {'EffectEdge'}),
          0,
          into,
        ),
      ),
      isFalse,
    );
  });
}
