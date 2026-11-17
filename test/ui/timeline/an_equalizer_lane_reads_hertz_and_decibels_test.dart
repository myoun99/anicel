import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';

/// An equalizer's lanes write their numbers in their units — ローカット (Hz)
/// · 低域 (dB), the lanes drawn in design 1 (board
/// audio-fx-grows-like-the-pros, Q2 유저 2026-11-17) — and read them back
/// with the unit typed or not, as every value column does.
void main() {
  final lowCut = EffectKind.equalizer.parameterSpec('lowCut')!;
  final lowGain = EffectKind.equalizer.parameterSpec('lowGain')!;

  test('a corner writes in hertz, a gain in decibels', () {
    expect(formatEffectLaneValue(lowCut, 80), '80.00 Hz');
    expect(formatEffectLaneValue(lowGain, -3), '-3.00 dB');
  });

  test('what a lane writes reads back, unit or none, held in its range', () {
    expect(parseEffectLaneValue(lowCut, '80.00 Hz'), 80);
    expect(parseEffectLaneValue(lowCut, '120'), 120);
    expect(parseEffectLaneValue(lowCut, '5000 Hz'), lowCut.maximum);
    expect(parseEffectLaneValue(lowGain, '-3.00 dB'), -3);
    expect(parseEffectLaneValue(lowGain, '6dB'), 6);
  });
}
