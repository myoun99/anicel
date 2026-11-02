import 'dart:developer' show Timeline;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_display_timing.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';

import '../helpers/native_engine_path.dart';

/// The engine's word on the display (`qa_display_vblank`,
/// `qa_display_window_screens`, `qa_display_wait_until_us`,
/// `qa_display_compose_every_vblank`): where the real vblanks are, on the
/// frame clock, a wait that ends on its microsecond — what a clock's frame
/// is handed to the GPU by (`PresentPacing`) — and the compositor kept
/// composing while it runs.
void main() {
  group('🚨the grid of a window (유저 2026-11-02: 「주사율 다른 모니터 둘에 '
      '걸쳐있으면 높은쪽을 기반으로 하도록」)', () {
    const composed = (vblankMicros: 1000, periodMicros: 6948.6);
    const fast = (vblankMicros: 2000, periodMicros: 6948.5);
    const sixty = (vblankMicros: 3000, periodMicros: 16666.6);
    const slow = (vblankMicros: 4000, periodMicros: 16949.1);

    test('on no screen anybody named, the compositor\'s clock', () {
      expect(gridOfTheWindow(composed: composed, screens: const []), (
        vblankMicros: 1000,
        periodMicros: 6948.6,
        composedVblankMicros: 1000,
        composedEveryMicros: 6948.6,
      ));
    });

    test('on a slower screen, that screen, under the compositor\'s clock', () {
      expect(gridOfTheWindow(composed: composed, screens: const [slow]), (
        vblankMicros: 4000,
        periodMicros: 16949.1,
        composedVblankMicros: 1000,
        composedEveryMicros: 6948.6,
      ));
    });

    test('🚨across two slower screens, the faster of them, in either order',
        () {
      const sixtyGrid = (
        vblankMicros: 3000,
        periodMicros: 16666.6,
        composedVblankMicros: 1000,
        composedEveryMicros: 6948.6,
      );
      expect(
        gridOfTheWindow(composed: composed, screens: const [slow, sixty]),
        sixtyGrid,
      );
      expect(
        gridOfTheWindow(composed: composed, screens: const [sixty, slow]),
        sixtyGrid,
      );
    });

    test('🚨across the compositor\'s screen and a slower one, the '
        'compositor\'s clock itself, not its screen\'s reading of it', () {
      const clock = (
        vblankMicros: 1000,
        periodMicros: 6948.6,
        composedVblankMicros: 1000,
        composedEveryMicros: 6948.6,
      );
      expect(
        gridOfTheWindow(composed: composed, screens: const [sixty, fast]),
        clock,
      );
      expect(
        gridOfTheWindow(composed: composed, screens: const [fast, sixty]),
        clock,
      );
    });

    test('⛔a screen faster than the compositor\'s clock is not taken: '
        'nothing was measured there', () {
      const faster = (vblankMicros: 5000, periodMicros: 4166.6);
      expect(
        gridOfTheWindow(composed: composed, screens: const [faster]).vblankMicros,
        1000,
      );
    });

    test('⛔a screen a hundredth slower than the clock is on it — and one '
        'past that is not', () {
      const just = (vblankMicros: 5000, periodMicros: 7018.0);
      const past = (vblankMicros: 5000, periodMicros: 7020.0);
      expect(
        gridOfTheWindow(composed: composed, screens: const [just]).vblankMicros,
        1000,
      );
      expect(
        gridOfTheWindow(composed: composed, screens: const [past]).vblankMicros,
        5000,
      );
    });
  });

  final dllPath = nativeEngineLibraryPathOrNull();

  setUp(() {
    QaDisplayTiming.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
  });

  tearDown(() {
    QaDisplayTiming.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  test('only Windows has a display that says where its vblanks are — and '
      'says it on the frame clock', () {
    if (dllPath == null) {
      markTestSkipped('qa_engine not built');
      return;
    }
    final timing = QaDisplayTiming.instance;
    if (!Platform.isWindows) {
      expect(timing, isNull, reason: 'its engine vsync is the display\'s');
      return;
    }
    if (timing == null) {
      markTestSkipped('the compositor did not answer: no display here');
      return;
    }
    final grid = timing.vblankGrid()!;
    expect(
      grid.periodMicros,
      inInclusiveRange(1000, 100000),
      reason: 'a refresh between 10 and 1000 times a second',
    );
    expect(
      grid.composedEveryMicros,
      grid.periodMicros,
      reason: 'a test has no window: it stands on the compositor\'s clock',
    );
    expect(grid.composedVblankMicros, grid.vblankMicros);
    expect(
      (grid.vblankMicros - Timeline.now).abs(),
      lessThan(Duration.microsecondsPerSecond),
      reason: 'a vblank of now, on the clock the frame times are on',
    );
  });

  test('with no app window to compose on — a test has none — the compositor '
      'is not kept composing, and letting it rest says so too', () {
    final timing = dllPath == null ? null : QaDisplayTiming.instance;
    if (timing == null) {
      markTestSkipped('no display timing here');
      return;
    }
    expect(timing.composeEveryVblank(on: true), isFalse);
    expect(timing.composeEveryVblank(on: false), isFalse);
  });

  test('a wait ends on its microsecond — never before it', () {
    final timing = dllPath == null ? null : QaDisplayTiming.instance;
    if (timing == null) {
      markTestSkipped('no display timing here');
      return;
    }
    for (var wait = 0; wait < 20; wait += 1) {
      final deadline = Timeline.now + 1500 + wait * 100;
      timing.waitUntil(deadline);
      expect(Timeline.now, greaterThanOrEqualTo(deadline));
    }
  });
}
