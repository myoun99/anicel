/// Waveform peaks — the data type and the fold that computes it from
/// conformed PCM. (This file once held an ffmpeg-based extractor; the
/// EXPORT-AUDIO round removed ffmpeg from every audio path, and peaks now
/// come exclusively from the conform pipeline's own decode.)
library;

import 'dart:typed_data';

import '../../models/project_frame_rate.dart';

/// Downsampled |peak| envelope of one audio file: [bucketsPerSecond]
/// buckets, each the maximum absolute amplitude (0..1) of its slice — what
/// the waveform strips paint and where clip durations come from.
class AudioPeaks {
  const AudioPeaks({required this.bucketsPerSecond, required this.peaks});

  final int bucketsPerSecond;
  final Float32List peaks;

  double get durationSeconds =>
      bucketsPerSecond <= 0 ? 0 : peaks.length / bucketsPerSecond;

  /// Whole frames the clip covers at [rate] (at least 1 for non-empty
  /// audio).
  ///
  /// The length is exactly `peaks.length / bucketsPerSecond` seconds —
  /// a ratio of two integers — so the frame count is computed from that
  /// ratio directly. Going through [durationSeconds] as a double was how
  /// an exactly-2-second file at 24fps used to measure 49 frames.
  int durationFrames(ProjectFrameRate rate) {
    if (bucketsPerSecond <= 0) {
      return 1;
    }
    final frames = rate.framesCoveringExactSeconds(
      peaks.length,
      bucketsPerSecond,
    );
    return frames < 1 ? 1 : frames;
  }
}

/// Folds decoded PCM into the same `|peak|` envelope the waveform paints,
/// taking the LOUDEST channel at each point rather than mixing them down.
///
/// The ffmpeg path this replaces asked for `-ac 1`, a mono downmix, and
/// measured that. Downmixing SUMS the channels — so a stereo pair in
/// opposite phase cancels to silence, and the waveform shows nothing while
/// the sound plays perfectly well. A hard-panned effect shows at half its
/// real size for the same reason. No professional tool does this: Pro
/// Tools, Logic and Premiere all draw per-channel lanes, precisely so a
/// waveform can never hide audible sound.
///
/// Per-channel lanes need track height this app does not have (SE rows are
/// a fixed 28px, and there is no vertical zoom), so the channel MAXIMUM is
/// the honest single-lane answer: it can never cancel, and what you see is
/// the loudest thing you will hear.
AudioPeaks peaksFromSamples({
  required Float32List samples,
  required int channels,
  required int sampleRate,
  int bucketsPerSecond = 40,
}) {
  if (channels <= 0 || sampleRate <= 0 || bucketsPerSecond <= 0) {
    return AudioPeaks(
      bucketsPerSecond: bucketsPerSecond < 1 ? 1 : bucketsPerSecond,
      peaks: Float32List(0),
    );
  }
  final samplesPerBucket = sampleRate ~/ bucketsPerSecond;
  if (samplesPerBucket <= 0) {
    return AudioPeaks(bucketsPerSecond: bucketsPerSecond, peaks: Float32List(0));
  }
  final frameCount = samples.length ~/ channels;
  final peaks = <double>[];
  var bucketMax = 0.0;
  var bucketCount = 0;
  for (var frame = 0; frame < frameCount; frame += 1) {
    final base = frame * channels;
    for (var channel = 0; channel < channels; channel += 1) {
      final value = samples[base + channel];
      final magnitude = value < 0 ? -value : value;
      if (magnitude > bucketMax) {
        bucketMax = magnitude;
      }
    }
    bucketCount += 1;
    if (bucketCount == samplesPerBucket) {
      peaks.add(bucketMax > 1.0 ? 1.0 : bucketMax);
      bucketMax = 0;
      bucketCount = 0;
    }
  }
  if (bucketCount > 0) {
    peaks.add(bucketMax > 1.0 ? 1.0 : bucketMax);
  }
  return AudioPeaks(
    bucketsPerSecond: bucketsPerSecond,
    peaks: Float32List.fromList(peaks),
  );
}
