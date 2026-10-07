import 'package:flutter/scheduler.dart';
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
import 'package:anicel/src/ui/playback/sleeping_ticker.dart';

/// 유저 2026-10-08: 「3 화면을 프레임만큼만 다시그리도록」.
///
/// A ticker that runs asks the engine for a frame at every vsync, and the
/// engine draws one whether or not anything changed — measured 2026-10-07:
/// 1452 app frames in 11 seconds of playback. So between frames the run's
/// ticker sleeps, and what is counted here is the ticks: a tick IS a screen
/// frame asked of the engine.
void main() {
  Cut cut(String id, int duration) => Cut(
    id: CutId(id),
    name: id,
    layers: const [],
    duration: duration,
    canvasSize: const CanvasSize(width: 8, height: 8),
  );

  // fps 10: a frame is 100ms. The cut that plays alone has four of them.
  const frameTime = Duration(milliseconds: 100);
  Project project() => Project(
    id: const ProjectId('project'),
    name: 'Project',
    frameRate: const ProjectFrameRate.integer(10),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Track',
        cuts: [cut('cut-a', 4)],
      ),
    ],
    createdAt: DateTime.utc(2026),
  );

  CanvasPlaybackController controller() => CanvasPlaybackController(
    resolveProject: project,
    resolveActiveCutId: () => const CutId('cut-a'),
    resolveActiveTrackId: () => const TrackId('track'),
    resolveFrameRate: () => const ProjectFrameRate.integer(10),
  );

  /// One frame of a 60Hz screen.
  const screenFrame = Duration(microseconds: 16667);

  /// Whether anything has asked the engine for a frame.
  bool asksForAFrame(WidgetTester tester) => tester.binding.hasScheduledFrame;

  group('on the wall clock', () {
    testWidgets('🚨a second of playback is ticked about as often as it has '
        'frames — not as often as the screen has', (tester) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);
      addTearDown(c.dispose);
      final shown = <int>[];
      c.globalFrameIndexListenable.addListener(() {
        final frame = c.globalFrameIndexListenable.value;
        if (frame != null) {
          shown.add(frame);
        }
      });

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      for (var screen = 0; screen < 60; screen += 1) {
        await tester.pump(screenFrame);
      }

      expect(
        shown,
        [0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2],
        reason: '⛔premise: ten frames went by, each on its time',
      );
      expect(
        vsync.ticks,
        inInclusiveRange(shown.length, 2 * shown.length),
        reason: 'a tick for each frame, and at most one before it that '
            'found the frame unchanged — the screen had sixty',
      );
      c.stop();
      c.detachTicker();
    });

    testWidgets('it sleeps until just before the frame is due, is awake '
        'from then, and sleeps again once the frame has changed', (
      tester,
    ) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);
      addTearDown(c.dispose);

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      expect(vsync.ticks, 1);
      expect(asksForAFrame(tester), isFalse, reason: 'asleep');

      await tester.pump(
        frameTime -
            SleepingTicker.wakeAhead -
            const Duration(milliseconds: 1),
      );
      expect(vsync.ticks, 1, reason: 'not yet');
      expect(asksForAFrame(tester), isFalse);

      await tester.pump(const Duration(milliseconds: 1));
      expect(vsync.ticks, 2, reason: 'woken: this tick finds frame 0 still…');
      expect(c.position!.localFrameIndex, 0);
      expect(
        asksForAFrame(tester),
        isTrue,
        reason: '…and it stays awake for the tick that changes it',
      );

      await tester.pump(SleepingTicker.wakeAhead);
      expect(c.position!.localFrameIndex, 1);
      expect(vsync.ticks, 3);
      expect(asksForAFrame(tester), isFalse, reason: 'asleep again');
      c.stop();
      c.detachTicker();
    });

    // `Ticker.muted` is its provider's to write too: a route that comes
    // back into view un-silences every ticker under it.
    testWidgets('a tick it did not ask for finds the frame unchanged and '
        'sleeps again — and still wakes for its frame', (tester) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);
      addTearDown(c.dispose);

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      vsync.last!.muted = false;
      expect(asksForAFrame(tester), isTrue, reason: '⛔premise');

      await tester.pump(const Duration(milliseconds: 10));
      expect(vsync.ticks, 2);
      expect(c.position!.localFrameIndex, 0);
      expect(asksForAFrame(tester), isFalse, reason: 'asleep again');

      await tester.pump(const Duration(milliseconds: 90));
      expect(c.position!.localFrameIndex, 1);
      c.stop();
      c.detachTicker();
    });

    testWidgets('a run that stops is woken by nothing', (tester) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);
      addTearDown(c.dispose);

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      c.stop();
      final ticked = vsync.ticks;

      await tester.pump(const Duration(seconds: 1));
      expect(vsync.ticks, ticked);
      expect(asksForAFrame(tester), isFalse);
      c.detachTicker();
    });
  });

  // ⚠️In the app this is the clock of every run, silent ones too: an empty
  // schedule rides the device like any other. What the device counts is
  // samples handed over — a stair — so it cannot say when its next frame is
  // due.
  group('on the device\'s clock', () {
    // ↩️For a day the device was asked every 3ms off the ticker, and the
    // ticker slept until it said another frame. Asked between vsyncs, a
    // frame changes up to a screen frame later than it does read on one
    // (유저 2026-10-08: 「늦게바뀌는건 좀 많이 신경쓰이는데」).
    testWidgets('🚨the ticker stays awake: the device is read on every '
        'screen frame, and nowhere between them', (tester) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);
      addTearDown(c.dispose);
      var heard = 0;
      var asked = 0;
      c.resolveAudioClock = () {
        asked += 1;
        return AudioClockStatus(globalFrame: heard);
      };

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      for (var screen = 0; screen < 6; screen += 1) {
        await tester.pump(screenFrame);
        expect(asksForAFrame(tester), isTrue, reason: 'awake');
      }
      expect(vsync.ticks, 7, reason: 'a tick a screen frame');
      expect(asked, vsync.ticks, reason: 'read on the ticks, and only there');

      // The frame it says is shown on the very next screen frame.
      heard = 1;
      await tester.pump(screenFrame);
      expect(c.position!.localFrameIndex, 1);
      c.stop();
      c.detachTicker();
    });

    testWidgets('a device that no longer carries the run: the wall clock is '
        'read from there, and that clock sleeps', (tester) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);
      addTearDown(c.dispose);
      AudioClockStatus? status = const AudioClockStatus(globalFrame: 0);
      c.resolveAudioClock = () => status;

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      status = null;
      await tester.pump(const Duration(milliseconds: 150));
      expect(c.position!.localFrameIndex, 1);
      expect(asksForAFrame(tester), isFalse, reason: 'asleep');
      c.stop();
      c.detachTicker();
    });
  });

  // 🚨Two ways a clock ends that once disposed the ticker by hand and left
  // what wakes it behind. ⚠️Each test ENDS on the act: a waker left behind
  // is a timer still pending when the test ends, and a ticker left behind
  // is one still active — the test framework fails a test for either. Time
  // pumped after the act would let the waker fire and hide it.
  group('what wakes a ticker ends with it', () {
    testWidgets('a view that goes away takes the ticker and its waker', (
      tester,
    ) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);
      addTearDown(c.dispose);

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      expect(asksForAFrame(tester), isFalse, reason: '⛔premise: asleep');

      c.detachTicker();
    });

    testWidgets('a controller that is disposed leaves neither', (
      tester,
    ) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      expect(asksForAFrame(tester), isFalse, reason: '⛔premise: asleep');

      c.dispose();
    });
  });
}

/// A vsync that counts the ticks its tickers were given.
class _CountingVSync implements TickerProvider {
  int ticks = 0;
  Ticker? last;

  @override
  Ticker createTicker(TickerCallback onTick) => last = Ticker((elapsed) {
    ticks += 1;
    onTick(elapsed);
  });
}
