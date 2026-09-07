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

/// The LOUDEST channel of the frame starting at [base] in an interleaved
/// [samples] buffer of [channels], as a magnitude.
///
/// The one answer both envelopes take when no fold is chosen — the file
/// fold below, and the live meter's `device` mode. Never a downmix:
/// downmixing SUMS the channels, so a stereo pair in opposite phase
/// cancels to silence and the waveform shows nothing while the sound plays
/// perfectly well.
///
/// ⚠️Per FRAME, and inlined: the clamp and gain around the callers stay
/// written out because THOSE run per sample.
@pragma('vm:prefer-inline')
double loudestChannelMagnitude(Float32List samples, int base, int channels) {
  var loudest = 0.0;
  for (var channel = 0; channel < channels; channel += 1) {
    final value = samples[base + channel];
    final magnitude = value < 0 ? -value : value;
    if (magnitude > loudest) {
      loudest = magnitude;
    }
  }
  return loudest;
}

/// The bucket state machine behind every `|peak|` envelope: a running
/// maximum per bucket, counted to [samplesPerBucket], pushed clamped and
/// reset.
///
/// One object because it was two — the file fold below and the live
/// recording meter each kept four pieces of mutable state and each drove
/// them by hand, and they had already drifted in two ways that happen to
/// give equal numbers (clamp before the max vs clamp at the push;
/// flush-the-partial vs never flush). Whether a partial bucket lands is now
/// the CALLER's decision, said out loud by calling [flush] or not: a file
/// has an end, a take in progress does not.
final class AudioPeakBucketFold {
  AudioPeakBucketFold({required this.samplesPerBucket});

  /// Frames per bucket — `sampleRate ~/ bucketsPerSecond`.
  final int samplesPerBucket;

  /// The buckets landed so far, in order.
  final List<double> peaks = [];

  double _bucketMax = 0;
  int _bucketFill = 0;

  /// Feeds one frame's magnitude. Clamping happens at the PUSH, which is
  /// the same answer as clamping first (max and clamp commute) and one
  /// comparison per bucket instead of one per frame.
  @pragma('vm:prefer-inline')
  void add(double magnitude) {
    if (magnitude > _bucketMax) {
      _bucketMax = magnitude;
    }
    _bucketFill += 1;
    if (_bucketFill == samplesPerBucket) {
      peaks.add(_bucketMax > 1.0 ? 1.0 : _bucketMax);
      _bucketMax = 0;
      _bucketFill = 0;
    }
  }

  /// Lands a partial bucket — the end-of-file rule. A live take never
  /// calls this: its partial bucket waits for the next chunk.
  void flush() {
    if (_bucketFill > 0) {
      peaks.add(_bucketMax > 1.0 ? 1.0 : _bucketMax);
      _bucketMax = 0;
      _bucketFill = 0;
    }
  }

  void reset() {
    peaks.clear();
    _bucketMax = 0;
    _bucketFill = 0;
  }

  Float32List toFloat32List() => Float32List.fromList(peaks);
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
  final fold = AudioPeakBucketFold(samplesPerBucket: samplesPerBucket);
  for (var frame = 0; frame < frameCount; frame += 1) {
    fold.add(loudestChannelMagnitude(samples, frame * channels, channels));
  }
  // A file has an end: the last partial bucket lands.
  fold.flush();
  return AudioPeaks(
    bucketsPerSecond: bucketsPerSecond,
    peaks: fold.toFloat32List(),
  );
}
