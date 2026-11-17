import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';

/// A sound filter's lanes write their numbers in their units — an
/// equalizer's ローカット (Hz) · 低域 (dB), the lanes drawn in design 1
/// (board audio-fx-grows-like-the-pros, Q2 유저 2026-11-17), and a
/// compressor's アタック (ms) · レシオ (:1) — and read them back with the
/// unit typed or not, as every value column does.
void main() {
  final lowCut = EffectKind.equalizer.parameterSpec('lowCut')!;
  final lowGain = EffectKind.equalizer.parameterSpec('lowGain')!;
  final attack = EffectKind.compressor.parameterSpec('attack')!;
  final ratio = EffectKind.compressor.parameterSpec('ratio')!;

  test('a corner writes in hertz, a gain in decibels', () {
    expect(formatEffectLaneValue(lowCut, 80), '80.00 Hz');
    expect(formatEffectLaneValue(lowGain, -3), '-3.00 dB');
  });

  test('a time writes in milliseconds, a ratio to one', () {
    expect(formatEffectLaneValue(attack, 10), '10.00 ms');
    expect(formatEffectLaneValue(ratio, 4), '4.00:1');
  });

  test('what a lane writes reads back, unit or none, held in its range', () {
    expect(parseEffectLaneValue(lowCut, '80.00 Hz'), 80);
    expect(parseEffectLaneValue(lowCut, '120'), 120);
    expect(parseEffectLaneValue(lowCut, '5000 Hz'), lowCut.maximum);
    expect(parseEffectLaneValue(lowGain, '-3.00 dB'), -3);
    expect(parseEffectLaneValue(lowGain, '6dB'), 6);
    expect(parseEffectLaneValue(attack, '25.00 ms'), 25);
    expect(parseEffectLaneValue(attack, '40ms'), 40);
    expect(parseEffectLaneValue(attack, '900 ms'), attack.maximum);
    expect(parseEffectLaneValue(ratio, '8.00:1'), 8);
    expect(parseEffectLaneValue(ratio, '3'), 3);
    expect(parseEffectLaneValue(ratio, '0.5:1'), ratio.minimum);
  });
}
