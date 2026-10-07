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
            CanvasPlaybackController.wakeAhead -
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

      await tester.pump(CanvasPlaybackController.wakeAhead);
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
  // samples handed over — a stair some 10ms to the step — so it cannot say
  // when its next frame is due, and is asked instead.
  group('on the device\'s clock', () {
    testWidgets('🚨the device is asked off the ticker, and asking costs no '
        'screen frame: while it says the same frame nothing is drawn, and '
        'when it says another the ticker is woken for it', (tester) async {
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
      expect(vsync.ticks, 1);
      final askedByTheTick = asked;

      for (var screen = 0; screen < 6; screen += 1) {
        await tester.pump(screenFrame);
        expect(asksForAFrame(tester), isFalse);
      }
      expect(vsync.ticks, 1, reason: 'six screen frames, none of them asked');
      expect(
        asked - askedByTheTick,
        greaterThan(20),
        reason: 'the device was asked all the while',
      );

      heard = 1;
      await tester.pump(CanvasPlaybackController.deviceAskEvery);
      expect(c.position!.localFrameIndex, 1);
      expect(vsync.ticks, 2);
      expect(asksForAFrame(tester), isFalse, reason: 'asleep again');
      c.stop();
      c.detachTicker();
    });

    testWidgets('a tick it did not ask for leaves one asker, not two', (
      tester,
    ) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);
      addTearDown(c.dispose);
      var asked = 0;
      c.resolveAudioClock = () {
        asked += 1;
        return const AudioClockStatus(globalFrame: 0);
      };

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      // Its provider un-silences it: a route come back into view.
      vsync.last!.muted = false;
      await tester.pump(const Duration(milliseconds: 1));
      expect(vsync.ticks, 2, reason: '⛔premise: it ticked unasked');
      final askedByThen = asked;

      await tester.pump(CanvasPlaybackController.deviceAskEvery * 10);
      expect(asked - askedByThen, 10);
      c.stop();
      c.detachTicker();
    });

    testWidgets('a device that ran out wakes the ticker, though it says the '
        'same frame: a run played once ends', (tester) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);
      addTearDown(c.dispose);
      c.loopMode = PlaybackLoopMode.once;
      var status = const AudioClockStatus(globalFrame: 3);
      c.resolveAudioClock = () => status;

      c.play(scope: PlaybackScope.activeCut, startGlobalFrame: 3);
      await tester.pump();
      expect(c.isActive, isTrue, reason: '⛔premise');

      status = const AudioClockStatus(globalFrame: 3, ended: true);
      await tester.pump(CanvasPlaybackController.deviceAskEvery);
      expect(c.isActive, isFalse);
      c.detachTicker();
    });

    testWidgets('a device that no longer carries the run wakes the ticker: '
        'the wall clock is read from there', (tester) async {
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
      c.stop();
      c.detachTicker();
    });

    testWidgets('a clock that stands asks nobody: a run that waits for its '
        'picture leaves the device alone', (tester) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);
      addTearDown(c.dispose);
      c.waitsOn = (frame, {required placed}) => frame == 1;
      var heard = 0;
      var asked = 0;
      c.resolveAudioClock = () {
        asked += 1;
        return AudioClockStatus(globalFrame: heard);
      };

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      heard = 1;
      await tester.pump(CanvasPlaybackController.deviceAskEvery);
      expect(c.isWaiting, isTrue, reason: '⛔premise');
      final askedByThen = asked;

      await tester.pump(const Duration(seconds: 1));
      expect(asked, askedByThen);
      expect(vsync.ticks, 2);
      c.stop();
      c.detachTicker();
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
