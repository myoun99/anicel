import 'dart:typed_data';

import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/audio/engine_wave_views.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// A SOUND WITH NO BUCKET HAS NO BAND (engineWaveViewsOf). The engine takes
/// no peaks of no lane, nor of an empty one, and refuses in the paint that
/// hands them over — and every place that draws a band on the engine hands
/// a sound's peaks over once a view of it, so a sound with no view is
/// never handed.
///
/// The take being recorded is that sound: it has no lane till its first
/// chunk says how many channels there are, and no bucket till one fills
/// (2026-11-23: its row's tile threw in the first paints of a recording).
void main() {
  const rate = ProjectFrameRate.fps24;

  List<Object> viewsOf(AudioPeaks peaks) => engineWaveViewsOf(
    (
      peaks: peaks,
      startFrame: 0,
      // A block of the take stands over its frames whatever was heard.
      audibleFrames: 12,
      leadingFrames: 0,
      gain: 1,
    ),
    on: (
      along: (frame) => frame * 24.0,
      origin: 0,
      from: 0,
      to: 12,
      axis: Axis.horizontal,
      across: 28,
      devicePixelRatio: 1,
      frameRate: rate,
    ),
    ink: const Color(0xFF000000),
  );

  test('⛔premise: a sound of one bucket has a view', () {
    expect(
      viewsOf(AudioPeaks(bucketsPerSecond: 40, peaks: Float32List(1))),
      hasLength(1),
    );
  });

  test('a take before its first chunk — no lane — has none', () {
    expect(
      viewsOf(AudioPeaks.ofChannels(bucketsPerSecond: 40, lanes: const [])),
      isEmpty,
    );
  });

  test('a take before its first bucket fills — empty lanes — has none', () {
    expect(
      viewsOf(
        AudioPeaks.ofChannels(
          bucketsPerSecond: 40,
          lanes: [Float32List(0), Float32List(0)],
        ),
      ),
      isEmpty,
    );
    expect(
      viewsOf(AudioPeaks(bucketsPerSecond: 40, peaks: Float32List(0))),
      isEmpty,
    );
  });
}
