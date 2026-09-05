import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/audio/waveform_painter.dart';

/// The waveform band — nothing named it (the audit's untested-file pass,
/// 2026-09-05).
///
/// It is a painter, so it is pinned by PIXELS: what the band covers, where
/// it starts once the clip is trimmed into the file, and how the volume
/// envelope narrows it. A test asserting on the painter's fields instead
/// would pass while the drawing moved.
///
/// ⚠️The two edge CLAMPS (a bucket landing before 0 or past the window)
/// resisted every fixture: the band is a filled polygon, so moving a
/// vertex just off-canvas leaves the same region covered — even with a
/// fade measuring from the clamped position. Measured 2026-09-05; they
/// shape the vertex list rather than the pixels, so what pins them is
/// reading the code, not this file. Said here so the next reader does not
/// take their mutants' survival for "the clamps do nothing".
void main() {
  const size = 64.0;
  const rate = ProjectFrameRate.fps24;
  const ink = Color(0xFF00FF00);

  AudioPeaks peaksOf(List<double> values, {int bucketsPerSecond = 8}) =>
      AudioPeaks(
        bucketsPerSecond: bucketsPerSecond,
        peaks: Float32List.fromList(values),
      );

  /// A one-second clip at full amplitude: eight buckets, all 1.0.
  AudioPeaks loud() => peaksOf(List<double>.filled(8, 1));

  Future<Uint32List> paint(WaveformPainter painter) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, const Size(size, size));
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(size.toInt(), size.toInt());
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

  /// How many pixels of the given column carry ink.
  int inkInColumn(Uint32List pixels, int x) {
    var count = 0;
    for (var y = 0; y < size.toInt(); y += 1) {
      if (pixels[y * size.toInt() + x] != 0) {
        count += 1;
      }
    }
    return count;
  }

  int inkTotal(Uint32List pixels) => pixels.where((pixel) => pixel != 0).length;

  WaveformPainter painter({
    AudioPeaks? peaks,
    double pixelsPerFrame = size / 24,
    Axis axis = Axis.horizontal,
    int leadingFrames = 0,
    double gain = 1.0,
    int fadeInFrames = 0,
    int fadeOutFrames = 0,
  }) => WaveformPainter(
    peaks: peaks ?? loud(),
    frameRate: rate,
    pixelsPerFrame: pixelsPerFrame,
    color: ink,
    axis: axis,
    leadingFrames: leadingFrames,
    gain: gain,
    fadeInFrames: fadeInFrames,
    fadeOutFrames: fadeOutFrames,
  );

  test('⛔empty peaks paint NOTHING — a clip still loading is not a flat '
      'line', () async {
    expect(inkTotal(await paint(painter(peaks: peaksOf(const [])))), 0);
  });

  test(
    '⛔a zero pixels-per-frame paints nothing rather than dividing by it',
    () async {
      expect(inkTotal(await paint(painter(pixelsPerFrame: 0))), 0);
    },
  );

  test('a loud clip fills a band around the row centre', () async {
    final pixels = await paint(painter());

    expect(inkTotal(pixels), greaterThan(0));
    expect(
      inkInColumn(pixels, 2),
      greaterThan(size ~/ 2),
      reason: 'full amplitude mirrors nearly the whole row height',
    );
  });

  test('🚨a QUIET clip draws a narrower band — the band is the envelope, '
      'not a fill', () async {
    final loudPixels = await paint(painter());
    final quietPixels = await paint(
      painter(peaks: peaksOf(List<double>.filled(8, 0.25))),
    );

    expect(inkTotal(quietPixels), lessThan(inkTotal(loudPixels)));
  });

  test('🚨GAIN scales the whole envelope, and is CAPPED at 1 — the band '
      'cannot outgrow the row', () async {
    final plain = inkTotal(await paint(painter()));
    final halved = inkTotal(await paint(painter(gain: 0.5)));
    final overdriven = inkTotal(await paint(painter(gain: 4)));

    expect(halved, lessThan(plain));
    expect(overdriven, plain, reason: 'capped, not clipped by the row edge');
  });

  test('🚨a FADE IN ramps the band up from the span start — the near edge '
      'is thinner than the middle', () async {
    final pixels = await paint(painter(fadeInFrames: 12));

    expect(inkInColumn(pixels, 1), lessThan(inkInColumn(pixels, 30)));
  });

  test('a FADE OUT ramps it down toward the audible end', () async {
    final pixels = await paint(painter(fadeOutFrames: 12));

    expect(
      inkInColumn(pixels, size.toInt() - 2),
      lessThan(inkInColumn(pixels, 30)),
    );
  });

  test('🚨a TRIMMED clip starts its envelope mid-file — the band stays '
      'aligned with what actually plays, and does not open a gap that '
      'shifts with every dragged frame', () async {
    // 13 frames lands MID-bucket, which is what exercises the clamp: an
    // offset that divides evenly never produces a negative sample.
    final pixels = await paint(painter(leadingFrames: 13));

    expect(
      inkInColumn(pixels, 0),
      greaterThan(0),
      reason:
          'the edge sample is clamped onto the window rather than '
          'dropped, so the band does not start a bucket short',
    );
  });

  test('🚨a clip LONGER than the window ends its band ON the window edge — '
      'the last sample is clamped there rather than drawn past it, which '
      'is what keeps the fade landing where the eye expects', () async {
    final pixels = await paint(
      painter(peaks: peaksOf(List<double>.filled(16, 1)), fadeOutFrames: 6),
    );

    expect(
      inkInColumn(pixels, size.toInt() - 1),
      lessThan(inkInColumn(pixels, 30)),
      reason:
          'the fade is measured at the CLAMPED position, so the far '
          'edge is thin; measured past the edge it would still be full',
    );
  });

  test('🚨the X-sheet paints the same band down a COLUMN', () async {
    final horizontal = await paint(painter());
    final vertical = await paint(painter(axis: Axis.vertical));

    expect(inkTotal(vertical), greaterThan(0));
    expect(
      inkTotal(vertical),
      closeTo(inkTotal(horizontal), inkTotal(horizontal) * 0.2),
      reason: 'the same envelope, turned',
    );

    // A QUIET clip makes the axis visible: its band is narrow, so a
    // vertical one leaves the outer columns empty while the centre is
    // full. At full amplitude both axes fill nearly everything and the
    // two are indistinguishable.
    final quietVertical = await paint(
      painter(
        peaks: peaksOf(List<double>.filled(8, 0.25)),
        axis: Axis.vertical,
      ),
    );
    expect(inkInColumn(quietVertical, 1), 0);
    expect(inkInColumn(quietVertical, size.toInt() ~/ 2), greaterThan(0));
  });
}
