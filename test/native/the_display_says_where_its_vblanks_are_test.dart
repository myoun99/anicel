import 'dart:developer' show Timeline;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_display_timing.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';

import '../helpers/native_engine_path.dart';

/// The engine's word on the display (`qa_display_vblank`,
/// `qa_display_wait_until_us`): where the real vblanks are, on the frame
/// clock, and a wait that ends on its microsecond — what a clock's frame
/// is handed to the GPU by (`PresentPacing`).
void main() {
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
      (grid.vblankMicros - Timeline.now).abs(),
      lessThan(Duration.microsecondsPerSecond),
      reason: 'a vblank of now, on the clock the frame times are on',
    );
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
