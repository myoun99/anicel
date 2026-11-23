import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/canvas/picture_up_view.dart';
import 'package:anicel/src/ui/debug/measurement_mode.dart';
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
  });

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

  test('the newest steps are kept, the oldest let go', () {
    for (var dabs = 0; dabs <= StrokeSteps.stepsKept; dabs += 1) {
      StrokeSteps.stepped(dabs, together: null);
    }
    expect(StrokeSteps.dabsKept, hasLength(StrokeSteps.stepsKept));
    expect(StrokeSteps.dabsKept.first, 1);
    expect(StrokeSteps.stepsCounted, StrokeSteps.stepsKept + 1);
  });
}
