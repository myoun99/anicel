import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuPlaceTook, GpuSampling;

import 'package:anicel/src/native/screen_texture.dart';
import 'package:anicel/src/ui/debug/engine_stages.dart';
import 'package:anicel/src/ui/debug/frame_stats.dart';
import 'package:anicel/src/ui/debug/frame_stats_readout.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/debug/screen_asked.dart';

/// The engine's stages (Settings ▸ Debug ▸ Engine Stages): what the frames
/// kept say, place by place, and the slowest of them whole — a stall of
/// one frame on a tablet out of reach is read off a photograph of these
/// lines (card the-galaxy-tab-canvas-went-slow-on-build-1095, 유저
/// 2026-11-22). What the engine itself tells is pinned where it is told
/// (rust/src/took.rs) and read
/// (test/native/a_timed_engine_tells_what_each_place_took_test.dart).
void main() {
  GpuPlaceTook gpu(String place, int micros, {int times = 1, int groups = 0}) =>
      (
        gpu: true,
        place: place,
        times: times,
        micros: micros,
        longest: micros,
        groups: groups,
      );
  GpuPlaceTook cpu(String place, int micros, {int times = 1}) => (
    gpu: false,
    place: place,
    times: times,
    micros: micros,
    longest: micros,
    groups: 0,
  );
  StagedFrame frame(int finish, List<GpuPlaceTook> took, {ScreenAsk? asked}) =>
      (up: (draw: 1000, finish: finish, show: 500), asked: asked, took: took);

  const show = r'src\kernels\composite\screen.rs:412';
  const copy = 'src/platform/android.rs:237';
  const pile = 'packages/gpu_engine/rust/src/kernels/stroke/pile.rs:88';
  const present = 'src/device.rs:1040';

  setUp(() {
    MeasurementMode.reset();
    EngineStages.install();
    EngineStages.debugForget();
    ScreenAsked.debugForget();
  });
  tearDown(() {
    MeasurementMode.reset();
    EngineStages.debugForget();
    ScreenAsked.debugForget();
    FrameStats.reset();
  });

  test('a place is named by its file under the engine\'s sources, without '
      'what every one shares', () {
    expect(EngineStages.shortPlace(show), 'composite/screen:412');
    expect(EngineStages.shortPlace(copy), 'platform/android:237');
    expect(EngineStages.shortPlace(pile), 'stroke/pile:88');
    expect(EngineStages.shortPlace(present), 'device:1040');
    expect(EngineStages.shortPlace('elsewhere.rs:3'), 'elsewhere:3');
  });

  test('the frames kept are summed place by place, the one that took most '
      'first, each with the most it took in one frame', () {
    final summary = EngineStages.summarize([
      frame(20000, [gpu(show, 12000, groups: 9000), gpu(copy, 5000)]),
      frame(30000, [
        gpu(show, 16000, groups: 9000),
        gpu(copy, 4000),
        cpu(present, 7000),
      ]),
      frame(10000, [gpu(copy, 6000), cpu(present, 2000, times: 2)]),
    ]);

    expect(summary.frames, 3);
    expect(summary.wholeMicros, (20000 + 30000 + 10000) + 3 * 1500);
    expect(
      [
        for (final place in summary.places)
          (place.gpu, place.place, place.micros, place.mostInAFrame),
      ],
      [
        (true, 'composite/screen:412', 28000, 16000),
        (true, 'platform/android:237', 15000, 6000),
        (false, 'device:1040', 9000, 7000),
      ],
    );
    expect(summary.places.first.groups, 18000);
    expect(summary.places.last.times, 3);
    expect(summary.gpuMicros, 43000);
    expect(summary.cpuMicros, 9000);
  });

  test('one place told as the GPU\'s and as the engine thread\'s is two '
      'places, each its own', () {
    // One line can hand a body to the engine's thread and make a submit
    // in it: what the GPU took there is not what the thread did.
    final summary = EngineStages.summarize([
      frame(10000, [gpu(present, 3000), cpu(present, 2000)]),
    ]);

    expect(
      [
        for (final place in summary.places)
          (place.gpu, place.place, place.micros),
      ],
      [(true, 'device:1040', 3000), (false, 'device:1040', 2000)],
    );
  });

  test('a place told twice of one frame is that frame\'s once: its most in '
      'a frame is their sum', () {
    final summary = EngineStages.summarize([
      frame(10000, [gpu(show, 3000), gpu(show, 4000)]),
      frame(10000, [gpu(show, 5000)]),
    ]);

    expect(summary.places.single.micros, 12000);
    expect(summary.places.single.mostInAFrame, 7000);
  });

  test('the slowest frame is the one longest from its draw to being up, '
      'told by its own places', () {
    const stall = (
      columns: 865,
      rows: 864,
      texels: 865 * 864,
      moved: null,
      scale: 1.35,
      mode: GpuSampling.nearest,
    );
    final summary = EngineStages.summarize([
      frame(17000, [gpu(show, 9000), gpu(copy, 5000)]),
      frame(125000, [
        gpu(pile, 90000, times: 25),
        gpu(copy, 5000),
        cpu(present, 20000),
      ], asked: stall),
      frame(18000, [gpu(show, 99000)]),
    ]);

    expect(summary.slowest.up.finish, 125000);
    expect(summary.slowest.asked, stall);
    expect(
      [for (final place in summary.slowestPlaces) (place.place, place.micros)],
      [('stroke/pile:88', 90000), ('device:1040', 20000), (
        'platform/android:237',
        5000,
      )],
      reason: 'its own, and not the frames\' in all — where `composite/'
          'screen` took the most',
    );
  });

  test('the lines say a frame on the average, then the places, then the '
      'slowest frame with what it was drawn as', () {
    const stall = (
      columns: 865,
      rows: 864,
      texels: 865 * 864,
      moved: null,
      scale: 1.35,
      mode: GpuSampling.nearest,
    );
    final lines = EngineStages.lines(
      EngineStages.summarize([
        frame(20500, [gpu(show, 12000, groups: 9000), gpu(copy, 4000)]),
        frame(124500, [
          gpu(pile, 90000, times: 25, groups: 400),
          gpu(copy, 6000),
          cpu(present, 20000),
        ], asked: stall),
      ]),
    );

    // The columns' padding is the readout's own: the words and the
    // figures are what a photograph is read for.
    expect([for (final line in lines) line.replaceAll(RegExp(' +'), ' ')], [
      'STAGES 2f a frame 74.00 gpu 56.00 cpu 10.00',
      ' gpu stroke/pile:88 45.00 max 90.00 12.5x 0.2k',
      ' cpu device:1040 10.00 max 20.00 0.5x',
      ' gpu composite/screen:412 6.00 max 12.00 0.5x 4.5k',
      ' gpu platform/android:237 5.00 max 6.00 1.0x',
      'SLOWEST 126.00 draw 1.00 finish 124.50 show 0.50 865x864 x1.35 '
          'nearest',
      ' gpu 96.00 cpu 20.00',
      ' gpu stroke/pile:88 90.00 25.0x 0.4k',
      ' cpu device:1040 20.00 1.0x',
      ' gpu platform/android:237 6.00 1.0x',
    ]);
  });

  test('no more places are named than the readout has room for', () {
    final many = [
      for (var line = 1; line <= 20; line++) gpu('src/a.rs:$line', line * 100),
    ];
    final lines = EngineStages.lines(
      EngineStages.summarize([frame(10000, many)]),
    );

    expect(
      lines.length,
      1 + EngineStages.placesShown + 2 + EngineStages.slowestPlacesShown,
    );
    expect(lines[1], contains('a:20 '), reason: 'the one that took most');
  });

  test('with no frame up yet the lines say so', () {
    expect(EngineStages.lines(null), ['STAGES  timed, no frame yet']);
    expect(EngineStages.summary, isNull);
  });

  group('the switch', () {
    tearDown(() => ScreenTexture.tookAsItWentUp = null);

    test('is off in an ordinary build, and nobody is told of a frame', () {
      expect(MeasurementMode.startWithEngineStages, isFalse);
      expect(MeasurementMode.engineStages.value, isFalse);
      expect(ScreenTexture.tookAsItWentUp, isNull);
    });

    test('on, the frames that go up are kept with what was asked of each; '
        'off again, none is kept and nobody is told', () {
      MeasurementMode.engineStages.value = true;
      final told = ScreenTexture.tookAsItWentUp;
      expect(told, isNotNull);

      const asked = (
        columns: 128,
        rows: 128,
        texels: 128 * 128,
        moved: null,
        scale: 1.0,
        mode: GpuSampling.nearest,
      );
      ScreenAsked.shown(asked);
      told!((draw: 100, finish: 9000, show: 50), [gpu(show, 4000)]);

      final summary = EngineStages.summary!;
      expect(summary.frames, 1);
      expect(summary.slowest.asked, asked);
      expect(summary.places.single.micros, 4000);

      MeasurementMode.engineStages.value = false;
      expect(ScreenTexture.tookAsItWentUp, isNull);
      expect(EngineStages.summary, isNull);
    });

    test('no more frames are kept than the newest', () {
      MeasurementMode.engineStages.value = true;
      for (var at = 0; at < EngineStages.framesKept + 5; at++) {
        EngineStages.wentUp((draw: 0, finish: at, show: 0), [gpu(show, at)]);
      }

      final summary = EngineStages.summary!;
      expect(summary.frames, EngineStages.framesKept);
      expect(summary.slowest.up.finish, EngineStages.framesKept + 4);
      // The five oldest — 0, 1, 2, 3, 4 — are gone from the sum.
      const all = EngineStages.framesKept + 5;
      expect(summary.places.single.micros, all * (all - 1) ~/ 2 - 10);
    });
  });

  testWidgets('the statistics show the stages under their own lines while '
      'the switch is on, and not while it is off', (tester) async {
    addTearDown(() => ScreenTexture.tookAsItWentUp = null);
    MeasurementMode.frameStats.value = true;
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: FrameStatsReadout(),
      ),
    );
    Finder line(String text) => find.textContaining(text);

    expect(line('STAGES'), findsNothing);

    MeasurementMode.engineStages.value = true;
    EngineStages.wentUp((draw: 100, finish: 9000, show: 50), [gpu(show, 4000)]);
    // The readout is built again as the statistics publish, and with
    // their window.
    FrameStats.debugFeed([
      FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 1000,
        rasterStart: 1000,
        rasterFinish: 2000,
        rasterFinishWallTime: 2000,
      ),
    ]);
    FrameStats.publish();
    await tester.pump();

    expect(line('STAGES  1f'), findsOneWidget);
    expect(line('composite/screen:412'), findsNWidgets(2));
    expect(line('SLOWEST'), findsOneWidget);

    MeasurementMode.engineStages.value = false;
    FrameStats.publish();
    await tester.pump();
    expect(line('STAGES'), findsNothing);
  });
}
