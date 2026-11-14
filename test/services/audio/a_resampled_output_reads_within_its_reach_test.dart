import 'dart:math' as math;
import 'dart:typed_data';

import 'package:anicel/src/native/qa_audio_resampler.dart';
import 'package:flutter_test/flutter_test.dart';

/// [resampleReach] is how far a window cut from inside a sound reads past
/// its edges to convert as the whole sound converts (sound_span.dart,
/// F-588): no output may read farther than it, or the window's edge comes
/// out against silence — and it should not overstate that by a frame, or
/// the window reads sound nothing needs.
void main() {
  const spacing = 401;
  const impulses = 150;
  for (final (input, output) in const [
    (1001, 1000),
    (1000, 1001),
    (25, 24),
    (24, 25),
    (44100, 48000),
  ]) {
    test('🎯$input → $output: the farthest input an output reads lies '
        'within resampleReach of its instant, and less than a frame '
        'inside it', () {
      final reach = resampleReach(inputRate: input, outputRate: output);
      expect(reach, lessThan(spacing ~/ 2), reason: 'the impulses overlap');
      final common = input.gcd(output);
      final step = (input ~/ common) / (output ~/ common);
      // Impulses far enough apart that each output hears one at most, a
      // prime apart, so between them the outputs land on every phase.
      final sound = Float32List(spacing * impulses);
      for (var at = 0; at < impulses; at += 1) {
        sound[at * spacing + spacing ~/ 2] = 1;
      }
      final heard = resampleAudio(
        samples: sound,
        channels: 1,
        inputRate: input,
        outputRate: output,
      );
      var farthest = 0.0;
      for (var frame = 0; frame < heard.length; frame += 1) {
        if (heard[frame] == 0) {
          continue;
        }
        final instant = frame * step;
        final nearest = (instant / spacing).floor() * spacing + spacing ~/ 2;
        farthest = math.max(farthest, (instant - nearest).abs());
      }
      expect(farthest, lessThanOrEqualTo(reach));
      expect(farthest, greaterThan(reach - 1));
    });
  }
}
