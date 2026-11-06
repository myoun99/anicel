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
  /// One lane: a mono sound, or one already folded to one.
  AudioPeaks({required this.bucketsPerSecond, required this.peaks})
    : lanes = List.unmodifiable([peaks]);

  /// A lane per channel, in the file's order — [peaks] is their loudest.
  AudioPeaks.ofChannels({
    required this.bucketsPerSecond,
    required List<Float32List> lanes,
  }) : lanes = List.unmodifiable(lanes),
       peaks = _loudestOf(lanes);

  final int bucketsPerSecond;

  /// The loudest channel at each bucket — what the length is read from.
  final Float32List peaks;

  /// Each channel's own envelope, which the waveform draws a lane of
  /// (`WaveformPainter`): 🗣️F-71-Q4 (유저 2026-11-05) 「L · R 두 줄」.
  final List<Float32List> lanes;

  static Float32List _loudestOf(List<Float32List> lanes) {
    if (lanes.length == 1) {
      return lanes.single;
    }
    var length = 0;
    for (final lane in lanes) {
      length = lane.length > length ? lane.length : length;
    }
    final loudest = Float32List(length);
    for (final lane in lanes) {
      for (var bucket = 0; bucket < lane.length; bucket += 1) {
        if (lane[bucket] > loudest[bucket]) {
          loudest[bucket] = lane[bucket];
        }
      }
    }
    return loudest;
  }

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

/// Folds decoded PCM into the `|peak|` envelopes the waveform paints: a
/// lane per channel, never mixed down.
///
/// The ffmpeg path this replaces asked for `-ac 1`, a mono downmix, and
/// measured that. Downmixing SUMS the channels — so a stereo pair in
/// opposite phase cancels to silence, and the waveform shows nothing while
/// the sound plays perfectly well. A hard-panned effect shows at half its
/// real size for the same reason. No professional tool does this: Pro
/// Tools, Logic and Premiere all draw per-channel lanes, precisely so a
/// waveform can never hide audible sound.
///
/// 🗣️F-71-Q4 (유저 2026-11-05) 「L · R 두 줄」, 「제일 큰 기준은
/// 프리미어프로나 다빈치」 — so the lanes are drawn, each in its own share
/// of the block. ↩️Per-channel lanes were judged to need track height this
/// app does not have (SE rows are a fixed 28px), and one lane drew the
/// channel MAXIMUM, which is still [AudioPeaks.peaks].
AudioPeaks peaksFromSamples({
  required Float32List samples,
  required int channels,
  required int sampleRate,
  int bucketsPerSecond = 40,
}) => peaksFromWindows(
  windows: [samples],
  channels: channels,
  sampleRate: sampleRate,
  bucketsPerSecond: bucketsPerSecond,
);

/// The same envelope of PCM that arrives a window at a time — [windows] in
/// order, each a run of whole interleaved frames — folded as one buffer
/// would be: a bucket runs on across a window's edge. What a long conform
/// is measured by without its PCM in memory.
AudioPeaks peaksFromWindows({
  required Iterable<Float32List> windows,
  required int channels,
  required int sampleRate,
  int bucketsPerSecond = 40,
}) {
  final fold = AudioPeaksOfWindows(
    channels: channels,
    sampleRate: sampleRate,
    bucketsPerSecond: bucketsPerSecond,
  );
  windows.forEach(fold.add);
  return fold.finish();
}

/// [peaksFromWindows] a window at a time, for a pass that does more with each
/// window than measure it — a conform written as it is made.
final class AudioPeaksOfWindows {
  AudioPeaksOfWindows({
    required this.channels,
    required int sampleRate,
    required this.bucketsPerSecond,
  }) : _folds =
           channels <= 0 ||
               sampleRate <= 0 ||
               bucketsPerSecond <= 0 ||
               sampleRate ~/ bucketsPerSecond <= 0
           ? null
           : [
               for (var channel = 0; channel < channels; channel += 1)
                 AudioPeakBucketFold(
                   samplesPerBucket: sampleRate ~/ bucketsPerSecond,
                 ),
             ];

  final int channels;
  final int bucketsPerSecond;

  /// A fold per channel; null where the geometry measures nothing.
  final List<AudioPeakBucketFold>? _folds;

  /// Folds [samples] — whole interleaved frames, after the ones before.
  void add(Float32List samples) {
    final folds = _folds;
    if (folds == null) {
      return;
    }
    final frameCount = samples.length ~/ channels;
    for (var frame = 0; frame < frameCount; frame += 1) {
      final base = frame * channels;
      for (var channel = 0; channel < channels; channel += 1) {
        folds[channel].add(samples[base + channel].abs());
      }
    }
  }

  /// The envelopes, once the last window is in.
  AudioPeaks finish() {
    final folds = _folds;
    if (folds == null) {
      return AudioPeaks(
        bucketsPerSecond: bucketsPerSecond < 1 ? 1 : bucketsPerSecond,
        peaks: Float32List(0),
      );
    }
    return AudioPeaks.ofChannels(
      bucketsPerSecond: bucketsPerSecond,
      lanes: [
        // A file has an end: the last partial bucket lands.
        for (final fold in folds) (fold..flush()).toFloat32List(),
      ],
    );
  }
}
