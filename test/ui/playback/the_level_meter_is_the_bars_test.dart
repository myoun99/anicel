import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/playback/audio_level_meter.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

/// The playback level meter — nothing named it (2026-09-05).
///
/// 🚨⛔NO TROUGH. 유저 2026-08-13: 「드롭율 왼쪽에 **이상한 바탕색? 배경?
/// 사각형 패딩같은거** 있는데 삭제」 — a 6×24 grey rectangle painted whether
/// or not there was a level to show. The BARS are the meter; a silent one
/// shows nothing.
///
/// The colours are a warning, so they are pinned by the pixels a peak
/// actually paints: green through the working range, amber approaching
/// full scale, red at or over 1.0 — the moment the output stage starts
/// clipping, which until now only ears could catch.
void main() {
  const canvas = CanvasSize(width: 64, height: 64);
  const rate = ProjectFrameRate.fps24;

  CanvasPlaybackController controllerFor(WidgetTester tester) {
    final controller = CanvasPlaybackController(
      resolveProject: () => Project(
        id: const ProjectId('p'),
        name: 'P',
        frameRate: rate,
        cameraSize: canvas,
        createdAt: DateTime.utc(2026, 9, 5),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V',
            cuts: [
              Cut(
                id: const CutId('c'),
                name: 'c',
                layers: const [],
                duration: 12,
                canvasSize: canvas,
              ),
            ],
          ),
        ],
      ),
      resolveActiveCutId: () => const CutId('c'),
      resolveActiveTrackId: () => const TrackId('t'),
      resolveFrameRate: () => rate,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  /// The meter's own painter, rasterized. ⚠️Painted through a recorder
  /// rather than captured off a RepaintBoundary: `toImage` on a boundary
  /// hangs in a plain widget test.
  Future<Uint32List> pixelsFor(
    WidgetTester tester, {
    required double left,
    required double right,
    bool playing = true,
  }) async {
    final controller = controllerFor(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AudioLevelMeter(
              controller: controller,
              resolvePeaks: () => (left: left, right: right),
            ),
          ),
        ),
      ),
    );
    if (playing) {
      controller.attachTicker(tester);
      controller.play(scope: PlaybackScope.activeCut, startGlobalFrame: 3);
      await tester.pump();
    }

    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(AudioLevelMeter),
        matching: find.byType(CustomPaint),
      ),
    );
    // The painter already holds this frame's peaks, so the transport can
    // come down now — a ticker still running at the end of the test is a
    // leak the framework fails on, and each case opens two of them.
    if (playing) {
      controller.stop();
      controller.detachTicker();
    }

    // ⚠️`toImage` needs the REAL event loop: inside testWidgets the fake
    // clock never delivers it, and the await hangs for ever.
    return (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      paint.painter!.paint(Canvas(recorder), const Size(6, 24));
      final picture = recorder.endRecording();
      try {
        final image = await picture.toImage(6, 24);
        try {
          final data = await image.toByteData();
          return data!.buffer.asUint32List();
        } finally {
          image.dispose();
        }
      } finally {
        picture.dispose();
      }
    }))!;
  }

  int inkCount(Uint32List pixels) => pixels.where((pixel) => pixel != 0).length;

  /// ⚠️`toByteData` gives RAW RGBA, so a Uint32List read on a
  /// little-endian machine packs as ABGR — not the ARGB a Color prints.
  int rgbaOf(Color color) {
    final argb = color.toARGB32();
    return (argb & 0xFF000000) |
        ((argb & 0xFF) << 16) |
        (argb & 0xFF00) |
        ((argb >> 16) & 0xFF);
  }

  /// The colours the bars are painted IN, ignoring the antialiased edge
  /// pixels: a rectangle's interior is what says which warning it is.
  Set<int> barColoursOf(Uint32List pixels) {
    final counts = <int, int>{};
    for (final pixel in pixels) {
      // Only FULLY OPAQUE pixels: a rectangle's antialiased rim carries a
      // partial alpha, and it is the interior that says which warning the
      // bar is.
      if (pixel >>> 24 == 0xFF) {
        counts[pixel] = (counts[pixel] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) {
      return const {};
    }
    // The interiors dwarf the antialiased edges; a quarter of the biggest
    // run separates "this is the bar" from "this is its rim".
    final biggest = counts.values.reduce((a, b) => a > b ? a : b);
    return {
      for (final entry in counts.entries)
        if (entry.value * 4 >= biggest) entry.key,
    };
  }

  testWidgets('⛔a SILENT meter shows nothing at all — no trough, no '
      'background, no padding rectangle', (tester) async {
    expect(barColoursOf(await pixelsFor(tester, left: 0, right: 0)), isEmpty);
  });

  testWidgets('⛔a stopped transport meters silence', (tester) async {
    expect(
      barColoursOf(await pixelsFor(tester, left: 1, right: 1, playing: false)),
      isEmpty,
    );
  });

  testWidgets('🚨the working range is GREEN', (tester) async {
    expect(barColoursOf(await pixelsFor(tester, left: 0.4, right: 0.4)), {
      rgbaOf(const Color(0xFF43A047)),
    });
  });

  testWidgets('🚨approaching full scale turns AMBER', (tester) async {
    expect(barColoursOf(await pixelsFor(tester, left: 0.8, right: 0.8)), {
      rgbaOf(const Color(0xFFFFB300)),
    });
  });

  testWidgets('🚨at or over 1.0 it is RED — the moment the output stage '
      'starts clipping', (tester) async {
    for (final peak in [1.0, 1.4]) {
      expect(
        barColoursOf(await pixelsFor(tester, left: peak, right: peak)),
        {rgbaOf(const Color(0xFFE53935))},
        reason: 'peak $peak',
      );
    }
  });

  testWidgets('🚨the two channels are read SEPARATELY — a hot left beside a '
      'quiet right is what a meter is for', (tester) async {
    expect(barColoursOf(await pixelsFor(tester, left: 1.2, right: 0.3)), {
      rgbaOf(const Color(0xFFE53935)),
      rgbaOf(const Color(0xFF43A047)),
    });
  });

  testWidgets('a louder peak paints a TALLER bar', (tester) async {
    final quiet = inkCount(await pixelsFor(tester, left: 0.2, right: 0.2));
    final loud = inkCount(await pixelsFor(tester, left: 0.9, right: 0.9));

    expect(loud, greaterThan(quiet));
  });

  // ⚠️The clamp itself is not observable in the raster: an unclamped bar
  // is drawn from a negative top and the canvas simply clips it, so the
  // pixels inside the meter are the same either way (measured 2026-09-05,
  // the same shape as the waveform's edge clamps). What this pins is the
  // BEHAVIOUR a caller sees.
  testWidgets('a peak PAST full scale does not paint past the meter — the '
      'bar clamps rather than overflowing its box', (tester) async {
    final full = inkCount(await pixelsFor(tester, left: 1.0, right: 1.0));
    final overdriven = inkCount(await pixelsFor(tester, left: 4, right: 4));

    expect(overdriven, full);
  });
}
