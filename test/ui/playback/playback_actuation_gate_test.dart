import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/playback/playback_actuation_gate.dart';

/// 🚨★★★ T28-c — 「재생 중 첫 작동은 정지이고, **정지일 뿐이다**」.
///
/// Both halves are load-bearing and each has its own test here: the
/// actuation STOPS, and the actuation does NOT also do its own job. A gate
/// that only did the first would be "stop and draw a stroke anyway", which
/// is the behaviour the user was describing when they said 「입력 일 안함」.
void main() {
  late CanvasPlaybackController controller;
  late int taps;


  CanvasPlaybackController build() => CanvasPlaybackController(
    resolveProject: () => Project(
      id: const ProjectId('p'),
      name: 'P',
      frameRate: const ProjectFrameRate.integer(10),
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'T',
          cuts: [
            Cut(
              id: const CutId('c'),
              name: 'c',
              layers: const [],
              duration: 8,
              canvasSize: const CanvasSize(width: 8, height: 8),
            ),
          ],
        ),
      ],
    ),
    resolveActiveCutId: () => const CutId('c'),
    resolveActiveTrackId: () => const TrackId('t'),
    resolveFrameRate: () => const ProjectFrameRate.integer(10),
  );

  Future<void> pumpGate(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackActuationGate(
            controller: controller,
            // Focused on purpose: it puts the primary focus BELOW the gate,
            // which is the arrangement that proves the keyboard half cannot
            // work through the widget tree.
            child: Focus(
              autofocus: true,
              child: GestureDetector(
                onTap: () => taps += 1,
                child: const SizedBox.expand(
                  key: ValueKey<String>('work-surface'),
                  child: ColoredBox(color: Color(0xFF000000)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  setUp(() {
    controller = build();
    taps = 0;

  });

  tearDown(() => controller.dispose());

  testWidgets('stopped, the work surface does its own job', (tester) async {
    await pumpGate(tester);

    await tester.tap(find.byKey(const ValueKey<String>('work-surface')));
    await tester.pump();

    expect(taps, 1, reason: 'the gate is inert while nothing is playing');
    expect(controller.isPlaying, isFalse);
  });

  testWidgets('a pointer down while playing STOPS, and the surface never '
      'sees it', (tester) async {
    await pumpGate(tester);
    controller.attachTicker(const TestVSync());
    controller.play(scope: PlaybackScope.activeCut);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('work-surface')));
    await tester.pump();

    expect(controller.isPlaying, isFalse);
    expect(taps, 0, reason: '「뭘 하든 정지만. 입력 일 안함」');

    controller.detachTicker();
  });

  /// ⚠️This asserts the STOP only, not that the key vanished from the focus
  /// tree — 실측: Flutter dispatches the key message to focus even when a
  /// [HardwareKeyboard] handler claims it, so no widget can make a key
  /// disappear from below. The CONSUMING half of the law is enforced where
  /// bound actuations actually arrive, in the editor's action funnel
  /// (`_consumedByPlayback`), and `home_page`'s own tests cover it.
  testWidgets('a key down while playing STOPS the transport', (tester) async {
    await pumpGate(tester);
    controller.attachTicker(const TestVSync());
    controller.play(scope: PlaybackScope.activeCut);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();

    expect(controller.isPlaying, isFalse);

    controller.detachTicker();
  });

  testWidgets('⛔hover and plain movement are NOT actuations — '
      '「커서만 움직여도 재생이 죽으면 데스크톱에서 못 쓴다」', (tester) async {
    await pumpGate(tester);
    controller.attachTicker(const TestVSync());
    controller.play(scope: PlaybackScope.activeCut);
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.byType(SizedBox)));
    await tester.pump();

    expect(
      controller.isPlaying,
      isTrue,
      reason: 'the cursor crossed the whole editor and playback survived',
    );

    controller.stop();
    controller.detachTicker();
  });

  group('D13: the navigation hole', () {
    final regionKey = GlobalKey(debugLabel: 'test-navigation-region');
    late int regionTaps;

    Future<void> pumpGateWithRegion(WidgetTester tester) async {
      regionTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaybackActuationGate(
              controller: controller,
              navigationRegionKey: regionKey,
              child: Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => taps += 1,
                      child: const SizedBox.expand(
                        key: ValueKey<String>('work-surface'),
                        child: ColoredBox(color: Color(0xFF000000)),
                      ),
                    ),
                  ),
                  SizedBox(
                    key: regionKey,
                    height: 200,
                    width: double.infinity,
                    child: GestureDetector(
                      key: const ValueKey<String>('nav-region'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => regionTaps += 1,
                      child: const ColoredBox(color: Color(0xFF222222)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a press INSIDE the region NAVIGATES — playback keeps '
        'playing and the region does its own job', (tester) async {
      await pumpGateWithRegion(tester);
      controller.attachTicker(const TestVSync());
      controller.play(scope: PlaybackScope.activeCut);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey<String>('nav-region')));
      await tester.pump();

      expect(
        controller.isPlaying,
        isTrue,
        reason: 'D13: pan/zoom keep working during playback — a canvas '
            'press is navigation, not an actuation to stop on',
      );
      expect(regionTaps, 1, reason: 'the press reached the canvas');

      controller.stop();
      controller.detachTicker();
    });

    testWidgets('a press OUTSIDE the region keeps the whole T28-c law: '
        'stop, and the surface never sees it', (tester) async {
      await pumpGateWithRegion(tester);
      controller.attachTicker(const TestVSync());
      controller.play(scope: PlaybackScope.activeCut);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey<String>('work-surface')));
      await tester.pump();

      expect(controller.isPlaying, isFalse);
      expect(taps, 0, reason: '「뭘 하든 정지만. 입력 일 안함」 — unchanged '
          'everywhere the canvas is not');

      controller.detachTicker();
    });

    testWidgets('an opaque surface OVER the region keeps the stop law — '
        'the hit PATH decides, never the rectangle (the floating timeline '
        'overlaps the canvas panel\'s rect)', (tester) async {
      regionTaps = 0;
      var overlayTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaybackActuationGate(
              controller: controller,
              navigationRegionKey: regionKey,
              child: Stack(
                children: [
                  SizedBox.expand(
                    key: regionKey,
                    child: GestureDetector(
                      key: const ValueKey<String>('nav-region'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => regionTaps += 1,
                      child: const ColoredBox(color: Color(0xFF222222)),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 200,
                    child: GestureDetector(
                      key: const ValueKey<String>('floating-overlay'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => overlayTaps += 1,
                      child: const ColoredBox(color: Color(0xFF444444)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      controller.attachTicker(const TestVSync());
      controller.play(scope: PlaybackScope.activeCut);
      await tester.pump();

      // The overlay sits INSIDE the region's rectangle but on top of it:
      // a press there is the overlay's, so the gate must stop + consume.
      await tester.tap(
        find.byKey(const ValueKey<String>('floating-overlay')),
      );
      await tester.pump();

      expect(
        controller.isPlaying,
        isFalse,
        reason: 'a surface floating over the canvas keeps T28-c whole',
      );
      expect(overlayTaps, 0, reason: 'stopped AND consumed');
      expect(regionTaps, 0);

      controller.detachTicker();
    });

    testWidgets('idle, the region is nothing special — both surfaces do '
        'their jobs', (tester) async {
      await pumpGateWithRegion(tester);

      await tester.tap(find.byKey(const ValueKey<String>('nav-region')));
      await tester.tap(find.byKey(const ValueKey<String>('work-surface')));
      await tester.pump();

      expect(regionTaps, 1);
      expect(taps, 1);
      expect(controller.isPlaying, isFalse);
    });
  });

  testWidgets('the SECOND actuation does its job — the gate is only in the '
      'way while playing', (tester) async {
    await pumpGate(tester);
    controller.attachTicker(const TestVSync());
    controller.play(scope: PlaybackScope.activeCut);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('work-surface')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('work-surface')));
    await tester.pump();

    expect(taps, 1, reason: 'the first was consumed, the second was not');

    controller.detachTicker();
  });
}
