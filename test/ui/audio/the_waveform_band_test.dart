import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/audio/waveform_painter.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart' show rectAlong;

/// The waveform band — nothing named it (the audit's untested-file pass,
/// 2026-09-05).
///
/// It is a painter, so it is pinned by PIXELS: what the band covers, where
/// it starts once the clip is trimmed into the file, and how the clip's
/// gain narrows it. A test asserting on the painter's fields instead
/// would pass while the drawing moved.
///
/// The band is gpu-int-spec-timeline ②'s, a device column at a time (관제
/// F-71 ⑤): the group at the end pins each part of that definition by the
/// thickness it leaves in a column.
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
    double devicePixelRatio = 1,
  }) => WaveformPainter(
    peaks: peaks ?? loud(),
    frameRate: rate,
    pixelsPerFrame: pixelsPerFrame,
    color: ink,
    devicePixelRatio: devicePixelRatio,
    axis: axis,
    leadingFrames: leadingFrames,
    gain: gain,
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

  /// How many pixels of row [y] carry ink.
  int inkInRow(Uint32List pixels, int y) {
    var count = 0;
    for (var x = 0; x < size.toInt(); x += 1) {
      if (pixels[y * size.toInt() + x] != 0) {
        count += 1;
      }
    }
    return count;
  }

  /// Two channels, the one numbered [loud] at full and the other silent.
  AudioPeaks oneLoud(int loud) => AudioPeaks.ofChannels(
    bucketsPerSecond: 8,
    lanes: [
      for (var channel = 0; channel < 2; channel += 1)
        Float32List.fromList(List<double>.filled(8, channel == loud ? 1 : 0)),
    ],
  );

  // 🗣️F-71-Q4 (유저 2026-11-05) 「L · R 두 줄」 — inside the block.
  test('🚨a channel draws its own band in its own half — the first on top, '
      'the second under it', () async {
    final pixels = await paint(painter(peaks: oneLoud(0)));
    final half = size.toInt() ~/ 2;
    expect(
      inkInRow(pixels, half ~/ 2),
      greaterThan(0),
      reason: 'the loud channel, around the top half\'s middle',
    );
    expect(
      inkInColumn(pixels, 2),
      inInclusiveRange(half - 4, half),
      reason: 'it stands in its half, not across the row',
    );
    for (var y = half; y < size.toInt(); y += 1) {
      expect(inkInRow(pixels, y), 0, reason: 'the silent one, under it');
    }
  });

  test('the second channel draws in the lower half alone', () async {
    final pixels = await paint(painter(peaks: oneLoud(1)));
    final half = size.toInt() ~/ 2;
    expect(
      inkInRow(pixels, half + half ~/ 2),
      greaterThan(0),
      reason: 'the loud channel, around the lower half\'s middle',
    );
    for (var y = 0; y < half; y += 1) {
      expect(inkInRow(pixels, y), 0, reason: 'the silent one, over it');
    }
  });

  test('🚨down a COLUMN the first channel is on the left', () async {
    final pixels = await paint(
      painter(peaks: oneLoud(0), axis: Axis.vertical),
    );
    final half = size.toInt() ~/ 2;
    expect(inkInColumn(pixels, half ~/ 2), greaterThan(0));
    for (var x = half; x < size.toInt(); x += 1) {
      expect(inkInColumn(pixels, x), 0);
    }
  });

  /// 🚨★★★**THE SECONDS ENTRANCE IS THE SAME PAINTER, PIXEL FOR PIXEL.**
  ///
  /// The media viewer thinks in seconds and the timeline in frames, and a
  /// second painter written for the viewer would be a clone whatever its
  /// text (유저 2026-08-27: 「사본 남으면 진짜 용서안할게」). This is the
  /// assertion that keeps [WaveformPainter.perSecond] an ENTRANCE rather
  /// than a second implementation: same band, same pixels, from the two
  /// ways of saying the one number the arithmetic actually wants.
  test('perSecond lands on the same pixels as the frame-based band', () async {
    // 24fps × 2 px/frame = 48 pixels per second, said both ways.
    final byFrames = await paint(
      WaveformPainter(
        peaks: loud(),
        frameRate: rate,
        pixelsPerFrame: 2,
        color: ink,
        devicePixelRatio: 1,
      ),
    );
    final bySeconds = await paint(
      WaveformPainter.perSecond(
        peaks: loud(),
        pixelsPerSecond: 2 * rate.approximateFps,
        color: ink,
        devicePixelRatio: 1,
      ),
    );

    expect(inkTotal(byFrames), greaterThan(0), reason: 'fixture: it drew');
    expect(bySeconds, byFrames);
  });

  /// 🚨I-57 (10-13, profile, the user's project): a sound running far past
  /// the window built every bucket of its length into the band at every
  /// paint — 6–20ms of a cut crossing's frame. The band is drawn as far as
  /// the picture's own clip can show it, and these two hold both halves:
  /// what the clip shows is the band as a whole paint draws it, and what
  /// the clip hides is not built.
  group('a band drawn under a clip', () {
    // A shaped band trimmed MID-bucket, so the clip's edges fall between
    // two vertices and a band started a bucket late would open a gap.
    final shaped = peaksOf(const [
      0.2, 0.9, 0.4, 1.0, 0.1, 0.7, 0.5, 0.8, //
      0.3, 0.6, 0.9, 0.2, 0.5, 1.0, 0.4, 0.7,
    ]);

    Future<Uint32List> paintUnder(WaveformPainter painter, Rect clip) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..clipRect(clip);
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

    for (final axis in Axis.values) {
      test('${axis.name}: what the clip shows is the whole band\'s pixels',
          () async {
        final band = painter(peaks: shaped, leadingFrames: 13, axis: axis);
        // Whole pixels, so no column is half the clip's own edge.
        const from = 20;
        const to = 44;
        final clip = rectAlong(
          axis,
          along: (from: from.toDouble(), to: to.toDouble()),
          across: (from: 0, to: size),
        );
        final whole = await paint(band);
        final clipped = await paintUnder(band, clip);

        expect(inkTotal(clipped), greaterThan(0), reason: 'LIVENESS: it drew');
        // The band's THICKNESS at each step along it, in pixels: the alpha
        // across it, summed. ⚠️Not pixel for pixel — the rasterizer
        // antialiases an edge by the whole path it belongs to, and a band
        // cut short is another path: 🔬an edge pixel came out 165 where the
        // whole band's was 196 (10-13). A band that started a bucket late
        // or stopped a bucket short leaves whole steps bare.
        final width = size.toInt();
        double thicknessAt(Uint32List pixels, int along) {
          var alpha = 0;
          for (var across = 0; across < width; across += 1) {
            final index = axis == Axis.horizontal
                ? across * width + along
                : along * width + across;
            alpha += pixels[index] >>> 24;
          }
          return alpha / 255;
        }

        final wrong = <String>[];
        for (var along = 0; along < width; along += 1) {
          final inside = along >= from && along < to;
          final expected = inside ? thicknessAt(whole, along) : 0.0;
          final drawn = thicknessAt(clipped, along);
          if ((drawn - expected).abs() > 0.5) {
            wrong.add('$along: $drawn px where the whole band is $expected');
          }
        }
        expect(wrong, isEmpty);
      });
    }

    test('what the clip hides is not built', () {
      // A long sound: four hundred buckets, a band 3200px long, of which
      // the clip shows 64.
      final band = WaveformPainter(
        peaks: peaksOf(List<double>.filled(400, 1)),
        frameRate: rate,
        pixelsPerFrame: size / 24,
        color: ink,
        devicePixelRatio: 1,
      );
      final whole = _BandSpy(clip: Rect.largest);
      band.paint(whole, const Size(3200, size));
      final clipped = _BandSpy(clip: const Rect.fromLTRB(1600, 0, 1664, size));
      band.paint(clipped, const Size(3200, size));

      expect(
        whole.band!.getBounds().width,
        closeTo(3200, 8),
        reason: 'LIVENESS: unclipped, the band runs its whole length',
      );
      final bounds = clipped.band!.getBounds();
      // The columns the clip shows, and not one more.
      expect(bounds.left, 1600);
      expect(bounds.right, 1664);
      // A clip edge inside a column still shows that column.
      final halfway = _BandSpy(
        clip: const Rect.fromLTRB(1600.5, 0, 1663.5, size),
      );
      band.paint(halfway, const Size(3200, size));
      expect(halfway.band!.getBounds().left, 1600);
      expect(halfway.band!.getBounds().right, 1664);

      // A clip that shows none of it — before its start — draws nothing.
      final before = _BandSpy(clip: const Rect.fromLTRB(-100, 0, -10, size));
      band.paint(before, const Size(3200, size));
      expect(before.band, isNull);
    });
  });

  /// gpu-int-spec-timeline ②, part by part. One lane on a 64 px row: its
  /// center at 32 and its reach 31 (`share / 2 − 1`), so a column standing
  /// at height h is 2 · 31 · h px of ink thick.
  group('a column stands as high as the line through its buckets reaches '
      'inside it', () {
    /// A column's ink in pixels: its alpha summed down it, in [pixels]
    /// [width] wide.
    double thicknessAt(Uint32List pixels, int x, {int width = 64}) {
      var alpha = 0;
      for (var y = 0; y < pixels.length ~/ width; y += 1) {
        alpha += pixels[y * width + x] >>> 24;
      }
      return alpha / 255;
    }

    double inkOf(double height) => 2 * 31 * height;

    test('zoomed out, a column takes the highest bucket inside it', () async {
      // 256 buckets a second on 64 px a second: four buckets a pixel.
      // Column 0 is buckets 0 to 4 — its ends 0.2 and 0.5, and 0.9 between.
      // Column 1 is buckets 4 to 8 — its ends 0.5 and 0.1, and 0.1 between.
      final values = List<double>.filled(256, 0.25);
      values.setAll(0, const [0.2, 0.9, 0.1, 0.3, 0.5, 0.1, 0.1, 0.1, 0.1]);
      final pixels = await paint(
        painter(peaks: peaksOf(values, bucketsPerSecond: 256)),
      );
      expect(thicknessAt(pixels, 0), closeTo(inkOf(0.9), 0.6));
      expect(thicknessAt(pixels, 1), closeTo(inkOf(0.5), 0.6));
    });

    test('zoomed in, a column takes the line at its far end', () async {
      // Eight pixels a bucket, rising from 0.2 to 1.0 over the first:
      // column 0 ends at bucket 0.125 (0.3) and column 4 at 0.625 (0.7).
      final rising = peaksOf(const [0.2, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]);
      final pixels = await paint(painter(peaks: rising));
      expect(thicknessAt(pixels, 0), closeTo(inkOf(0.3), 0.6));
      expect(thicknessAt(pixels, 4), closeTo(inkOf(0.7), 0.6));
    });

    test('⛔a silent stretch draws nothing — no line down the center',
        () async {
      // Silent up to bucket 2 (16 px), then rising to 1.0 at bucket 3.
      final pixels = await paint(
        painter(peaks: peaksOf(const [0, 0, 0, 1, 0, 0, 0, 0])),
      );
      for (var x = 0; x < 16; x += 1) {
        expect(thicknessAt(pixels, x), 0, reason: 'column $x is silent');
      }
      expect(thicknessAt(pixels, 16), closeTo(inkOf(0.125), 0.6));
    });

    test('the band runs from the first bucket to the last, and no further',
        () async {
      // Eight buckets eight pixels apart: the last stands at 56 px.
      final eight = await paint(painter());
      expect(thicknessAt(eight, 55), closeTo(inkOf(1), 0.6));
      expect(thicknessAt(eight, 56), 0);
      // A sound of one bucket has no stretch at all.
      expect(inkTotal(await paint(painter(peaks: peaksOf(const [1])))), 0);
    });

    test('the strip\'s own end cuts the band', () async {
      // The sound runs 56 px; its strip is 40 px long, then 39.5.
      Future<Uint32List> strip(double length) async {
        final recorder = ui.PictureRecorder();
        painter().paint(Canvas(recorder), Size(length, size));
        final picture = recorder.endRecording();
        final image = await picture.toImage(size.toInt(), size.toInt());
        final pixels = (await image.toByteData())!.buffer.asUint32List();
        image.dispose();
        picture.dispose();
        return pixels;
      }

      final whole = await strip(40);
      expect(thicknessAt(whole, 39), closeTo(inkOf(1), 0.6));
      expect(thicknessAt(whole, 40), 0);
      // An end inside a column cuts that column where the strip ends.
      final half = await strip(39.5);
      expect(thicknessAt(half, 39), closeTo(inkOf(1) / 2, 1));
      expect(thicknessAt(half, 40), 0);
    });

    test('🚨a column is a DEVICE pixel, not a logical one', () async {
      // Eight logical pixels a bucket, rising from 0 to 1: a logical pixel
      // is two device columns at a ratio of 2, ending at buckets 1/16 and
      // 1/8; at a ratio of 1 both halves are one column ending at 1/8.
      Future<Uint32List> twice(double ratio) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(2);
        painter(
          peaks: peaksOf(const [0, 1, 1, 1, 1, 1, 1, 1]),
          devicePixelRatio: ratio,
        ).paint(canvas, const Size(size, size));
        final picture = recorder.endRecording();
        final image = await picture.toImage(128, 128);
        final pixels = (await image.toByteData())!.buffer.asUint32List();
        image.dispose();
        picture.dispose();
        return pixels;
      }

      Matcher device(double height) => closeTo(2 * inkOf(height), 0.6);
      final columns = await twice(2);
      expect(thicknessAt(columns, 0, width: 128), device(1 / 16));
      expect(thicknessAt(columns, 1, width: 128), device(1 / 8));
      final halves = await twice(1);
      expect(thicknessAt(halves, 0, width: 128), device(1 / 8));
      expect(thicknessAt(halves, 1, width: 128), device(1 / 8));
    });
  });
}

/// A canvas that tells the painter where its clip stands and keeps the band
/// it was handed.
final class _BandSpy implements Canvas {
  _BandSpy({required this.clip});

  final Rect clip;
  Path? band;

  @override
  Rect getLocalClipBounds() => clip;

  @override
  void drawPath(Path path, Paint paint) => band = path;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
