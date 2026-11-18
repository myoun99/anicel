import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_effect.dart';

/// A sound's filter ([EffectKind.filtersSound]) is the row's sound's, baked
/// a span at a time — so no picture's chain ever runs it, at any value
/// (board audio-fx-grows-like-the-pros, Q3: 「s행은 그냥 영상fx안붙게?
/// 오디오fx만 기본으로」).
void main() {
  test('🎯an equalizer away from its defaults is still no picture step', () {
    final equalizer = LayerEffect(
      id: const EffectId('eq'),
      kind: EffectKind.equalizer,
      parameters: {'lowGain': EffectParameter(value: 12)},
    );
    final blur = LayerEffect(
      id: const EffectId('blur'),
      kind: EffectKind.blur,
      parameters: {'blurriness': EffectParameter(value: 4)},
    );
    expect(
      resolveLayerEffectsAt(
        effects: [equalizer, blur],
        frameIndex: 0,
        blocks: null,
        worn: null,
      ).map((sample) => sample.kind),
      [EffectKind.blur],
    );
  });

  test('a kind is taken by the rows that play what it filters', () {
    for (final kind in EffectKind.values) {
      expect(
        kind.isTakenByARow(playsSound: true),
        kind.filtersSound,
        reason: '$kind on a sound row',
      );
      expect(
        kind.isTakenByARow(playsSound: false),
        !kind.filtersSound,
        reason: '$kind on a picture row',
      );
    }
    expect(
      [
        for (final kind in EffectKind.values)
          if (kind.filtersSound) kind,
      ],
      [EffectKind.equalizer, EffectKind.compressor, EffectKind.noiseRemoval],
    );
  });
}
