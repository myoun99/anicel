import 'dart:math' as math;

import 'package:flutter/painting.dart' show Axis, Color;
import 'package:gpu_engine/gpu_engine.dart' show GpuWaveView;

import '../../models/project_frame_rate.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../timeline/timeline_grid_tile_ops.dart' show timelineGridPackRgba;

/// A sound where a picture shows it along a frame axis: its [peaks], the
/// axis frame its audible part starts on, how many frames it is audible
/// for, how far into its file it is there, and its gain.
typedef EngineWaveSound = ({
  AudioPeaks peaks,
  int startFrame,
  int audibleFrames,
  int leadingFrames,
  double gain,
});

/// The frame axis a picture is drawn along: the logical pixel each frame's
/// leading edge stands at ([along]) and the picture's first column on that
/// scale ([origin]); the frame at or before that column ([from]) and the
/// one at or past its last ([to]); the axis it runs along, how far across
/// it the band stands, the device pixels to a logical one, and the rate its
/// frames are counted at.
typedef EngineWaveAxis = ({
  double Function(int frame) along,
  double origin,
  int from,
  int to,
  Axis axis,
  double across,
  double devicePixelRatio,
  ProjectFrameRate frameRate,
});

/// [sound]'s band as the waveform pass draws it into a picture laid [on] a
/// frame axis, in [ink] — the views ([GpuGridBatch.wave]) drawn one after
/// another into that picture. Every place a sound's band is drawn on the
/// engine asks it here: a row's tile, the viewer's face, the offset strip,
/// the viewer's page.
///
/// Reckoned from the later of the picture's first frame and the sound's, a
/// whole frame into the file there: a column stands on a frame edge the
/// picture holds, so a pixel's rounding never builds up along a sound
/// longer than the picture. ↩️Each place reckoned its own view — the row's
/// tile this way, the viewer's page from its first column — the same
/// arithmetic twice and about to be four times (CLAUDE.md 절대명령 1).
///
/// A frame's pixels are the q8 the pass steps by, whose rounding builds up
/// frame after frame: where the frames a view runs would carry it past half
/// a device pixel — a whole file across a viewer's row, 43,200 frames for
/// half an hour — the band is reckoned afresh, a view at a time.
List<GpuWaveView> engineWaveViewsOf(
  EngineWaveSound sound, {
  required EngineWaveAxis on,
  required Color ink,
}) {
  final along = on.along;
  final dpr = on.devicePixelRatio;
  final soundEnd = sound.startFrame + sound.audibleFrames;
  final end = math.min(on.to, soundEnd);
  final first = math.max(on.from, sound.startFrame);
  if (end <= first) {
    return const [];
  }
  // A frame's pixels, q8: the distance between the picture's first two
  // edges.
  final exact = (along(on.from + 1) - along(on.from)) * dpr * 256;
  final frameQ8 = exact.round();
  final drift = (frameQ8 - exact).abs() / 256;
  final run = drift == 0 ? end - first : math.max(1, (0.5 / drift).floor());
  return [
    for (var base = first; base < end; base += run)
      (
        along0: ((on.origin - along(base)) * dpr).round(),
        length:
            ((along(base + run < end ? base + run : soundEnd) - along(base)) *
                    dpr)
                .round(),
        vertical: on.axis == Axis.vertical,
        frameQ8: frameQ8,
        fpsNumerator: on.frameRate.numerator,
        fpsDenominator: on.frameRate.denominator,
        bucketsPerSecond: sound.peaks.bucketsPerSecond,
        leadingFrames: sound.leadingFrames + base - sound.startFrame,
        acrossQ8: (on.across * dpr * 256).round(),
        gainQ16: (sound.gain * 65536).round(),
        rgba: timelineGridPackRgba(ink),
      ),
  ];
}
