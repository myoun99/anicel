
import 'dart:async';

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
import 'package:anicel/src/native/qa_display_timing.dart';
import 'package:anicel/src/services/playback/present_slot.dart';
import 'package:anicel/src/ui/look_only_frames.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/playback/looking_ticker.dart';
import 'package:anicel/src/ui/present_pacing.dart';

/// A display that says where its vblanks are, and remembers what it was
/// asked to wait for.
class _Display implements DisplayTiming {
  static const int vblank = 3000000;
  static const double period = 6948.6;

  /// How far past its vsync a frame has got when its look asks the time,
  /// and when its seam does — the first read in a frame, and the rest.
  int lookedAfter = 900;
  int seamAfter = 2900;

  final List<int> waits = [];

  int get _vsyncStart =>
      SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds -
      period.round();

  int get lookNow => _vsyncStart + lookedAfter;
  int get seamNow => _vsyncStart + seamAfter;

  Duration? _readIn;
  int _reads = 0;

  /// Now, between frames: when a test says it.
  int? between;

  @override
  int get nowMicros {
    final between = this.between;
    if (between != null) {
      return between;
    }
    final frame = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    if (_readIn != frame) {
      _readIn = frame;
      _reads = 0;
    }
    _reads += 1;
    return _reads == 1 ? lookNow : seamNow;
  }

  @override
  ({int vblankMicros, double periodMicros})? vblankGrid() =>
      (vblankMicros: vblank, periodMicros: period);

  @override
  void waitUntil(int micros) => waits.add(micros);

  /// What it was told of composing on every vblank, in order.
  final List<bool> composing = [];

  @override
  bool composeEveryVblank({required bool on}) {
    composing.add(on);
    return on;
  }
}

/// The playback of a project of one cut, ten frames long, at 24fps.
CanvasPlaybackController _playbackOfOneCut() {
  final project = Project(
    id: const ProjectId('paced'),
    name: 'Paced',
    createdAt: DateTime.utc(2026, 10, 11),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('cut'),
            name: 'A',
            duration: 10,
            canvasSize: const CanvasSize(width: 64, height: 36),
            layers: const [],
          ),
        ],
      ),
    ],
  );
  return CanvasPlaybackController(
    resolveProject: () => project,
    resolveActiveCutId: () => const CutId('cut'),
    resolveActiveTrackId: () => const TrackId('track'),
    resolveFrameRate: () => ProjectFrameRate.fps24,
  );
}

/// The test binding with both laws of a clock's frames mixed in: drawn only
/// when something changed ([LookOnlyFrames]), and handed to the GPU at the
/// hand-off of the vblank its look claimed ([PresentPacing]) — on a display
/// the test owns.
class _PacedBinding extends AutomatedTestWidgetsFlutterBinding
    with LookOnlyFrames, PresentPacing {
  DisplayTiming? display;

  @override
  DisplayTiming? get displayTiming => display;

  /// What each held frame was told of the raster thread getting past its
  /// scene, oldest first: the test says when.
  final List<Completer<void>> behind = [];

  @override
  Future<void> rasterBehind() {
    final past = Completer<void>();
    behind.add(past);
    return past.future;
  }
}

/// 🚨A CLOCK'S LOOK CLAIMS A REAL VBLANK, AND ITS FRAME HANDS ITS SCENE TO
/// THE GPU IN THAT VBLANK'S WINDOW (유저 2026-10-11: 「144hz든 몇이든
/// 확실하게 근본/구조적으로 해결하도록」) — and the clock is read at the moment
/// that vblank is shown. No other frame waits for anything.
void main() {
  final binding = _PacedBinding();
  late _Display display;

  /// The claims as the binding should have made them, look for look.
  late PresentClaims expected;

  setUp(() {
    display = _Display();
    binding
      ..display = display
      ..debugForgetClaims()
      ..behind.clear();
    expected = PresentClaims();
  });

  const vsync = Duration(microseconds: 16667);

  PresentClaim expectedClaim({RasterSpread? spread}) => expected.claim(
    nowMicros: display.lookNow,
    vblankMicros: _Display.vblank,
    periodMicros: _Display.period,
    budgetMicros: PresentPacing.budgetMicros,
    handOffMicros: (spread ?? RasterSpread()).handOffFor(_Display.period),
  );

  /// A look in this frame changed what its clock shows — said to the
  /// binding, and to the claims the test expects.
  void changedInTheLook() {
    lookChangedWhatItShows();
    expected.changed();
  }

  /// A picture of a number, and nothing asking for a frame.
  Future<ValueNotifier<int>> settle(WidgetTester tester) async {
    final shown = ValueNotifier<int>(0);
    addTearDown(shown.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<int>(
          valueListenable: shown,
          builder: (context, value, child) => Text('$value'),
        ),
      ),
    );
    await tester.pump(vsync);
    display.waits.clear();
    return shown;
  }

  /// Asks for the next frame only to look in; [looks] is called in it.
  void lookNext(FrameCallback looks) {
    binding.askingOnlyToLook(() => binding.scheduleFrameCallback(looks));
  }

  testWidgets('🚨a clock\'s look is read at the moment its claimed vblank is '
      'shown, and its frame waits for that vblank\'s hand-off', (
    tester,
  ) async {
    final shown = await settle(tester);
    Duration? readAt;
    PresentClaim? claim;

    lookNext((_) {
      claim = expectedClaim();
      readAt = frameShownAt();
      shown.value += 1;
      changedInTheLook();
    });
    await tester.pump(vsync);

    expect(readAt, Duration(microseconds: claim!.shownAtMicros));
    expect(display.waits, [claim!.handOffMicros]);
  });

  testWidgets('🚨a clock\'s frame that something else ALSO asked to draw '
      'waits for its hand-off all the same — the film it carries is on it', (
    tester,
  ) async {
    final shown = await settle(tester);
    PresentClaim? claim;

    lookNext((_) {
      claim = expectedClaim();
      frameShownAt();
      shown.value += 1;
      changedInTheLook();
    });
    binding.scheduleFrame();
    await tester.pump(vsync);

    expect(display.waits, [claim!.handOffMicros]);
  });

  testWidgets('🚨a look that changed nothing is not held, though its frame '
      'is drawn for something else — a page turn between two film frames '
      'lands whenever it lands', (tester) async {
    final shown = await settle(tester);
    Duration? readAt;
    PresentClaim? claim;

    lookNext((_) {
      claim = expectedClaim();
      readAt = frameShownAt();
      shown.value += 1;
    });
    await tester.pump(vsync);

    expect(find.text('1'), findsOneWidget, reason: '⛔premise: drawn');
    expect(
      readAt,
      Duration(microseconds: claim!.shownAtMicros),
      reason: 'the clock still reads at its claim',
    );
    expect(display.waits, isEmpty);
  });

  testWidgets('🚨a frame no clock looked in is handed over as it is built — '
      'an edit is never held for a vblank', (tester) async {
    final shown = await settle(tester);

    shown.value += 1;
    await tester.pump(vsync);

    expect(display.waits, isEmpty);
  });

  testWidgets('🚨the frame after a change, whose look changed nothing, is '
      'not held — a change holds its own frame and no other', (tester) async {
    final shown = await settle(tester);
    lookNext((_) {
      expectedClaim();
      frameShownAt();
      shown.value += 1;
      changedInTheLook();
    });
    await tester.pump(vsync);
    expect(display.waits, hasLength(1), reason: '⛔premise: the change held');
    display.waits.clear();

    lookNext((_) {
      expectedClaim();
      frameShownAt();
      shown.value += 1;
    });
    await tester.pump(vsync);

    expect(display.waits, isEmpty);
  });

  testWidgets('a look that changed nothing draws nothing, and waits for '
      'nothing', (tester) async {
    await settle(tester);

    lookNext((_) => frameShownAt());
    await tester.pump(vsync);

    expect(display.waits, isEmpty);
  });

  testWidgets('a frame past its hand-off is handed over at once', (
    tester,
  ) async {
    final shown = await settle(tester);
    display.seamAfter = 40000;

    lookNext((_) {
      frameShownAt();
      shown.value += 1;
      changedInTheLook();
    });
    await tester.pump(vsync);

    expect(display.waits, isEmpty);
  });

  testWidgets('🚨looks a refresh apart fill one vblank after another — a '
      'change among them told to the chain', (tester) async {
    final shown = await settle(tester);
    const refresh = Duration(microseconds: 6949);
    final read = <Duration>[];
    final want = <int>[];

    for (var look = 0; look < 6; look += 1) {
      lookNext((_) {
        final claim = expectedClaim();
        want.add(claim.shownAtMicros);
        read.add(frameShownAt());
        if (look == 2) {
          shown.value += 1;
          changedInTheLook();
        }
      });
      await tester.pump(refresh);
    }

    expect(read, [for (final micros in want) Duration(microseconds: micros)]);
    for (var look = 1; look < read.length; look += 1) {
      expect(
        (read[look] - read[look - 1]).inMicroseconds,
        closeTo(_Display.period, 1),
        reason: 'look $look',
      );
    }
  });

  testWidgets('🚨a clock\'s time runs on the moments its frames are shown, '
      'not on the engine\'s vsyncs', (tester) async {
    await settle(tester);
    final elapsed = <Duration>[];
    final ticker = LookingTicker(elapsed.add);

    ticker.start(const TestVSync());
    // The engine's grid 7ms a step; the display's refresh 6.9486ms.
    for (var look = 0; look < 8; look += 1) {
      await tester.pump(const Duration(microseconds: 7000));
    }
    ticker.stop();

    expect(elapsed.first, Duration.zero);
    expect(
      elapsed.last.inMicroseconds,
      closeTo((elapsed.length - 1) * _Display.period, 2),
      reason: 'one refresh a look — not the 7ms the engine stepped',
    );
  });

  testWidgets('🚨a run tells the chain when its look changes the frame, and '
      'the look after it takes back the lead its wait spent', (tester) async {
    await settle(tester);
    final read = <Duration>[];
    var heard = 0;
    final controller = _playbackOfOneCut()
      ..resolveAudioClock = ({frameTime}) {
        read.add(frameTime!);
        return ClockReading(globalFrame: heard);
      };
    addTearDown(controller.dispose);
    controller.attachTicker(const TestVSync());
    controller.play(scope: PlaybackScope.activeCut);

    // The engine's grid 7ms a step — not the display's refresh — so a
    // clock read on the engine's times could not pass for one read on the
    // shown moments.
    const refresh = Duration(microseconds: 7000);
    await tester.pump(refresh);
    await tester.pump(refresh);
    heard = 1;
    await tester.pump(refresh);
    // The frame the change was drawn in waited for its hand-off and held the
    // next look up: two refreshes pass.
    await tester.pump(refresh * 2);
    controller.stop();

    expect(
      (read.last - read[read.length - 2]).inMicroseconds,
      closeTo(2 * _Display.period, 2),
      reason: 'the vblank right after the change is passed over',
    );
  });

  testWidgets('⛔where the engine\'s vsync is the display\'s there is no '
      'display timing: a clock reads its frame\'s own time, and nothing '
      'waits', (tester) async {
    final shown = await settle(tester);
    binding.display = null;
    Duration? readAt;

    lookNext((_) {
      readAt = frameShownAt();
      shown.value += 1;
    });
    await tester.pump(vsync);

    expect(readAt, binding.currentSystemFrameTimeStamp);
    expect(find.text('1'), findsOneWidget);
  });

  /// The raster thread is seen past the last held frame's scene [late]
  /// after a raster [ranFor] long ended.
  Future<void> seenPast(
    WidgetTester tester, {
    required int ranFor,
    required int late,
  }) async {
    display.between = display.seamNow + ranFor + late;
    binding.behind.removeLast().complete();
    await tester.pump();
    display.between = null;
  }

  /// A held frame, its claim mirrored with the lengths read so far.
  Future<void> heldFrame(
    WidgetTester tester,
    ValueNotifier<int> shown,
    RasterSpread read,
  ) async {
    lookNext((_) {
      expectedClaim(spread: read);
      frameShownAt();
      shown.value += 1;
      changedInTheLook();
    });
    await tester.pump(vsync);
  }

  testWidgets('🚨a held frame\'s length is read as its raster ends — the '
      'moment the raster thread is seen past its scene, less how late it is '
      'seen — and moves the next hand-off at once', (tester) async {
    final shown = await settle(tester);
    final learned = RasterSpread();
    for (var round = 0; round < 8; round += 1) {
      await heldFrame(tester, shown, learned);
      expect(binding.behind, hasLength(1), reason: 'one look behind it');
      final ranFor = 1500 + round * 10;
      await seenPast(
        tester,
        ranFor: ranFor,
        late: PresentPacing.seenLateUnmeasuredMicros,
      );
      learned.add(ranFor);
    }
    display.waits.clear();
    PresentClaim? claim;
    PresentClaim? unlearned;

    lookNext((_) {
      final now = display.lookNow;
      claim = expectedClaim(spread: learned);
      unlearned = PresentClaims().claim(
        nowMicros: now,
        vblankMicros: _Display.vblank,
        periodMicros: _Display.period,
        budgetMicros: PresentPacing.budgetMicros,
        handOffMicros: RasterSpread().handOffFor(_Display.period),
      );
      frameShownAt();
      shown.value += 1;
      changedInTheLook();
    });
    await tester.pump(vsync);

    expect(display.waits, [claim!.handOffMicros]);
    expect(
      claim!.handOffMicros - claim!.shownAtMicros,
      isNot(unlearned!.handOffMicros - unlearned!.shownAtMicros),
      reason: '⛔premise: the learned spread puts the hand-off elsewhere',
    );
  });

  testWidgets('a frame that was not held reads no length — how long a page '
      'turn took says nothing of where a change lands', (tester) async {
    final shown = await settle(tester);
    for (var round = 0; round < 8; round += 1) {
      lookNext((_) {
        expectedClaim();
        frameShownAt();
        shown.value += 1;
      });
      await tester.pump(vsync);
      binding.platformDispatcher.onReportTimings?.call([
        FrameTiming(
          vsyncStart: 0,
          buildStart: 0,
          buildFinish: 0,
          rasterStart: 0,
          rasterFinish: display.seamNow + 50000,
          rasterFinishWallTime: 0,
          frameNumber: binding.platformDispatcher.frameData.frameNumber,
        ),
      ]);
    }
    expect(binding.behind, isEmpty, reason: 'nothing looks behind them');
    PresentClaim? claim;

    lookNext((_) {
      claim = expectedClaim();
      frameShownAt();
      shown.value += 1;
      changedInTheLook();
    });
    await tester.pump(vsync);

    expect(display.waits, [claim!.handOffMicros]);
  });

  testWidgets('🚨how late the raster thread is seen past a scene is what the '
      'frames\' timings last said — every length read after them is read '
      'less that', (tester) async {
    final shown = await settle(tester);
    final read = RasterSpread();
    for (var round = 0; round < 8; round += 1) {
      await heldFrame(tester, shown, read);
      final rasterEnd = display.seamNow + 1500;
      await seenPast(tester, ranFor: 1500, late: 900);
      // The first is read before any timing has said how late the thread
      // is seen past a scene.
      read.add(
        round == 0
            ? 1500 + 900 - PresentPacing.seenLateUnmeasuredMicros
            : 1500,
      );
      // Its timing: the raster ended 900µs before the thread was seen past
      // it. (Every frame a test draws is frame 1 to the engine, so each
      // timing comes before the next frame.)
      binding.platformDispatcher.onReportTimings!([
        FrameTiming(
          vsyncStart: 0,
          buildStart: 0,
          buildFinish: 0,
          rasterStart: 0,
          rasterFinish: rasterEnd,
          rasterFinishWallTime: 0,
          frameNumber: binding.platformDispatcher.frameData.frameNumber,
        ),
      ]);
    }
    for (var round = 0; round < 8; round += 1) {
      await heldFrame(tester, shown, read);
      final ranFor = 1000 + round * 10;
      await seenPast(tester, ranFor: ranFor, late: 900);
      read.add(ranFor);
    }
    display.waits.clear();
    PresentClaim? claim;

    lookNext((_) {
      claim = expectedClaim(spread: read);
      frameShownAt();
      shown.value += 1;
      changedInTheLook();
    });
    await tester.pump(vsync);

    expect(display.waits, [claim!.handOffMicros]);
  });

  group('🚨while a clock runs the compositor composes on every vblank', () {
    testWidgets('from the clock\'s start to its stop — and rests after', (
      tester,
    ) async {
      await settle(tester);
      final clock = LookingTicker((_) {});
      addTearDown(clock.stop);

      clock.start(const TestVSync());
      expect(display.composing, [true]);
      await tester.pump(vsync);
      clock.stop();

      expect(display.composing, [true, false]);
    });

    testWidgets('two clocks: it rests only once the last has stopped', (
      tester,
    ) async {
      await settle(tester);
      final film = LookingTicker((_) {});
      final sound = LookingTicker((_) {});
      addTearDown(film.stop);
      addTearDown(sound.stop);

      film.start(const TestVSync());
      sound.start(const TestVSync());
      film.stop();
      expect(display.composing, [true], reason: 'one still runs');
      sound.stop();

      expect(display.composing, [true, false]);
    });

    testWidgets('a clock started afresh never stopped: the compositor is not '
        'let rest between', (tester) async {
      await settle(tester);
      final clock = LookingTicker((_) {});
      addTearDown(clock.stop);

      clock.start(const TestVSync());
      clock.start(const TestVSync());
      expect(display.composing, [true]);
      clock.stop();

      expect(display.composing, [true, false]);
    });

    testWidgets('a clock stopped twice says it once', (tester) async {
      await settle(tester);
      final clock = LookingTicker((_) {});
      addTearDown(clock.stop);

      clock.start(const TestVSync());
      clock.stop();
      clock.stop();

      expect(display.composing, [true, false]);
    });

    testWidgets('🚨a cut\'s playback composes while it plays', (tester) async {
      await settle(tester);
      final controller = _playbackOfOneCut();
      addTearDown(controller.dispose);
      controller.attachTicker(const TestVSync());

      controller.play(scope: PlaybackScope.activeCut);
      await tester.pump(vsync);
      expect(display.composing, [true]);
      controller.stop();

      expect(display.composing, [true, false]);
    });
  });

  group('the quiet between held frames', () {
    /// The run's clock: a quiet is kept only while one is running.
    final clock = Object();
    setUp(() => clockStarted(clock));
    tearDown(() => clockStopped(clock));

    /// Holds a frame a film frame apart for each of [intervals], each its
    /// look's change; answers the last one's claim.
    Future<PresentClaim> holdChanges(
      WidgetTester tester,
      ValueNotifier<int> shown,
      List<int> intervals,
    ) async {
      PresentClaim? last;
      for (final interval in intervals) {
        lookNext((_) {
          last = expectedClaim();
          frameShownAt();
          shown.value += 1;
          changedInTheLook();
        });
        await tester.pump(Duration(microseconds: interval));
      }
      return last!;
    }

    /// The quiet after a held frame that claimed [last], the next standing
    /// [gap] refreshes past it.
    ({int fromMicros, int untilMicros}) quietAfter(
      PresentClaim last, {
      required int gap,
    }) => quietBetweenHeldFrames(
      held: (
        vblankMicros:
            last.shownAtMicros - presentShownAfterVblanks * _Display.period,
        periodMicros: _Display.period,
        gap: gap,
        handOffMicros: RasterSpread().handOffFor(_Display.period),
      ),
      marginMicros: PresentPacing.budgetMicros + 1000,
    );

    testWidgets('🚨runs from where the last held frame\'s latch window '
        'closes to before the next is handed over — read off the vblanks '
        'the frames held claimed', (tester) async {
      final shown = await settle(tester);
      expect(quietForBackgroundGpuWork(), isNull, reason: 'nothing held yet');

      final last = await holdChanges(tester, shown, [41700, 41700, 41700]);

      expect(quietForBackgroundGpuWork(), quietAfter(last, gap: 6));
    });

    testWidgets('🚨one odd gap — a loop\'s wrap — does not shorten the '
        'quiets after it', (tester) async {
      final shown = await settle(tester);
      final last = await holdChanges(
        tester,
        shown,
        [41700, 13900, 41700, 41700],
      );

      expect(quietForBackgroundGpuWork(), quietAfter(last, gap: 6));
    });

    testWidgets('a clock that has not looked for a while — its ticker '
        'silenced — holds nothing, and there is no quiet to keep', (
      tester,
    ) async {
      final shown = await settle(tester);
      await holdChanges(tester, shown, [41700, 41700]);
      expect(quietForBackgroundGpuWork(), isNotNull, reason: '⛔premise');

      binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 200));

      expect(quietForBackgroundGpuWork(), isNull);
    });

    testWidgets('🚨the last clock stopped: no quiet, at once — a run that '
        'stands to wait for its picture keeps nothing waiting for a quiet', (
      tester,
    ) async {
      final shown = await settle(tester);
      await holdChanges(tester, shown, [41700, 41700]);
      expect(quietForBackgroundGpuWork(), isNotNull, reason: '⛔premise');

      clockStopped(clock);

      expect(quietForBackgroundGpuWork(), isNull);
    });

    group('what waits for the quiet to move is told', () {
      /// Whether what waits, from now, has been told.
      Future<bool Function()> waiting(WidgetTester tester) async {
        var moved = false;
        unawaited(quietMayHaveMoved().then((_) => moved = true));
        await tester.pump();
        return () => moved;
      }

      testWidgets('🚨when the next frame is held — the quiet it leaves is '
          'the next', (tester) async {
        final shown = await settle(tester);
        await holdChanges(tester, shown, [41700, 41700]);
        final moved = await waiting(tester);
        await tester.pump(const Duration(milliseconds: 20));
        expect(moved(), isFalse, reason: 'nothing held since');

        await holdChanges(tester, shown, [41700]);

        expect(moved(), isTrue);
      });

      testWidgets('🚨when the last clock stops', (tester) async {
        final shown = await settle(tester);
        await holdChanges(tester, shown, [41700, 41700]);
        final moved = await waiting(tester);
        expect(moved(), isFalse, reason: '⛔premise');

        clockStopped(clock);
        await tester.pump();

        expect(moved(), isTrue);
      });

      testWidgets('when no clock has looked for a while', (tester) async {
        final shown = await settle(tester);
        await holdChanges(tester, shown, [41700, 41700]);
        final moved = await waiting(tester);
        expect(moved(), isFalse, reason: '⛔premise');

        await tester.pump(const Duration(milliseconds: 150));

        expect(moved(), isTrue);
      });

      testWidgets('at once where no quiet is kept', (tester) async {
        await settle(tester);
        expect(quietForBackgroundGpuWork(), isNull, reason: '⛔premise');

        final moved = await waiting(tester);

        expect(moved(), isTrue);
      });
    });

    testWidgets('⛔where the display says nothing, there is no quiet either', (
      tester,
    ) async {
      final shown = await settle(tester);
      await holdChanges(tester, shown, [41700, 41700]);
      binding.display = null;

      expect(quietForBackgroundGpuWork(), isNull);
    });
  });
}
