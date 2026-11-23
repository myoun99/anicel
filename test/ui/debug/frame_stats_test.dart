import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuSampling;

import 'package:anicel/main.dart';
import 'package:anicel/src/native/screen_texture.dart';
import 'package:anicel/src/ui/debug/engine_behind.dart';
import 'package:anicel/src/ui/debug/frame_stats.dart';
import 'package:anicel/src/ui/debug/frame_stats_readout.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/debug/picture_writes.dart';
import 'package:anicel/src/ui/debug/pointer_clock.dart';
import 'package:anicel/src/ui/debug/screen_asked.dart';
import 'package:anicel/src/ui/debug/stroke_steps.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';

/// Repaints whenever its notifier ticks, so a test can make a bake happen
/// on demand. `shouldRepaint` is false on purpose: the `repaint` listenable
/// is what drives it, which is the same path a real painter uses.
class _TickPainter extends CustomPainter {
  const _TickPainter(Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF336699),
    );
  }

  @override
  bool shouldRepaint(_TickPainter oldDelegate) => false;
}

/// One synthetic frame. Every duration is expressed in milliseconds so
/// the expectations below read as the numbers a person would see on
/// screen.
FrameTiming _frame({
  required double uiMs,
  required double rasterMs,
  double vsyncToBuildMs = 0,
  double buildToRasterMs = 0,
  int atMs = 0,
  int layerCacheCount = 0,
  int layerCacheBytes = 0,
  int pictureCacheCount = 0,
  int pictureCacheBytes = 0,
}) {
  int us(double ms) => (ms * 1000).round();
  final vsyncStart = us(atMs.toDouble());
  final buildStart = vsyncStart + us(vsyncToBuildMs);
  final buildFinish = buildStart + us(uiMs);
  final rasterStart = buildFinish + us(buildToRasterMs);
  final rasterFinish = rasterStart + us(rasterMs);
  return FrameTiming(
    vsyncStart: vsyncStart,
    buildStart: buildStart,
    buildFinish: buildFinish,
    rasterStart: rasterStart,
    rasterFinish: rasterFinish,
    rasterFinishWallTime: rasterFinish,
    layerCacheCount: layerCacheCount,
    layerCacheBytes: layerCacheBytes,
    pictureCacheCount: pictureCacheCount,
    pictureCacheBytes: pictureCacheBytes,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FrameStats.install();
    FrameStats.reset();
  });
  tearDown(() {
    FrameStats.reset();
    MeasurementMode.reset();
  });

  group('the switch', () {
    test('is off unless --dart-define=QA_FRAME_STATS=true seeds it', () {
      expect(
        MeasurementMode.startWithFrameStats,
        isFalse,
        reason: 'default builds must not draw a measurement readout',
      );
      expect(MeasurementMode.frameStats.value, isFalse);
    });

    test('reset returns it to the build default', () {
      MeasurementMode.frameStats.value = true;
      MeasurementMode.reset();
      expect(
        MeasurementMode.frameStats.value,
        MeasurementMode.startWithFrameStats,
      );
    });

    test('turning it off empties the window and unpublishes', () {
      MeasurementMode.frameStats.value = true;
      FrameStats.debugFeed(<FrameTiming>[_frame(uiMs: 1, rasterMs: 2)]);
      FrameStats.publish();
      expect(FrameStats.latest.value, isNotNull);

      MeasurementMode.frameStats.value = false;
      expect(
        FrameStats.latest.value,
        isNull,
        reason: 'a stale window read as a live one would be worse than none',
      );
    });

    test('turning it off forgets the pointer packets timed while it was '
        'up', () {
      MeasurementMode.frameStats.value = true;
      PointerClock.handled(points: 2, micros: 300);

      MeasurementMode.frameStats.value = false;

      expect(PointerClock.packetsCounted, 0);
      expect(PointerClock.packetMicros, isEmpty);
    });
  });

  test('install registers exactly once however often it is called', () {
    final before = FrameStats.debugRegistrations;
    FrameStats.install();
    FrameStats.install();
    FrameStats.install();
    expect(
      FrameStats.debugRegistrations,
      before,
      reason: 'a duplicated timings callback would count every frame twice',
    );
  });

  group('recording', () {
    test('ignores frames while the switch is off', () {
      FrameStats.debugRecord(<FrameTiming>[_frame(uiMs: 1, rasterMs: 40)]);
      expect(FrameStats.latest.value, isNull);
    });

    test('republishes on the frame clock, not on every frame', () {
      MeasurementMode.frameStats.value = true;

      // First frame publishes immediately — otherwise the readout would
      // sit on "no frames yet" for a quarter second after every toggle.
      FrameStats.debugRecord(<FrameTiming>[
        _frame(uiMs: 1, rasterMs: 10, atMs: 0),
      ]);
      expect(FrameStats.latest.value!.rasterP50, 10.0);

      // Frames inside the interval accumulate but do not republish, so
      // the readout is not part of what it measures.
      for (var ms = 16; ms < 250; ms += 16) {
        FrameStats.debugRecord(<FrameTiming>[
          _frame(uiMs: 1, rasterMs: 99, atMs: ms),
        ]);
      }
      expect(
        FrameStats.latest.value!.rasterP50,
        10.0,
        reason: 'still the first publication',
      );

      // Crossing the interval publishes the whole accumulated window.
      FrameStats.debugRecord(<FrameTiming>[
        _frame(uiMs: 1, rasterMs: 99, atMs: 250),
      ]);
      expect(FrameStats.latest.value!.rasterP50, 99.0);
      expect(FrameStats.latest.value!.frames, 17);
    });
  });

  group('the window', () {
    test('publishes nothing until a frame has arrived', () {
      FrameStats.publish();
      expect(FrameStats.latest.value, isNull);
    });

    test('keeps the NEWEST frames when it overflows', () {
      // MORE THAN HALF a window of cheap frames, then a full window of
      // expensive ones. Keeping the newest leaves nothing but expensive
      // frames, so every percentile reads 20. Trimming from the wrong
      // end would keep the cheap majority and p50 would read 1.0 —
      // and the majority is the point: a handful of stale frames would
      // sink below the median and the test would pass either way.
      FrameStats.debugFeed(<FrameTiming>[
        for (var i = 0; i < FrameStats.windowFrames ~/ 2 + 10; i += 1)
          _frame(uiMs: 1, rasterMs: 1, atMs: i),
      ]);
      FrameStats.debugFeed(<FrameTiming>[
        for (var i = 0; i < FrameStats.windowFrames; i += 1)
          _frame(uiMs: 2, rasterMs: 20, atMs: 100 + i),
      ]);
      FrameStats.publish();

      final stats = FrameStats.latest.value!;
      expect(stats.frames, FrameStats.windowFrames);
      expect(stats.rasterP50, 20.0);
      expect(stats.rasterWorst, 20.0);
    });
  });

  group('the arithmetic', () {
    test('percentiles are nearest-rank over the window, in milliseconds', () {
      // 1..100 ms of raster. Nearest rank on 100 samples: p50 -> index
      // 50 (=51 ms), p95 -> index 94 (=95 ms), max -> index 99.
      FrameStats.debugFeed(<FrameTiming>[
        for (var i = 1; i <= 100; i += 1)
          _frame(uiMs: i / 10, rasterMs: i.toDouble(), atMs: i),
      ]);
      FrameStats.publish();

      final stats = FrameStats.latest.value!;
      expect(stats.rasterP50, 51.0);
      expect(stats.rasterP95, 95.0);
      expect(stats.rasterWorst, 100.0);
      expect(stats.uiP50, closeTo(5.1, 0.0001));
      expect(stats.uiWorst, closeTo(10.0, 0.0001));
    });

    test('latency is the whole span, not the two durations added', () {
      // vsync -> build is dead time inside the pipeline: 5 ms of it,
      // 2 ms of build, 3 ms of raster. Adding the durations gives 5;
      // the span is 10, and the span is what the pen feels.
      FrameStats.debugFeed(<FrameTiming>[
        _frame(uiMs: 2, rasterMs: 3, vsyncToBuildMs: 5),
      ]);
      FrameStats.publish();

      final stats = FrameStats.latest.value!;
      expect(stats.uiP50, 2.0);
      expect(stats.rasterP50, 3.0);
      expect(
        stats.latencyP50,
        10.0,
        reason: 'totalSpan is vsyncStart..rasterFinish, dead time included',
      );
    });

    test('cache figures are the LAST frame, because they are a level', () {
      // A cache filling up: 0 entries, then 2, then 5. Averaging would
      // report 2.33 and describe a state the app was never in.
      FrameStats.debugFeed(<FrameTiming>[
        _frame(uiMs: 1, rasterMs: 1, atMs: 0),
        _frame(
          uiMs: 1,
          rasterMs: 1,
          atMs: 16,
          layerCacheCount: 2,
          layerCacheBytes: 1024 * 1024,
        ),
        _frame(
          uiMs: 1,
          rasterMs: 1,
          atMs: 32,
          layerCacheCount: 5,
          layerCacheBytes: 4 * 1024 * 1024,
          pictureCacheCount: 3,
          pictureCacheBytes: 2 * 1024 * 1024,
        ),
      ]);
      FrameStats.publish();

      final stats = FrameStats.latest.value!;
      expect(stats.layerCacheCount, 5);
      expect(stats.layerCacheMegabytes, closeTo(4.0, 0.0001));
      expect(stats.pictureCacheCount, 3);
      expect(stats.pictureCacheMegabytes, closeTo(2.0, 0.0001));
    });

    test('fps comes from the vsync span, not from the frame count', () {
      // 61 frames at a 16 ms cadence spans 960 ms => 63.5 fps. A naive
      // frames/windowFrames would say something else entirely.
      FrameStats.debugFeed(<FrameTiming>[
        for (var i = 0; i <= 60; i += 1)
          _frame(uiMs: 1, rasterMs: 1, atMs: i * 16),
      ]);
      FrameStats.publish();

      final stats = FrameStats.latest.value!;
      expect(stats.frames, 61);
      expect(stats.windowSeconds, closeTo(0.96, 0.0001));
      expect(stats.framesPerSecond, closeTo(63.54, 0.01));
    });

    test('the bake rate is a slope, not the session total', () {
      // The counter climbs for the life of the process; what says "a
      // panel is re-baking on the pointer" is its slope, not its total.
      FrameStats.debugFeed(<FrameTiming>[
        for (var i = 0; i <= 60; i += 1)
          _frame(uiMs: 1, rasterMs: 1, atMs: i * 16),
      ]);
      FrameStats.publish();
      final first = FrameStats.latest.value!;
      expect(
        first.bakesPerSecond,
        0,
        reason: 'the first publication has no previous reading to slope from',
      );

      FrameStats.publish();
      expect(
        FrameStats.latest.value!.bakesPerSecond,
        0,
        reason: 'no bakes happened between the two, so the slope is flat',
      );
    });

    test('what a frame stood for before its build and before its raster is '
        'read apart from both', () {
      // Each wait in an order of its own, so one read for the other shows.
      FrameStats.debugFeed(<FrameTiming>[
        _frame(uiMs: 1, rasterMs: 1, vsyncToBuildMs: 1, buildToRasterMs: 7),
        _frame(uiMs: 1, rasterMs: 1, vsyncToBuildMs: 3, buildToRasterMs: 5),
        _frame(uiMs: 1, rasterMs: 1, vsyncToBuildMs: 2, buildToRasterMs: 9),
      ]);
      FrameStats.publish();

      final stats = FrameStats.latest.value!;
      expect([stats.buildWaitP50, stats.buildWaitP95], [2.0, 3.0]);
      expect([stats.rasterWaitP50, stats.rasterWaitP95], [7.0, 9.0]);
      expect([stats.uiP50, stats.rasterP50], [1.0, 1.0]);
    });

    test('the screen lines are the engine screens\' newest frames — from '
        'their draw to being put up, and part by part', () {
      ScreenTexture.debugForgetUps();
      addTearDown(ScreenTexture.debugForgetUps);
      // Each part largest in a frame of its own.
      for (final up in const [
        (draw: 1000, finish: 4000, show: 2000),
        (draw: 3000, finish: 20000, show: 500),
        (draw: 2000, finish: 6000, show: 9000),
      ]) {
        ScreenTexture.debugWentUp(up);
      }
      FrameStats.debugFeed(<FrameTiming>[_frame(uiMs: 1, rasterMs: 1)]);
      FrameStats.publish();

      final stats = FrameStats.latest.value!;
      expect(
        [stats.screenUpP50, stats.screenUpP95],
        [17.0, 23.5],
        reason: 'a frame\'s way up is its three parts together',
      );
      expect([stats.screenDrawP50, stats.screenDrawP95], [2.0, 3.0]);
      expect([stats.screenFinishP50, stats.screenFinishP95], [6.0, 20.0]);
      expect([stats.screenShowP50, stats.screenShowP95], [2.0, 9.0]);
    });

    test('the screens\' rates are slopes over the interval between two '
        'publications, as the bakes\' is', () {
      const up = (draw: 0, finish: 1000, show: 0);
      ScreenTexture.debugForgetUps();
      addTearDown(ScreenTexture.debugForgetUps);
      ScreenTexture.debugWentUp(up, behind: true);
      // A window of FOUR SECONDS, published twice a QUARTER SECOND apart.
      FrameStats.debugFeed(<FrameTiming>[
        for (var ms = 0; ms <= 4000; ms += 40)
          _frame(uiMs: 1, rasterMs: 1, atMs: ms),
      ]);
      FrameStats.publish();
      expect(
        [
          FrameStats.latest.value!.screensUpPerSecond,
          FrameStats.latest.value!.screensBehindPerSecond,
        ],
        [0, 0],
        reason: 'the first publication has no reading before it',
      );

      for (var i = 0; i < 5; i += 1) {
        ScreenTexture.debugWentUp(up, behind: i < 2);
      }
      FrameStats.debugFeed(<FrameTiming>[
        _frame(uiMs: 1, rasterMs: 1, atMs: 4250),
      ]);
      FrameStats.publish();

      expect(
        FrameStats.latest.value!.screensUpPerSecond,
        closeTo(5 / 0.25, 0.01),
        reason: 'five went up in the quarter second between the two',
      );
      expect(
        FrameStats.latest.value!.screensBehindPerSecond,
        closeTo(2 / 0.25, 0.01),
        reason: 'two of them behind what was asked for',
      );
    });

    test('the pointer line is the newest packets and their slopes — the '
        'points, the packets and the time they took a second', () {
      PointerClock.handled(points: 1, micros: 900);
      FrameStats.debugFeed(<FrameTiming>[
        for (var ms = 0; ms <= 4000; ms += 40)
          _frame(uiMs: 1, rasterMs: 1, atMs: ms),
      ]);
      FrameStats.publish();
      final first = FrameStats.latest.value!;
      expect(
        [
          first.pointsPerSecond,
          first.packetsPerSecond,
          first.pointerMillisPerSecond,
        ],
        [0, 0, 0],
        reason: 'the first publication has no reading before it',
      );

      // Five packets of twelve points, five milliseconds in all.
      for (final (points, micros) in const [
        (2, 300),
        (4, 2500),
        (1, 100),
        (3, 1700),
        (2, 400),
      ]) {
        PointerClock.handled(points: points, micros: micros);
      }
      FrameStats.debugFeed(<FrameTiming>[
        _frame(uiMs: 1, rasterMs: 1, atMs: 4250),
      ]);
      FrameStats.publish();

      final stats = FrameStats.latest.value!;
      expect(stats.packetsPerSecond, closeTo(5 / 0.25, 0.01));
      expect(stats.pointsPerSecond, closeTo(12 / 0.25, 0.01));
      expect(stats.pointerMillisPerSecond, closeTo(5 / 0.25, 0.01));
      expect(
        [stats.pointerP50, stats.pointerP95],
        [0.9, 2.5],
        reason: 'over the six packets kept: 100 300 400 900 1700 2500 µs',
      );
    });

    testWidgets('the GPU line is the submits behind as published, and the '
        'most read at a frame built since the last publication', (
      tester,
    ) async {
      MeasurementMode.frameStats.value = true;
      var behind = 7;
      EngineBehind.debugNow = () => behind;
      addTearDown(() => EngineBehind.debugNow = null);
      tester.binding.scheduleFrame();
      await tester.pump();
      behind = 2;
      FrameStats.debugFeed(<FrameTiming>[_frame(uiMs: 1, rasterMs: 1)]);
      FrameStats.publish();
      final first = FrameStats.latest.value!;
      expect([first.gpuBehind, first.gpuBehindWorst], [2, 7]);

      FrameStats.publish();
      final next = FrameStats.latest.value!;
      expect(
        [next.gpuBehind, next.gpuBehindWorst],
        [2, 2],
        reason: 'the most since the last publication, not since the first',
      );
    });

    testWidgets('the stroke lines are the newest steps and their slope — the '
        'dabs each carried, how long its first dab was held for it, and how '
        'long till the frame that showed it was up', (tester) async {
      MeasurementMode.frameStats.value = true;
      var now = 0;
      StrokeSteps.debugMicros = () => now;
      addTearDown(() => StrokeSteps.debugMicros = null);
      Future<void> step(
        int dabs, {
        required int queued,
        required int laid,
        required int up,
      }) async {
        now = queued;
        StrokeSteps.queued();
        now = laid;
        StrokeSteps.stepped(dabs, together: null);
        now = up;
        tester.binding.scheduleFrame();
        await tester.pump();
      }

      await step(1, queued: 0, laid: 2000, up: 5000);
      FrameStats.debugFeed(<FrameTiming>[
        for (var ms = 0; ms <= 4000; ms += 40)
          _frame(uiMs: 1, rasterMs: 1, atMs: ms),
      ]);
      FrameStats.publish();
      expect(
        FrameStats.latest.value!.stepsPerSecond,
        0,
        reason: 'the first publication has no reading before it',
      );

      await step(9, queued: 10000, laid: 18000, up: 30000);
      await step(2, queued: 40000, laid: 41000, up: 44000);
      await step(3, queued: 50000, laid: 54000, up: 60000);
      FrameStats.debugFeed(<FrameTiming>[
        _frame(uiMs: 1, rasterMs: 1, atMs: 4250),
      ]);
      FrameStats.publish();

      final stats = FrameStats.latest.value!;
      expect(stats.stepsPerSecond, closeTo(3 / 0.25, 0.01));
      expect(
        [stats.dabsPerStepP50, stats.dabsPerStepWorst],
        [3, 9],
        reason: 'over the four steps kept: 1 2 3 9 dabs',
      );
      expect(
        [stats.strokeHeldP50, stats.strokeHeldP95],
        [4.0, 8.0],
        reason: 'held 2 8 1 4 ms',
      );
      expect(
        [stats.strokeUpP50, stats.strokeUpP95],
        [10.0, 20.0],
        reason: 'up 5 20 4 10 ms after their first dab',
      );

      FrameStats.reset();
      expect(
        [StrokeSteps.stepsCounted, StrokeSteps.dabsKept],
        [0, isEmpty],
        reason: 'what was counted while last up says nothing of now',
      );
    });

    testWidgets('the slope is over the interval it measured, not the window', (
      tester,
    ) async {
      // 🚨 The test above cannot see the bug this one exists for: with
      // zero bakes, EVERY denominator gives zero. The first version of
      // this instrument divided the delta accumulated since the last
      // publication (a quarter second) by the whole window's span
      // (seconds), and so answered "0.0/s" no matter what was baking.
      // Only a fixture that actually bakes can tell the two apart.
      MeasurementMode.frameStats.value = true;
      final repaint = ValueNotifier<int>(0);
      addTearDown(repaint.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 100,
                height: 100,
                child: StaticRaster(
                  debugLabel: 'rate-fixture',
                  // The stand-down is a separate question; letting it fire
                  // here would silently reduce the delta to nothing and
                  // make this test vacuous again.
                  maxConsecutiveCaptures: 1000,
                  child: CustomPaint(painter: _TickPainter(repaint)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // A window spanning FOUR SECONDS, published twice a QUARTER SECOND
      // apart. The two intervals differ by 17x, which is the whole point.
      FrameStats.debugFeed(<FrameTiming>[
        for (var ms = 0; ms <= 4000; ms += 40)
          _frame(uiMs: 1, rasterMs: 1, atMs: ms),
      ]);
      FrameStats.publish();
      expect(FrameStats.latest.value!.windowSeconds, closeTo(4.0, 0.001));

      final before = StaticRaster.censusCaptures;
      for (var i = 0; i < 5; i += 1) {
        repaint.value += 1;
        await tester.pump();
      }
      final baked = StaticRaster.censusCaptures - before;
      expect(
        baked,
        greaterThan(0),
        reason:
            'the fixture never baked, so any arithmetic would pass — this '
            'assertion is the difference between a test and a decoration',
      );

      FrameStats.debugFeed(<FrameTiming>[
        _frame(uiMs: 1, rasterMs: 1, atMs: 4250),
      ]);
      FrameStats.publish();
      final stats = FrameStats.latest.value!;
      expect(
        stats.frames,
        102,
        reason:
            'the pumps must not have injected timings of their own, or the '
            'window is not the one the arithmetic below assumes',
      );

      expect(
        stats.bakesPerSecond,
        closeTo(baked / 0.25, 0.01),
        reason: 'the delta happened over the quarter second between publishes',
      );
      expect(
        stats.bakesPerSecond,
        isNot(closeTo(baked / stats.windowSeconds, 0.01)),
        reason:
            'that is the old answer — a quarter-second delta spread over a '
            'four-second window, low by the ratio between them',
      );
    });

    testWidgets('closing a panel does not make the rate go negative', (
      tester,
    ) async {
      // 🚨 The census SHRINKS — a surface leaves it on detach and on
      // dispose — so a total summed over live members goes DOWN whenever
      // a panel closes or a dock is rearranged. A slope taken across that
      // is negative, and `-4.0/s` is printed on screen as confidently as
      // any other number.
      MeasurementMode.frameStats.value = true;
      final repaint = ValueNotifier<int>(0);
      addTearDown(repaint.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 100,
                height: 100,
                child: StaticRaster(
                  debugLabel: 'closing-fixture',
                  maxConsecutiveCaptures: 1000,
                  child: CustomPaint(painter: _TickPainter(repaint)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        StaticRaster.censusCaptures,
        greaterThan(0),
        reason: 'nothing baked, so unmounting it could not lose anything',
      );

      FrameStats.debugFeed(<FrameTiming>[
        _frame(uiMs: 1, rasterMs: 1, atMs: 0),
        _frame(uiMs: 1, rasterMs: 1, atMs: 16),
      ]);
      FrameStats.publish();

      // The panel closes. Its bakes still happened.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      expect(StaticRaster.census, isEmpty);

      FrameStats.debugFeed(<FrameTiming>[
        _frame(uiMs: 1, rasterMs: 1, atMs: 266),
      ]);
      FrameStats.publish();

      expect(
        FrameStats.latest.value!.bakesPerSecond,
        greaterThanOrEqualTo(0),
        reason: 'a count of things that happened cannot become smaller',
      );
    });

    test('a single frame reports no span rather than an infinite rate', () {
      FrameStats.debugFeed(<FrameTiming>[_frame(uiMs: 1, rasterMs: 1)]);
      FrameStats.publish();

      final stats = FrameStats.latest.value!;
      expect(stats.windowSeconds, 0);
      expect(stats.framesPerSecond, 0);
    });
  });

  group('the readout', () {
    testWidgets('is absent until the switch is on, and never eats a tap', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MeasurementReadoutHost(child: Text('app', textDirection: TextDirection.ltr)),
        ),
      );
      expect(find.byType(FrameStatsReadout), findsNothing);

      MeasurementMode.frameStats.value = true;
      await tester.pump();
      expect(find.byType(FrameStatsReadout), findsOneWidget);

      // The instrument sits over whatever panel happens to be under it,
      // so it must not be the thing that receives the click.
      final ignoring = tester.widgetList<IgnorePointer>(
        find.ancestor(
          of: find.byType(FrameStatsReadout),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignoring.any((w) => w.ignoring), isTrue);
    });

    testWidgets('says so when no frames have arrived', (tester) async {
      MeasurementMode.frameStats.value = true;
      await tester.pumpWidget(
        const MaterialApp(home: MeasurementReadoutHost(child: SizedBox())),
      );
      await tester.pump();
      expect(find.textContaining('no frames yet'), findsOneWidget);
    });

    testWidgets('prints raster, UI, latency and both cache lines', (
      tester,
    ) async {
      MeasurementMode.frameStats.value = true;
      FrameStats.debugFeed(<FrameTiming>[
        _frame(
          uiMs: 0.4,
          rasterMs: 12.3,
          vsyncToBuildMs: 8,
          layerCacheCount: 3,
          layerCacheBytes: 4 * 1024 * 1024,
        ),
      ]);
      FrameStats.publish();

      await tester.pumpWidget(
        const MaterialApp(home: MeasurementReadoutHost(child: SizedBox())),
      );
      await tester.pump();

      expect(find.textContaining('RASTER'), findsOneWidget);
      expect(find.textContaining('12.3'), findsOneWidget);
      expect(find.textContaining('LATENCY'), findsOneWidget);
      expect(find.textContaining('SCREEN'), findsOneWidget);
      expect(find.textContaining('layer   cache 3'), findsOneWidget);
      expect(find.textContaining('picture cache 0'), findsOneWidget);
    });

    testWidgets('prints what a frame waited for, a screen\'s frame part by '
        'part, and the pointer packets', (tester) async {
      MeasurementMode.frameStats.value = true;
      ScreenTexture.debugForgetUps();
      addTearDown(ScreenTexture.debugForgetUps);
      ScreenTexture.debugWentUp((draw: 1100, finish: 22200, show: 3300));
      PointerClock.handled(points: 3, micros: 4400);
      FrameStats.debugFeed(<FrameTiming>[
        _frame(
          uiMs: 0.4,
          rasterMs: 0.6,
          vsyncToBuildMs: 5.5,
          buildToRasterMs: 7.7,
        ),
      ]);
      FrameStats.publish();

      await tester.pumpWidget(
        const MaterialApp(home: MeasurementReadoutHost(child: SizedBox())),
      );
      await tester.pump();

      // Each figure once, on the line that names it.
      for (final (line, figure) in const [
        (' waits  build', '5.5'),
        (' waits  build', 'raster p50   7.7'),
        ('SCREEN', '26.6'),
        ('SCREEN', 'behind'),
        (' draw', '1.1'),
        (' finish', '22.2'),
        (' show', '3.3'),
        ('POINTER', '4.4'),
        ('POINTER', 'pts/s'),
      ]) {
        expect(
          find.textContaining(RegExp('^${RegExp.escape(line)}.*$figure')),
          findsOneWidget,
          reason: '$line … $figure',
        );
      }
      expect(
        find.text(' path   —'),
        findsOneWidget,
        reason: 'no screen was opened: its row stands, saying none',
      );
    });

    testWidgets('prints a stroke\'s steps, the submits behind on the GPU, the '
        'memory held and the display\'s rate', (tester) async {
      MeasurementMode.frameStats.value = true;
      var now = 0;
      StrokeSteps.debugMicros = () => now;
      addTearDown(() => StrokeSteps.debugMicros = null);
      StrokeSteps.queued();
      now = 6600;
      StrokeSteps.stepped(7, together: null);
      now = 9900;
      tester.binding.scheduleFrame();
      await tester.pump();
      FrameStats.debugFeed(<FrameTiming>[_frame(uiMs: 1, rasterMs: 1)]);
      FrameStats.publish();

      await tester.pumpWidget(
        const MaterialApp(home: MeasurementReadoutHost(child: SizedBox())),
      );
      await tester.pump();

      for (final (line, figure) in const [
        ('FRAME STATS', r'fps  display \d+Hz$'),
        ('STROKE', r'steps/s  dabs/step p50 7  max 7$'),
        (' held', r'p50   6\.6'),
        (' pen→up', r'p50   9\.9'),
        // No engine is open in a test: none of its figures, not a zero.
        ('GPU', r'behind —  max —  timestamps —$'),
        ('MEMORY', r'app \d+\.\d MB  screens 0\.0 MB  vram —$'),
      ]) {
        expect(
          find.textContaining(RegExp('^${RegExp.escape(line)}.*$figure')),
          findsOneWidget,
          reason: '$line … $figure',
        );
      }
    });

    testWidgets('prints a stroke\'s first step and its landing apart — none '
        'till there is one — and the press to up over the strokes kept', (
      tester,
    ) async {
      MeasurementMode.frameStats.value = true;
      var now = 0;
      StrokeSteps.debugMicros = () => now;
      addTearDown(() => StrokeSteps.debugMicros = null);
      addTearDown(() => EngineBehind.debugNow = null);
      addTearDown(ScreenAsked.debugForget);
      FrameStats.debugFeed(<FrameTiming>[_frame(uiMs: 1, rasterMs: 1)]);
      FrameStats.publish();
      await tester.pumpWidget(
        const MaterialApp(home: MeasurementReadoutHost(child: SizedBox())),
      );
      await tester.pump();
      expect(find.text(' first  —'), findsOneWidget);
      expect(find.text(' landed —'), findsOneWidget);
      expect(find.text('  wrote —'), findsNWidgets(2));

      Future<void> aStroke(int pressedAt, {required int upAfter}) async {
        now = pressedAt;
        StrokeSteps.pressed();
        now += 400;
        StrokeSteps.queued();
        now += 500;
        StrokeSteps.armed();
        now += 1100;
        StrokeSteps.stepped(1, together: null);
        PictureWrites.wrote(PictureWrite.inPlace);
        PictureWrites.wrote(PictureWrite.whole);
        ScreenAsked.shown((
          columns: 64,
          rows: 10,
          texels: 640,
          moved: null,
          scale: 1,
          mode: GpuSampling.nearest,
        ));
        now = pressedAt + upAfter;
        tester.binding.scheduleFrame();
        await tester.pump();
      }

      EngineBehind.debugNow = () => 3;
      await aStroke(10000, upAfter: 20000);
      await aStroke(40000, upAfter: 10000);
      await aStroke(60000, upAfter: 5000);
      EngineBehind.debugNow = () => 4;
      now = 70000;
      StrokeSteps.landed(together: null);
      PictureWrites.wrote(PictureWrite.copied);
      now = 76000;
      tester.binding.scheduleFrame();
      await tester.pump();
      FrameStats.debugFeed(<FrameTiming>[_frame(uiMs: 1, rasterMs: 1)]);
      FrameStats.publish();
      final stats = FrameStats.latest.value!;
      expect(stats.firstStep, StrokeSteps.firstStep);
      expect(stats.landing, StrokeSteps.landing);
      expect(
        [stats.firstUpP50, stats.firstUpWorst],
        [10.0, 20.0],
        reason: 'press to up 20 10 5 ms',
      );
      await tester.pump();

      for (final line in const [
        ' first  arm 0.9  dab 0.4  held 1.6  up 5.0  behind 3',
        '  wrote in place 1  copied 0  whole 1  64x10  x1.00  nearest',
        ' press→up p50  10.0  max  20.0',
        ' landed up 6.0  behind 4',
        '  wrote in place 0  copied 1  whole 0  drew none',
      ]) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
    });

    testWidgets('says the way the screen reaches Flutter\'s, and why it was '
        'refused, on a row of its own', (tester) async {
      MeasurementMode.frameStats.value = true;
      addTearDown(() => ScreenTexture.debugPathIs(''));
      FrameStats.debugFeed(<FrameTiming>[_frame(uiMs: 1, rasterMs: 1)]);
      await tester.pumpWidget(
        const MaterialApp(home: MeasurementReadoutHost(child: SizedBox())),
      );

      ScreenTexture.debugPathIs('ahb');
      FrameStats.publish();
      await tester.pump();
      expect(find.text(' path   ahb'), findsOneWidget);

      ScreenTexture.debugPathIs(
        'ahb no — ahb storage no',
        refused: 'ahb storage no',
      );
      FrameStats.publish();
      await tester.pump();
      expect(
        find.text(' path   ahb no — ahb storage no  refused: ahb storage no'),
        findsOneWidget,
      );
    });

    testWidgets('says what the newest frame was drawn as — its texels, the '
        'display\'s scale and the mode —, on the line of its draw', (
      tester,
    ) async {
      MeasurementMode.frameStats.value = true;
      addTearDown(ScreenAsked.debugForget);
      ScreenAsked.debugForget();
      FrameStats.debugFeed(<FrameTiming>[_frame(uiMs: 1, rasterMs: 1)]);
      await tester.pumpWidget(
        const MaterialApp(home: MeasurementReadoutHost(child: SizedBox())),
      );
      FrameStats.publish();
      await tester.pump();
      expect(
        find.textContaining(RegExp(r'^ draw .*\d\s*$')),
        findsOneWidget,
        reason: 'no screen was shown: the line ends on its figures',
      );

      for (final (asked, said) in const [
        (
          (
            columns: 2560,
            rows: 1536,
            texels: 2560 * 1536,
            moved: null,
            scale: 0.9712,
            mode: GpuSampling.blend,
          ),
          '2560x1536  x0.97  blend',
        ),
        (
          (
            columns: 640,
            rows: 1408,
            texels: 640 * 1408,
            moved: null,
            scale: 1.88,
            mode: GpuSampling.nearest,
          ),
          '640x1408  x1.88  nearest',
        ),
        // A pan's: what it held moved, and the band it uncovered drawn —
        // the box round it the target, its walks a part of that.
        (
          (
            columns: 3584,
            rows: 2560,
            texels: 128 * 2560,
            moved: (-128, 0),
            scale: 0.63,
            mode: GpuSampling.blend,
          ),
          '3584x2560 drew 328k moved -128,0  x0.63  blend',
        ),
        (
          (
            columns: 96,
            rows: 64,
            texels: 512,
            moved: (0, 8),
            scale: 1.0,
            mode: GpuSampling.nearest,
          ),
          '96x64 drew 512 moved 0,8  x1.00  nearest',
        ),
      ]) {
        ScreenAsked.shown(asked);
        FrameStats.publish();
        await tester.pump();

        expect(
          find.textContaining(RegExp('^ draw .*  ${RegExp.escape(said)}\$')),
          findsOneWidget,
          reason: said,
        );
      }
    });
  });

  testWidgets('the app mounts the readout host above every route', (
    tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await tester.pump();
    expect(
      find.byType(MeasurementReadoutHost),
      findsOneWidget,
      reason: 'MaterialApp.builder is the only level above the Navigator',
    );
  });
}
