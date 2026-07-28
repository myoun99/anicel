import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';

/// The waveform envelope computed from decoded PCM, taking the loudest
/// channel instead of a mono downmix.
///
/// The cases that matter are the ones the old ffmpeg `-ac 1` path got
/// wrong: a downmix SUMS channels, so opposite-phase stereo cancels to
/// silence and a hard-panned effect halves — the waveform hiding sound that
/// plays perfectly well.
void main() {
  const rate = 48000;
  const buckets = 40; // 1200 samples per bucket

  Float32List interleave(List<double> left, List<double> right) {
    final out = Float32List(left.length * 2);
    for (var index = 0; index < left.length; index += 1) {
      out[index * 2] = left[index];
      out[index * 2 + 1] = right[index];
    }
    return out;
  }

  Float32List constant(double value, int frames) =>
      Float32List(frames)..fillRange(0, frames, value);

  group('the failures a mono downmix causes', () {
    test('opposite-phase stereo does not vanish', () {
      // L = +0.8, R = -0.8. Summed, this is silence — the old path drew a
      // flat line while the sound played.
      final samples = interleave(
        List<double>.filled(1200, 0.8),
        List<double>.filled(1200, -0.8),
      );
      final peaks = peaksFromSamples(
        samples: samples,
        channels: 2,
        sampleRate: rate,
        bucketsPerSecond: buckets,
      );
      expect(peaks.peaks, hasLength(1));
      expect(peaks.peaks[0], closeTo(0.8, 1e-6));
    });

    test('a hard-panned sound shows at its real size, not half', () {
      // Silence left, full right — a footstep panned right. A downmix
      // would draw it at 0.45.
      final samples = interleave(
        List<double>.filled(1200, 0.0),
        List<double>.filled(1200, 0.9),
      );
      final peaks = peaksFromSamples(
        samples: samples,
        channels: 2,
        sampleRate: rate,
        bucketsPerSecond: buckets,
      );
      expect(peaks.peaks[0], closeTo(0.9, 1e-6));
    });
  });

  group('envelope shape', () {
    test('each bucket holds its own maximum', () {
      final samples = Float32List(3600);
      for (var index = 0; index < 1200; index += 1) {
        samples[index] = 0.25;
        samples[1200 + index] = 0.5;
        samples[2400 + index] = 1.0;
      }
      final peaks = peaksFromSamples(
        samples: samples,
        channels: 1,
        sampleRate: rate,
        bucketsPerSecond: buckets,
      );
      expect(peaks.peaks.toList(), [0.25, 0.5, 1.0]);
    });

    test('a spike anywhere in a bucket survives it', () {
      // Buckets are a MAXIMUM, not an average: one loud sample must not be
      // averaged into invisibility.
      final samples = constant(0.0, 1200);
      samples[700] = 0.95;
      final peaks = peaksFromSamples(
        samples: samples,
        channels: 1,
        sampleRate: rate,
        bucketsPerSecond: buckets,
      );
      expect(peaks.peaks[0], closeTo(0.95, 1e-6));
    });

    test('magnitude ignores sign', () {
      final samples = Float32List.fromList(
        List<double>.generate(1200, (i) => i.isEven ? -0.7 : 0.3),
      );
      final peaks = peaksFromSamples(
        samples: samples,
        channels: 1,
        sampleRate: rate,
        bucketsPerSecond: buckets,
      );
      expect(peaks.peaks[0], closeTo(0.7, 1e-6));
    });

    test('a trailing partial bucket still lands', () {
      final peaks = peaksFromSamples(
        samples: constant(0.6, 1800),
        channels: 1,
        sampleRate: rate,
        bucketsPerSecond: buckets,
      );
      expect(peaks.peaks, hasLength(2));
      expect(peaks.peaks[1], closeTo(0.6, 1e-6));
    });

    test('over-unity input is capped at the band edge', () {
      // The bus has headroom; the DISPLAY band does not — a peak past 1
      // would paint outside its row.
      final peaks = peaksFromSamples(
        samples: constant(2.5, 1200),
        channels: 1,
        sampleRate: rate,
        bucketsPerSecond: buckets,
      );
      expect(peaks.peaks[0], 1.0);
    });
  });

  group('duration', () {
    test('the frame count matches the real length', () {
      // 2 seconds of stereo at 48k.
      final peaks = peaksFromSamples(
        samples: Float32List(48000 * 2 * 2),
        channels: 2,
        sampleRate: rate,
        bucketsPerSecond: buckets,
      );
      expect(peaks.peaks, hasLength(80));
      expect(peaks.durationFrames(const ProjectFrameRate.integer(24)), 48);
    });
  });

  group('degenerate input', () {
    test('empty, zero-channel and zero-rate inputs stay empty', () {
      for (final probe in [
        peaksFromSamples(
          samples: Float32List(0),
          channels: 1,
          sampleRate: rate,
        ),
        peaksFromSamples(
          samples: constant(0.5, 100),
          channels: 0,
          sampleRate: rate,
        ),
        peaksFromSamples(
          samples: constant(0.5, 100),
          channels: 1,
          sampleRate: 0,
        ),
      ]) {
        expect(probe.peaks, isEmpty);
      }
    });

    test('a bucket rate above the sample rate does not divide by zero', () {
      final peaks = peaksFromSamples(
        samples: constant(0.5, 100),
        channels: 1,
        sampleRate: 100,
        bucketsPerSecond: 1000,
      );
      expect(peaks.peaks, isEmpty);
    });
  });
}
