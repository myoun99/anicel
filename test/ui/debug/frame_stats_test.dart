import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/main.dart';
import 'package:anicel/src/ui/debug/frame_stats.dart';
import 'package:anicel/src/ui/debug/frame_stats_readout.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
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
  final rasterStart = buildFinish;
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
      expect(find.textContaining('layer   cache 3'), findsOneWidget);
      expect(find.textContaining('picture cache 0'), findsOneWidget);
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
