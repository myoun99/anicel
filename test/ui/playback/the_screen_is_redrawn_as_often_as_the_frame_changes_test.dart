import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
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
import 'package:anicel/src/ui/playback/looking_ticker.dart';

import '../../helpers/look_test_binding.dart';

/// 유저 2026-10-08: 「3 화면을 프레임만큼만 다시그리도록」 — and, of the
/// clock the frames follow: 「소리 싱크나 영상이나 뭐 그런거 정확하기만하면되.
/// 그게 제일 최우선.」
///
/// A run's clock is looked at on EVERY screen frame — that is what changes
/// its frame on the screen frame it is due on — and the screen is drawn as
/// often as the frame changes. Two things are counted here: the ticks (a
/// tick is a screen frame the clock was looked at on), and the frames that
/// were DRAWN ([LookTestBinding.drawnFrames]).
///
/// ↩️For a day the ticks themselves were what was kept few: the ticker
/// slept between frames and a timer woke it, and the frame changed as late
/// as the timer came (`LookOnlyFrames` has the measurements).
void main() {
  final binding = LookTestBinding.ensureInitialized();

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

  /// Shows the run's frame the way its view does: rebuilt when it changes,
  /// and by nothing else.
  Future<void> showFrameOf(WidgetTester tester, CanvasPlaybackController c) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder<int?>(
            valueListenable: c.globalFrameIndexListenable,
            builder: (context, frame, child) => Text('frame $frame'),
          ),
        ),
      );

  group('on the wall clock', () {
    testWidgets('🚨a second of playback is looked at as often as the screen '
        'has frames and DRAWN as often as it has its own — each of them on '
        'the screen frame it is due on', (tester) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);
      addTearDown(c.dispose);
      await showFrameOf(tester, c);

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      expect(find.text('frame 0'), findsOneWidget);
      final drawn = binding.drawnFrames;
      final ticked = vsync.ticks;

      var changes = 0;
      var showing = 0;
      for (var screen = 1; screen <= 60; screen += 1) {
        await tester.pump(screenFrame);
        // Due once the screen frames so far add up to it.
        final due =
            (screenFrame * screen).inMicroseconds ~/
            frameTime.inMicroseconds %
            4;
        expect(
          find.text('frame $due'),
          findsOneWidget,
          reason: 'screen frame $screen: changed on the screen frame it is '
              'due on, and drawn in it',
        );
        if (due != showing) {
          changes += 1;
          showing = due;
        }
      }

      expect(changes, 10, reason: '⛔premise: ten frames went by');
      expect(
        vsync.ticks - ticked,
        60,
        reason: 'the clock is looked at on every screen frame',
      );
      expect(
        binding.drawnFrames - drawn,
        changes,
        reason: 'and the screen is drawn when the frame changes — it had '
            'sixty frames in that second',
      );
      c.stop();
      c.detachTicker();
    });

    testWidgets('a run that stops looks no more: no frame is asked for', (
      tester,
    ) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);
      addTearDown(c.dispose);
      await showFrameOf(tester, c);

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      c.stop();
      // The frame the stopping itself asked for: the view shows no frame.
      await tester.pump(screenFrame);
      final ticked = vsync.ticks;
      expect(binding.hasScheduledFrame, isFalse);

      await tester.pump(const Duration(seconds: 1));
      expect(vsync.ticks, ticked);
      expect(binding.hasScheduledFrame, isFalse);
      c.detachTicker();
    });
  });

  // ⚠️In the app this is the clock of every run, silent ones too: an empty
  // schedule rides the device like any other.
  group('on the device\'s clock', () {
    // ↩️For a day it was asked every 3ms off the ticker instead, and a
    // frame asked for between vsyncs changes up to a screen frame later
    // than one read on a vsync (유저 2026-10-08: 「늦게바뀌는건 좀 많이
    // 신경쓰이는데」).
    testWidgets('🚨the device is read on every screen frame, and nowhere '
        'between them: a reading that says the same frame draws nothing, '
        'and the one that says the next is drawn on that screen frame', (
      tester,
    ) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);
      addTearDown(c.dispose);
      var heard = 0;
      var asked = 0;
      c.resolveAudioClock = () {
        asked += 1;
        return ClockReading(globalFrame: heard);
      };
      await showFrameOf(tester, c);

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      final drawn = binding.drawnFrames;
      for (var screen = 0; screen < 6; screen += 1) {
        await tester.pump(screenFrame);
      }
      expect(vsync.ticks, 7, reason: 'a tick a screen frame');
      expect(asked, vsync.ticks, reason: 'read on the ticks, and only there');
      expect(
        binding.drawnFrames,
        drawn,
        reason: 'the same frame six times over: nothing to draw',
      );

      heard = 1;
      await tester.pump(screenFrame);
      expect(find.text('frame 1'), findsOneWidget);
      expect(binding.drawnFrames, drawn + 1);
      c.stop();
      c.detachTicker();
    });

    testWidgets('a device that no longer carries the run: the wall clock is '
        'read from there', (tester) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);
      addTearDown(c.dispose);
      ClockReading? status = const ClockReading(globalFrame: 0);
      c.resolveAudioClock = () => status;

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      status = null;
      await tester.pump(const Duration(milliseconds: 150));
      expect(c.position!.localFrameIndex, 1);
      c.stop();
      c.detachTicker();
    });
  });

  group('the ticker that looks', () {
    testWidgets('🚨its first tick is asked for only to look, like every one '
        'after it', (tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(screenFrame);
      final vsync = _CountingVSync();
      final ticker = LookingTicker((_) {});
      final drawn = binding.drawnFrames;

      ticker.start(vsync);
      for (var screen = 0; screen < 3; screen += 1) {
        await tester.pump(screenFrame);
      }

      expect(vsync.ticks, 3);
      expect(binding.drawnFrames, drawn);
      ticker.stop();
    });

    testWidgets('a tick that ends the clock asks for no frame after it', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(screenFrame);
      final vsync = _CountingVSync();
      late final LookingTicker ticker;
      ticker = LookingTicker((_) => ticker.stop());

      ticker.start(vsync);
      await tester.pump(screenFrame);

      expect(vsync.ticks, 1);
      expect(ticker.isRunning, isFalse);
      expect(binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a tick that starts the clock afresh: the new ticker counts '
        'from the screen frame it was started in, ticks once a screen '
        'frame, and looks', (tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(screenFrame);
      final vsync = _CountingVSync();
      final elapsed = <Duration>[];
      late final LookingTicker ticker;
      ticker = LookingTicker((sinceItStarted) {
        elapsed.add(sinceItStarted);
        if (elapsed.length == 2) {
          ticker.start(vsync);
        }
      });
      final drawn = binding.drawnFrames;

      ticker.start(vsync);
      for (var screen = 0; screen < 4; screen += 1) {
        await tester.pump(screenFrame);
      }

      expect(elapsed, [
        Duration.zero,
        screenFrame,
        // A ticker started inside a frame counts from that frame.
        screenFrame,
        screenFrame * 2,
      ]);
      expect(vsync.ticks, 4);
      expect(binding.drawnFrames, drawn);
      ticker.stop();
    });
  });

  // The ticker is the framework's own, made by the view's own provider —
  // and `Ticker.muted` is that provider's to write: a route that is not
  // shown silences every ticker under it.
  group('the clock\'s ticker is its view\'s', () {
    testWidgets('silenced by its provider it does not tick; shown again it '
        'looks on — and draws nothing for looking', (tester) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);
      addTearDown(c.dispose);
      await showFrameOf(tester, c);

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      vsync.last!.muted = true;
      final ticked = vsync.ticks;
      await tester.pump(screenFrame);
      await tester.pump(screenFrame);
      expect(vsync.ticks, ticked);

      vsync.last!.muted = false;
      // The frame its provider asked for — anybody's, for all the scheduler
      // knows: drawn.
      await tester.pump(screenFrame);
      expect(vsync.ticks, ticked + 1);
      final drawn = binding.drawnFrames;

      await tester.pump(screenFrame);
      expect(vsync.ticks, ticked + 2);
      expect(binding.drawnFrames, drawn, reason: 'looking again');
      c.stop();
      c.detachTicker();
    });

    // ⚠️Each of these two ENDS on the act: a ticker left behind is one
    // still active when the test ends, and the test framework fails a test
    // for that.
    testWidgets('a view that goes away takes the ticker', (tester) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);
      addTearDown(c.dispose);

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      expect(binding.hasScheduledFrame, isTrue, reason: '⛔premise: looking');

      c.detachTicker();
    });

    testWidgets('a controller that is disposed leaves none', (tester) async {
      final vsync = _CountingVSync();
      final c = controller()..attachTicker(vsync);

      c.play(scope: PlaybackScope.activeCut);
      await tester.pump();
      expect(binding.hasScheduledFrame, isTrue, reason: '⛔premise: looking');

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
