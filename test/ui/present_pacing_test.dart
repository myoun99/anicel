
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

  @override
  int get nowMicros {
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
}

/// The test binding with both laws of a clock's frames mixed in: drawn only
/// when something changed ([LookOnlyFrames]), and handed to the GPU in the
/// window of the vblank its look claimed ([PresentPacing]) — on a display
/// the test owns.
class _PacedBinding extends AutomatedTestWidgetsFlutterBinding
    with LookOnlyFrames, PresentPacing {
  DisplayTiming? display;

  @override
  DisplayTiming? get displayTiming => display;
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
      ..debugForgetClaims();
    expected = PresentClaims();
  });

  const vsync = Duration(microseconds: 16667);

  PresentClaim expectedClaim({RasterSpread? spread}) => expected.claim(
    nowMicros: display.lookNow,
    vblankMicros: _Display.vblank,
    periodMicros: _Display.period,
    budgetMicros: PresentPacing.budgetMicros,
    rasterLowMicros: (spread ?? RasterSpread()).lowMicros,
    rasterHighMicros: (spread ?? RasterSpread()).highMicros,
  );

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
      'shown, and its frame waits for that vblank\'s window', (tester) async {
    final shown = await settle(tester);
    Duration? readAt;
    PresentClaim? claim;

    lookNext((_) {
      claim = expectedClaim();
      readAt = frameShownAt();
      shown.value += 1;
    });
    await tester.pump(vsync);

    expect(readAt, Duration(microseconds: claim!.shownAtMicros));
    expect(display.waits, [claim!.handOffFromMicros]);
  });

  testWidgets('🚨a clock\'s frame that something else ALSO asked to draw '
      'waits for its window all the same — the film it carries is on it', (
    tester,
  ) async {
    final shown = await settle(tester);
    PresentClaim? claim;

    lookNext((_) {
      claim = expectedClaim();
      frameShownAt();
      shown.value += 1;
    });
    binding.scheduleFrame();
    await tester.pump(vsync);

    expect(display.waits, [claim!.handOffFromMicros]);
  });

  testWidgets('🚨a frame no clock looked in is handed over as it is built — '
      'an edit is never held for a vblank', (tester) async {
    final shown = await settle(tester);

    shown.value += 1;
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

  testWidgets('a frame already inside its window is handed over at once', (
    tester,
  ) async {
    final shown = await settle(tester);
    display.seamAfter = 40000;

    lookNext((_) {
      frameShownAt();
      shown.value += 1;
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
          lookChangedWhatItShows();
          expected.changed();
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
    final controller =
        CanvasPlaybackController(
            resolveProject: () => project,
            resolveActiveCutId: () => const CutId('cut'),
            resolveActiveTrackId: () => const TrackId('track'),
            resolveFrameRate: () => const ProjectFrameRate.integer(24),
          )
          ..resolveAudioClock = ({frameTime}) {
            read.add(frameTime!);
            return ClockReading(globalFrame: heard);
          };
    addTearDown(controller.dispose);
    controller.attachTicker(const TestVSync());
    controller.play(scope: PlaybackScope.activeCut);

    const refresh = Duration(microseconds: 6949);
    await tester.pump(refresh);
    await tester.pump(refresh);
    heard = 1;
    await tester.pump(refresh);
    // The frame the change was drawn in waited for its window and held the
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

  testWidgets('🚨the raster\'s spread is learned from the frames it paced: '
      'what their timings say moves the next window', (tester) async {
    final shown = await settle(tester);
    final learned = RasterSpread();
    for (var round = 0; round < 8; round += 1) {
      lookNext((_) {
        expectedClaim();
        frameShownAt();
        shown.value += 1;
      });
      await tester.pump(vsync);
      final released = display.seamNow;
      final ranFor = 1500 + round * 10;
      learned.add(ranFor);
      binding.platformDispatcher.onReportTimings!([
        FrameTiming(
          vsyncStart: 0,
          buildStart: 0,
          buildFinish: 0,
          rasterStart: 0,
          rasterFinish: released + ranFor,
          rasterFinishWallTime: 0,
          frameNumber: binding.platformDispatcher.frameData.frameNumber,
        ),
      ]);
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
        rasterLowMicros: RasterSpread.unmeasuredLowMicros,
        rasterHighMicros: RasterSpread.unmeasuredHighMicros,
      );
      frameShownAt();
      shown.value += 1;
    });
    await tester.pump(vsync);

    expect(display.waits, [claim!.handOffFromMicros]);
    expect(
      claim!.handOffFromMicros - claim!.shownAtMicros,
      isNot(unlearned!.handOffFromMicros - unlearned!.shownAtMicros),
      reason: '⛔premise: the learned spread puts the window elsewhere',
    );
  });
}
