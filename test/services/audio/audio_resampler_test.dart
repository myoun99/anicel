import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/audio/audio_resampler_reference.dart';

/// Resampler quality, MEASURED rather than listened to.
///
/// A converter is either transparent or it is not, and both are numbers:
/// how far down the aliases sit, how flat the passband is, and — the one
/// that matters most here — whether a sound comes out at the instant it
/// went in.
void main() {
  /// Level of one DFT bin in dB, measured over exactly ONE SECOND taken
  /// from the MIDDLE of [samples].
  ///
  /// Both halves of that matter.
  ///
  /// One second means an integer frequency lands dead on bin `frequency`
  /// in every rate, so there is no spectral leakage — measured off a bin
  /// centre, an unwindowed DFT's own sidelobes sit near −80 dB and would
  /// masquerade as the filter's stopband.
  ///
  /// The middle matters because the signal STARTS. A tone that switches on
  /// at sample 0 is a step, and the convolution running off into zeros
  /// spreads that step across every frequency. Measured from the edge, a
  /// filter with 135 dB of real rejection reads as 94 — the number
  /// describes the test's own transient, not the converter.
  double binDb(Float32List samples, int rate, int frequency) {
    expect(
      samples.length,
      greaterThanOrEqualTo(rate * 2),
      reason: 'need at least two seconds so a clean middle second exists',
    );
    final start = (samples.length - rate) ~/ 2;
    var re = 0.0;
    var im = 0.0;
    for (var i = 0; i < rate; i += 1) {
      final angle = -2 * math.pi * frequency * i / rate;
      re += samples[start + i] * math.cos(angle);
      im += samples[start + i] * math.sin(angle);
    }
    final magnitude = math.sqrt(re * re + im * im) / rate;
    return 20 * math.log(magnitude + 1e-30) / math.ln10;
  }

  /// Three seconds of a tone, so [binDb] has a clean second to look at
  /// with a full second of settled filter either side of it.
  Float32List tone(int frequency, int rate, {double gain = 0.5}) {
    final frames = rate * 3;
    final out = Float32List(frames);
    for (var i = 0; i < frames; i += 1) {
      out[i] = gain * math.sin(2 * math.pi * frequency * i / rate);
    }
    return out;
  }

  group('the delay is exactly zero', () {
    test('an impulse comes out where it went in', () {
      // THE test. A symmetric FIR delays by (taps-1)/2 — at these lengths
      // more than a frame at 24fps. If the compensation were off, every
      // resampled clip would sit late, which is the exact defect this
      // program exists to remove.
      const inputRate = 44100;
      const outputRate = 48000;
      const at = 2000;
      final samples = Float32List(8000);
      samples[at] = 1.0;

      final resampled = resampleAudioReference(
        samples: samples,
        channels: 1,
        inputRate: inputRate,
        outputRate: outputRate,
      );

      var peakIndex = 0;
      var peak = 0.0;
      for (var i = 0; i < resampled.samples.length; i += 1) {
        final magnitude = resampled.samples[i].abs();
        if (magnitude > peak) {
          peak = magnitude;
          peakIndex = i;
        }
      }
      final expected = at * outputRate / inputRate;
      expect(
        peakIndex.toDouble(),
        closeTo(expected, 1.0),
        reason:
            'the impulse must land on its own instant (±1 sample for the '
            'grid change), not $peakIndex vs $expected',
      );
    });

    test('the same holds downward, and at a big ratio', () {
      for (final rates in const [
        (48000, 44100),
        (48000, 32000),
        (22050, 48000),
        (8000, 48000),
      ]) {
        final (inputRate, outputRate) = rates;
        const at = 1500;
        final samples = Float32List(6000);
        samples[at] = 1.0;

        final resampled = resampleAudioReference(
          samples: samples,
          channels: 1,
          inputRate: inputRate,
          outputRate: outputRate,
        );
        var peakIndex = 0;
        var peak = 0.0;
        for (var i = 0; i < resampled.samples.length; i += 1) {
          final magnitude = resampled.samples[i].abs();
          if (magnitude > peak) {
            peak = magnitude;
            peakIndex = i;
          }
        }
        expect(
          peakIndex.toDouble(),
          closeTo(at * outputRate / inputRate, 1.0),
          reason: '$inputRate → $outputRate shifted the impulse',
        );
      }
    });
  });

  group('stopband', () {
    test('an image lands more than 100 dB down', () {
      // A 1 kHz tone upsampled 44.1k → 48k: the image sits at
      // inputRate − f = 43.1 kHz. A linear interpolator leaves that around
      // −30 dB; this must bury it.
      const inputRate = 44100;
      const outputRate = 48000;
      final resampled = resampleAudioReference(
        samples: tone(1000, inputRate),
        channels: 1,
        inputRate: inputRate,
        outputRate: outputRate,
      );

      final signal = binDb(resampled.samples, outputRate, 1000);
      final image = binDb(resampled.samples, outputRate, inputRate - 1000);
      expect(
        signal - image,
        greaterThan(100.0),
        reason:
            'image rejection was only ${(signal - image).toStringAsFixed(1)} dB',
      );
    });

    test('content above the new Nyquist is removed, not folded back', () {
      // 15 kHz into a 24 kHz project cannot survive — Nyquist is 12 kHz.
      // The wrong answer is not "quiet", it is a 9 kHz tone that was never
      // played, sitting right in the middle of the audible band.
      const inputRate = 48000;
      const outputRate = 24000;
      final resampled = resampleAudioReference(
        samples: tone(15000, inputRate),
        channels: 1,
        inputRate: inputRate,
        outputRate: outputRate,
      );
      final folded = binDb(resampled.samples, outputRate, 9000);
      final reference = binDb(tone(9000, outputRate), outputRate, 9000);
      expect(
        reference - folded,
        greaterThan(100.0),
        reason:
            '15 kHz folded back to 9 kHz at only '
            '${(reference - folded).toStringAsFixed(1)} dB down',
      );
    });
  });

  group('passband', () {
    test('audible tones keep their level', () {
      const inputRate = 44100;
      const outputRate = 48000;
      for (final frequency in const [100, 1000, 5000, 10000, 15000]) {
        final source = tone(frequency, inputRate);
        final resampled = resampleAudioReference(
          samples: source,
          channels: 1,
          inputRate: inputRate,
          outputRate: outputRate,
        );
        final before = binDb(source, inputRate, frequency);
        final after = binDb(resampled.samples, outputRate, frequency);
        expect(
          after - before,
          closeTo(0.0, 0.1),
          reason:
              '${frequency}Hz moved by '
              '${(after - before).toStringAsFixed(3)} dB',
        );
      }
    });
  });

  group('the common path costs nothing', () {
    test('a source already at the project rate is untouched', () {
      // Most SE libraries and dialogue are already 44.1k or 48k, so this
      // is the path that usually runs — and it must be bit-exact, not
      // "near enough".
      final samples = tone(440, 48000);
      final resampled = resampleAudioReference(
        samples: samples,
        channels: 1,
        inputRate: 48000,
        outputRate: 48000,
      );
      expect(resampled.passthrough, isTrue);
      expect(identical(resampled.samples, samples), isTrue);
      expect(resampled.taps, 0);
    });
  });

  group('shape and geometry', () {
    test('the output length follows the ratio', () {
      final resampled = resampleAudioReference(
        samples: Float32List(44100),
        channels: 1,
        inputRate: 44100,
        outputRate: 48000,
      );
      expect(resampled.length, 48000);
      expect(resampled.sampleRate, 48000);
    });

    test('channels stay in their lanes', () {
      // L holds a tone, R holds silence. A stride bug shows up as leakage.
      final left = tone(1000, 44100);
      final frames = left.length;
      final samples = Float32List(frames * 2);
      for (var i = 0; i < frames; i += 1) {
        samples[i * 2] = left[i];
        samples[i * 2 + 1] = 0.0;
      }
      final resampled = resampleAudioReference(
        samples: samples,
        channels: 2,
        inputRate: 44100,
        outputRate: 48000,
      );
      expect(resampled.channels, 2);

      var rightPeak = 0.0;
      var leftPeak = 0.0;
      for (var i = 0; i < resampled.length; i += 1) {
        leftPeak = math.max(leftPeak, resampled.samples[i * 2].abs());
        rightPeak = math.max(rightPeak, resampled.samples[i * 2 + 1].abs());
      }
      expect(leftPeak, greaterThan(0.4));
      expect(rightPeak, lessThan(1e-6), reason: 'signal leaked into R');
    });

    test('the filter is odd-length and symmetric', () {
      // Symmetry IS linear phase — the property the delay compensation
      // rests on. If a change ever broke it, the delay would stop being
      // constant and no correction could fix it.
      final kernel = buildResamplerKernel(
        taps: 641,
        cutoff: 0.5 / 160 * 0.95,
        beta: kaiserBeta(120),
        interpolation: 160,
      );
      expect(kernel.length.isOdd, isTrue);
      for (var i = 0; i < kernel.length ~/ 2; i += 1) {
        expect(
          kernel[i],
          closeTo(kernel[kernel.length - 1 - i], 1e-12),
          reason: 'tap $i is not mirrored',
        );
      }
    });
  });

  group('filter design', () {
    test('the Bessel kernel matches known values', () {
      expect(besselI0(0.0), closeTo(1.0, 1e-12));
      expect(besselI0(1.0), closeTo(1.2660658777520084, 1e-10));
      expect(besselI0(2.0), closeTo(2.2795853023360673, 1e-10));
      expect(besselI0(5.0), closeTo(27.239871823604442, 1e-8));
    });

    test('beta follows the stopband target', () {
      expect(kaiserBeta(120.0), closeTo(0.1102 * (120.0 - 8.7), 1e-12));
      expect(kaiserBeta(10.0), 0.0);
      expect(kaiserBeta(60.0), greaterThan(kaiserBeta(40.0)));
    });
  });

  group('degenerate input', () {
    test('nonsense geometry returns empty rather than throwing', () {
      for (final probe in [
        resampleAudioReference(
          samples: Float32List(8),
          channels: 0,
          inputRate: 44100,
          outputRate: 48000,
        ),
        resampleAudioReference(
          samples: Float32List(8),
          channels: 1,
          inputRate: 0,
          outputRate: 48000,
        ),
        resampleAudioReference(
          samples: Float32List(8),
          channels: 1,
          inputRate: 44100,
          outputRate: 0,
        ),
      ]) {
        expect(probe.samples, isEmpty);
      }
    });

    test('an empty source yields an empty result', () {
      final resampled = resampleAudioReference(
        samples: Float32List(0),
        channels: 2,
        inputRate: 44100,
        outputRate: 48000,
      );
      expect(resampled.samples, isEmpty);
      expect(resampled.sampleRate, 48000);
    });
  });
}
