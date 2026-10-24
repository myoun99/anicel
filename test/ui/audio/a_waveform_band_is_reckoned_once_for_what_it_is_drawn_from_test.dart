import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/audio/waveform_painter.dart';

/// A strip built again over the same sound — a tab opened again, a panel
/// unfolded — draws the band it reckoned before, and a band is reckoned
/// anew for whatever it is drawn from (frame-panels-build-in-one-frame,
/// 10-24: the storyboard's two sounds were 32,000 buckets reckoned at every
/// opening).
///
/// The kept band is pinned by PIXELS against the same painter over a sound
/// no band was kept for — reckoned FIRST, so nothing kept can answer it.
void main() {
  const canvas = 64.0;
  const rate = ProjectFrameRate.fps24;
  const ink = Color(0xFF00FF00);
  const values = [1.0, 0.5, 1.0, 0.25, 1.0, 0.75, 1.0, 0.5];

  /// One second of [values], eight buckets — a new sound each call.
  AudioPeaks sound() =>
      AudioPeaks(bucketsPerSecond: 8, peaks: Float32List.fromList(values));

  WaveformPainter painter(
    AudioPeaks peaks, {
    double gain = 1.0,
    int leadingFrames = 0,
    Axis axis = Axis.horizontal,
  }) => WaveformPainter(
    peaks: peaks,
    frameRate: rate,
    pixelsPerFrame: canvas / 24,
    color: ink,
    axis: axis,
    leadingFrames: leadingFrames,
    gain: gain,
  );

  Future<Uint32List> paint(
    WaveformPainter painter, {
    Size size = const Size(canvas, canvas),
    Rect? clip,
  }) async {
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);
    if (clip != null) {
      c.clipRect(clip);
    }
    painter.paint(c, size);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(canvas.toInt(), canvas.toInt());
      try {
        final data = await image.toByteData();
        return data!.buffer.asUint32List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  test('a strip painted again over the same sound draws the band it '
      'reckoned', () async {
    final peaks = sound();
    final first = await paint(painter(peaks));
    final before = WaveformPainter.debugBandsReckoned;
    final again = await paint(painter(peaks));

    expect(WaveformPainter.debugBandsReckoned, before);
    expect(again, first);
    expect(again.any((pixel) => pixel != 0), isTrue);
  });

  for (final (name, base, variant) in <(
    String,
    Future<Uint32List> Function(AudioPeaks peaks),
    Future<Uint32List> Function(AudioPeaks peaks),
  )>[
    (
      'its painter (the gain)',
      (peaks) => paint(painter(peaks)),
      (peaks) => paint(painter(peaks, gain: 0.5)),
    ),
    (
      'its painter (the trim)',
      (peaks) => paint(painter(peaks)),
      (peaks) => paint(painter(peaks, leadingFrames: 6)),
    ),
    (
      'its painter (the axis)',
      (peaks) => paint(painter(peaks)),
      (peaks) => paint(painter(peaks, axis: Axis.vertical)),
    ),
    (
      'its size',
      (peaks) => paint(painter(peaks)),
      (peaks) => paint(painter(peaks), size: const Size(canvas, canvas / 2)),
    ),
    (
      'the stretch its clip shows',
      (peaks) => paint(
        painter(peaks),
        clip: const Rect.fromLTWH(0, 0, canvas / 4, canvas),
      ),
      (peaks) => paint(painter(peaks)),
    ),
  ]) {
    test('a band is reckoned anew for $name', () async {
      final expected = await variant(sound());
      final peaks = sound();
      final kept = await base(peaks);

      final drawn = await variant(peaks);

      expect(kept, isNot(expected), reason: 'the case varies nothing');
      expect(drawn, expected);
    });
  }
}
