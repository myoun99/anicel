import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/project_frame_rate.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../timeline/axis_turn.dart';
import '../repaint_props.dart';
import '../timeline/memo_token.dart';

/// Paints a clip's |peak| envelope as a filled band mirrored around the
/// row's center line, along [axis] (horizontal timeline rows, vertical
/// X-sheet columns). The widget's main-axis extent is expected to be
/// `durationFrames(frameRate) * pixelsPerFrame` — each bucket maps to
/// `pixelsPerFrame * fps / bucketsPerSecond` pixels.
class WaveformPainter extends CustomPainter with RepaintOnProps {
  const WaveformPainter({
    required this.peaks,
    required this.frameRate,
    required this.pixelsPerFrame,
    required this.color,
    this.axis = Axis.horizontal,
    this.leadingFrames = 0,
    this.gain = 1.0,
    this.fadeInFrames = 0,
    this.fadeOutFrames = 0,
  });

  final AudioPeaks peaks;
  final ProjectFrameRate frameRate;
  final double pixelsPerFrame;
  final Color color;
  final Axis axis;

  /// Frames skipped into the FILE before main-axis 0 — the clip's
  /// offsetFrames trim: the envelope starts mid-file, so the painted band
  /// stays aligned with what actually plays.
  final int leadingFrames;

  /// The clip's volume envelope, drawn INTO the band (amplitudes scale
  /// with what actually plays): [gain] scales the whole envelope (capped
  /// at 1 — the band cannot outgrow the row), [fadeInFrames] ramps up from
  /// the span start and [fadeOutFrames] ramps down toward the audible end
  /// (span end or file end, whichever comes first).
  final double gain;
  final int fadeInFrames;
  final int fadeOutFrames;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.peaks.isEmpty ||
        frameRate.numerator <= 0 ||
        pixelsPerFrame <= 0) {
      return;
    }
    final mainExtent = extentAlong(axis, size);
    final crossExtent = extentAcross(axis, size);
    final center = crossExtent / 2;
    final maxAmplitude = (crossExtent / 2) - 1;
    final pixelsPerBucket =
        pixelsPerFrame * frameRate.approximateFps / peaks.bucketsPerSecond;
    if (pixelsPerBucket <= 0) {
      return;
    }
    final leadingPixels = leadingFrames * pixelsPerFrame;
    final startBucket = leadingPixels <= 0
        ? 0
        : (leadingPixels / pixelsPerBucket).floor();

    // Where the audible part ends on the main axis: the span's own end or
    // the file running out, whichever is first — the fade-out anchor.
    final audibleEndPixels = math.min(
      mainExtent,
      (peaks.durationFrames(frameRate) - leadingFrames) * pixelsPerFrame,
    );
    final fadeInPixels = fadeInFrames * pixelsPerFrame;
    final fadeOutPixels = fadeOutFrames * pixelsPerFrame;
    final envelopeGain = math.min(1.0, gain);

    double envelopeAt(double main) {
      var factor = envelopeGain;
      if (fadeInPixels > 0 && main < fadeInPixels) {
        factor *= math.max(0, main / fadeInPixels);
      }
      final remaining = audibleEndPixels - main;
      if (fadeOutPixels > 0 && remaining < fadeOutPixels) {
        factor *= math.max(0, remaining / fadeOutPixels);
      }
      return factor;
    }

    final path = Path();
    final top = <Offset>[];
    final bottom = <Offset>[];
    for (var bucket = startBucket; bucket < peaks.peaks.length; bucket += 1) {
      var main = bucket * pixelsPerBucket - leadingPixels;
      var lastSample = false;
      // The offset usually lands MID-bucket: clamp the edge samples onto
      // the window instead of dropping them, or the band opens/closes up
      // to a bucket short — a gap that shifts with every dragged frame
      // (the "ends flicker while sliding" artifact).
      if (main < 0) {
        main = 0;
      }
      if (main >= mainExtent) {
        main = mainExtent;
        lastSample = true;
      }
      final amplitude = peaks.peaks[bucket] * maxAmplitude * envelopeAt(main);
      top.add(offsetAlong(axis, along: main, across: center - amplitude));
      bottom.add(offsetAlong(axis, along: main, across: center + amplitude));
      if (lastSample) {
        break;
      }
    }
    if (top.isEmpty) {
      return;
    }
    path.moveTo(top.first.dx, top.first.dy);
    for (final point in top.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    for (final point in bottom.reversed) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();

    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  Object get props => (
    ByIdentity(peaks),
    frameRate,
    pixelsPerFrame,
    color,
    axis,
    leadingFrames,
    gain,
    fadeInFrames,
    fadeOutFrames,
  );
}
