import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuSampling;
import 'package:anicel/src/ui/canvas/picture_up_view.dart';
import 'package:anicel/src/ui/debug/engine_behind.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
import 'package:anicel/src/ui/debug/picture_writes.dart';
import 'package:anicel/src/ui/debug/screen_asked.dart';
import 'package:anicel/src/ui/debug/stroke_steps.dart';

/// 🔬A stroke's steps as the frame statistics count them (`StrokeSteps`):
/// how long the first dab of each waited for it to go out, and how long
/// till the frame that showed it was up — the pen's line on the screen as
/// late as it is (card the-galaxy-tab-canvas-went-slow-on-build-1095).
void main() {
  var now = 0;
  setUp(() {
    MeasurementMode.frameStats.value = true;
    StrokeSteps.forget();
    now = 0;
    StrokeSteps.debugMicros = () => now;
  });
  tearDown(() {
    MeasurementMode.reset();
    StrokeSteps.forget();
    StrokeSteps.debugMicros = null;
    EngineBehind.debugNow = null;
    ScreenAsked.debugForget();
  });

  /// An ask of a screen's, [columns] wide.
  ScreenAsk anAsk(int columns) => (
    columns: columns,
    rows: 10,
    texels: columns * 10,
    moved: null,
    scale: 1,
    mode: GpuSampling.nearest,
  );

  /// A frame of the app's: a test pumps none it was not asked for.
  Future<void> aFrame(WidgetTester tester) {
    tester.binding.scheduleFrame();
    return tester.pump();
  }

  testWidgets('a step is held from the first of its dabs queued, and the '
      'next waits from its own', (tester) async {
    StrokeSteps.queued();
    now = 3000;
    StrokeSteps.queued();
    now = 5000;
    StrokeSteps.stepped(2, together: null);
    now = 6000;
    StrokeSteps.queued();
    now = 6500;
    StrokeSteps.stepped(1, together: null);

    expect(StrokeSteps.heldMicros, [5000, 500]);
    expect([StrokeSteps.stepsCounted, StrokeSteps.dabsCounted], [2, 3]);
    expect(StrokeSteps.dabsKept, [2, 1]);
    now = 8000;
    await aFrame(tester);
    expect(
      StrokeSteps.upMicros,
      [8000, 2000],
      reason: 'with no frame of a canvas drawn, up at the frame painted',
    );
  });

  testWidgets('a step whose frame is being drawn is up once that frame is', (
    tester,
  ) async {
    final together = PicturesUpTogether();
    StrokeSteps.queued();
    now = 1000;
    StrokeSteps.stepped(2, together: together);
    // The paint that draws the step puts its frame up (ScreenTexture.present).
    final drawn = Completer<void>();
    unawaited(together.joined(drawn.future));
    now = 3000;
    await aFrame(tester);
    expect(StrokeSteps.upMicros, isEmpty, reason: 'its frame is being drawn');

    now = 7000;
    drawn.complete();
    await tester.idle();
    expect(StrokeSteps.upMicros, [7000]);
  });

  testWidgets('nothing is counted while the statistics are off, nor held '
      'from a dab queued then', (tester) async {
    MeasurementMode.frameStats.value = false;
    StrokeSteps.queued();
    StrokeSteps.stepped(4, together: null);
    await aFrame(tester);
    expect([StrokeSteps.stepsCounted, StrokeSteps.dabsCounted], [0, 0]);
    expect(StrokeSteps.dabsKept, isEmpty);

    StrokeSteps.queued();
    MeasurementMode.frameStats.value = true;
    now = 4000;
    StrokeSteps.stepped(3, together: null);
    await aFrame(tester);
    expect(StrokeSteps.dabsKept, [3], reason: 'the step, counted');
    expect(
      [StrokeSteps.heldMicros, StrokeSteps.upMicros],
      [isEmpty, isEmpty],
      reason: 'its first dab queued while off: no time to tell from',
    );
  });

  group('a stroke\'s first step', () {
    testWidgets('is told from its press: armed, its first dab, held, up, '
        'the GPU\'s backlog as it went, and what its frame did', (
      tester,
    ) async {
      var behind = 3;
      EngineBehind.debugNow = () => behind;
      PictureWrites.wrote(PictureWrite.copied);
      ScreenAsked.shown(anAsk(1));
      StrokeSteps.pressed();
      now = 400;
      StrokeSteps.queued();
      now = 900;
      StrokeSteps.armed();
      now = 2000;
      StrokeSteps.queued();
      StrokeSteps.stepped(2, together: null);
      behind = 9;
      expect(StrokeSteps.firstStep, (
        armed: 900,
        dab: 400,
        held: 1600,
        up: null,
        behind: 3,
        did: null,
      ), reason: 'out, not up yet');

      // The frame's paint, which shows it.
      PictureWrites.wrote(PictureWrite.inPlace);
      PictureWrites.wrote(PictureWrite.whole);
      ScreenAsked.shown(anAsk(64));
      now = 5000;
      await aFrame(tester);
      expect(StrokeSteps.firstStep, (
        armed: 900,
        dab: 400,
        held: 1600,
        up: 5000,
        behind: 3,
        did: (wrote: (inPlace: 1, copied: 0, whole: 1), asked: anAsk(64)),
      ), reason: 'what the frame did, not what was done before it');
      expect(StrokeSteps.firstUpMicros, [5000]);
      expect(StrokeSteps.upMicros, [4600], reason: 'a step too');
    });

    testWidgets('is the first alone: the steps after it are steps', (
      tester,
    ) async {
      StrokeSteps.pressed();
      now = 100;
      StrokeSteps.queued();
      StrokeSteps.stepped(1, together: null);
      now = 1000;
      await aFrame(tester);
      final first = StrokeSteps.firstStep;
      now = 2000;
      StrokeSteps.queued();
      now = 2500;
      StrokeSteps.stepped(1, together: null);
      PictureWrites.wrote(PictureWrite.copied);
      now = 4000;
      await aFrame(tester);
      expect(StrokeSteps.firstStep, first);
      expect(StrokeSteps.firstUpMicros, [1000]);
      expect(StrokeSteps.upMicros, [900, 2000]);
    });

    testWidgets('of a frame that drew no screen says none — not the ask '
        'before it', (tester) async {
      ScreenAsked.shown(anAsk(8));
      StrokeSteps.pressed();
      StrokeSteps.queued();
      StrokeSteps.stepped(1, together: null);
      await aFrame(tester);
      expect(StrokeSteps.firstStep?.did, (
        wrote: (inPlace: 0, copied: 0, whole: 0),
        asked: null,
      ));
    });

    testWidgets('is up once the frame of the pictures being drawn is', (
      tester,
    ) async {
      final together = PicturesUpTogether();
      StrokeSteps.pressed();
      now = 500;
      StrokeSteps.queued();
      StrokeSteps.stepped(1, together: together);
      final drawn = Completer<void>();
      unawaited(together.joined(drawn.future));
      await aFrame(tester);
      expect(StrokeSteps.firstStep?.up, isNull);
      now = 9000;
      drawn.complete();
      await tester.idle();
      expect(StrokeSteps.firstStep?.up, 9000);
      expect(StrokeSteps.firstUpMicros, [9000]);
    });

    testWidgets('of a stroke pressed again before its frame is the newest '
        'stroke\'s', (tester) async {
      StrokeSteps.pressed();
      now = 50;
      StrokeSteps.armed();
      StrokeSteps.queued();
      StrokeSteps.stepped(1, together: null);
      now = 1000;
      StrokeSteps.pressed();
      now = 1200;
      StrokeSteps.queued();
      StrokeSteps.stepped(1, together: null);
      now = 3000;
      await aFrame(tester);
      expect(StrokeSteps.firstStep, (
        armed: 200,
        dab: 200,
        held: 0,
        up: 2000,
        behind: null,
        did: (wrote: (inPlace: 0, copied: 0, whole: 0), asked: null),
      ), reason: 'unarmed: armed as its step went out, not as the one before');
      expect(StrokeSteps.firstUpMicros, [3000, 2000]);
    });

    testWidgets('is none of a press while the statistics were off', (
      tester,
    ) async {
      MeasurementMode.frameStats.value = false;
      StrokeSteps.pressed();
      MeasurementMode.frameStats.value = true;
      StrokeSteps.queued();
      StrokeSteps.stepped(1, together: null);
      await aFrame(tester);
      expect(StrokeSteps.firstStep, isNull);
      expect(StrokeSteps.upMicros, hasLength(1), reason: 'a step');
    });

    testWidgets('the newest strokes\' are kept, the oldest let go', (
      tester,
    ) async {
      for (var stroke = 0; stroke <= StrokeSteps.strokesKept; stroke += 1) {
        now = stroke * 1000;
        StrokeSteps.pressed();
        StrokeSteps.queued();
        StrokeSteps.stepped(1, together: null);
        now += stroke;
        await aFrame(tester);
      }
      expect(StrokeSteps.firstUpMicros, hasLength(StrokeSteps.strokesKept));
      expect(StrokeSteps.firstUpMicros.first, 1);
    });
  });

  testWidgets('a landing is told from the lift: its commit, the frame after '
      'it up, the GPU\'s backlog once committed and what that frame did', (
    tester,
  ) async {
    var behind = 4;
    EngineBehind.debugNow = () => behind;
    now = 500;
    StrokeSteps.lifted();
    now = 1000;
    StrokeSteps.landed(together: null);
    behind = 0;
    expect(StrokeSteps.landing, (commit: 500, up: null, behind: 4, did: null));
    PictureWrites.wrote(PictureWrite.inPlace);
    ScreenAsked.shown(anAsk(32));
    now = 7000;
    await aFrame(tester);
    expect(StrokeSteps.landing, (
      commit: 500,
      up: 6500,
      behind: 4,
      did: (wrote: (inPlace: 1, copied: 0, whole: 0), asked: anAsk(32)),
    ));

    now = 8000;
    StrokeSteps.landed(together: null);
    now = 8500;
    StrokeSteps.landed(together: null);
    now = 9000;
    await aFrame(tester);
    expect(
      [StrokeSteps.landing?.commit, StrokeSteps.landing?.up],
      [0, 500],
      reason: 'the newest landing, no lift told: from its commit',
    );

    StrokeSteps.forget();
    expect(
      [StrokeSteps.landing, StrokeSteps.firstStep, StrokeSteps.firstUpMicros],
      [null, null, isEmpty],
    );
  });

  test('a landing is none while the statistics are off, nor timed from a '
      'lift told then', () {
    MeasurementMode.frameStats.value = false;
    StrokeSteps.lifted();
    StrokeSteps.landed(together: null);
    expect(StrokeSteps.landing, isNull);
    now = 3000;
    MeasurementMode.frameStats.value = true;
    StrokeSteps.landed(together: null);
    expect(StrokeSteps.landing?.commit, 0);
  });

  test('a picture\'s writes are counted by how each went, and none while '
      'the statistics are off', () {
    final before = PictureWrites.counted;
    PictureWrites.wrote(PictureWrite.inPlace);
    PictureWrites.wrote(PictureWrite.copied);
    PictureWrites.wrote(PictureWrite.copied);
    PictureWrites.wrote(PictureWrite.whole);
    MeasurementMode.frameStats.value = false;
    PictureWrites.wrote(PictureWrite.whole);
    final after = PictureWrites.counted;
    expect(
      [
        after.inPlace - before.inPlace,
        after.copied - before.copied,
        after.whole - before.whole,
      ],
      [1, 2, 1],
    );
  });

  test('a lift told before the statistics were let go of times no landing '
      'after', () {
    now = 1000;
    StrokeSteps.lifted();
    StrokeSteps.forget();
    now = 3000;
    StrokeSteps.landed(together: null);
    expect(StrokeSteps.landing?.commit, 0);
  });

  test('the newest steps are kept, the oldest let go', () {
    for (var dabs = 0; dabs <= StrokeSteps.stepsKept; dabs += 1) {
      StrokeSteps.stepped(dabs, together: null);
    }
    expect(StrokeSteps.dabsKept, hasLength(StrokeSteps.stepsKept));
    expect(StrokeSteps.dabsKept.first, 1);
    expect(StrokeSteps.stepsCounted, StrokeSteps.stepsKept + 1);
  });
}
