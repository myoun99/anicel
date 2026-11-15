import 'dart:typed_data';

import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/audio/engine_wave_views.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The engine's band steps a frame's pixels as a q8 (engineWaveViewsOf):
/// along a picture of few frames its rounding is nothing, along a whole file
/// it builds up — a half-hour sound across a viewer's row ran its band ~20
/// device pixels short of its end. Reckoned afresh before it reaches half a
/// device pixel, every view of the band stands where the frames do.
void main() {
  const rate = ProjectFrameRate.integer(24);
  AudioPeaks soundOf(int seconds) =>
      AudioPeaks(bucketsPerSecond: 80, peaks: Float32List(seconds * 80));

  EngineWaveSound wholeFile(AudioPeaks peaks) => (
    peaks: peaks,
    startFrame: 0,
    audibleFrames: peaks.durationFrames(rate),
    leadingFrames: 0,
    gain: 1,
  );

  test('a picture whose frame is a whole q8 draws its sound as one view', () {
    final peaks = soundOf(10);
    final views = engineWaveViewsOf(
      wholeFile(peaks),
      on: (
        along: (frame) => frame * 24.0,
        origin: 0,
        from: 0,
        to: 40,
        axis: Axis.horizontal,
        across: 28,
        devicePixelRatio: 1.5,
        frameRate: rate,
      ),
      ink: const Color(0xFF000000),
    );

    expect(views, hasLength(1));
    expect(views.single.frameQ8, 24 * 1.5 * 256);
    expect(views.single.along0, 0);
    expect(views.single.length, 240 * 24 * 1.5, reason: 'the whole sound');
  });

  test('a whole file across a row is reckoned afresh before half a device '
      'pixel builds up, and its views run on from each other to its end', () {
    final peaks = soundOf(30 * 60);
    final frames = peaks.durationFrames(rate);
    const dpr = 1.5;
    final perFrame = 1000 / frames;
    double along(int frame) => frame * perFrame;
    final views = engineWaveViewsOf(
      wholeFile(peaks),
      on: (
        along: along,
        origin: 0,
        from: 0,
        to: frames,
        axis: Axis.horizontal,
        across: 60,
        devicePixelRatio: dpr,
        frameRate: rate,
      ),
      ink: const Color(0xFF000000),
    );

    expect(views.length, greaterThan(1), reason: '⛔전제: the q8 rounds');
    for (final (index, view) in views.indexed) {
      final base = view.leadingFrames;
      final next = index + 1 < views.length
          ? views[index + 1].leadingFrames
          : frames;
      expect(next, greaterThan(base), reason: 'view $index runs on');
      // Where the pass puts the view's last frame edge, against where it
      // stands.
      final stepped = (next - base) * view.frameQ8 / 256;
      final stands = (along(next) - along(base)) * dpr;
      expect(
        (stepped - stands).abs(),
        lessThanOrEqualTo(0.5 + 1e-9),
        reason: 'view $index, frames $base to $next',
      );
      expect(view.along0, (-along(base) * dpr).round());
    }
    expect(views.first.leadingFrames, 0);
    expect(
      views.last.length,
      ((along(frames) - along(views.last.leadingFrames)) * dpr).round(),
      reason: 'the last view runs to the sound\'s end',
    );
  });
}
