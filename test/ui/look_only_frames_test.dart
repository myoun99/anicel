import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/look_only_frames.dart';
import 'package:anicel/src/ui/ui_scale_binding.dart';

import '../helpers/look_test_binding.dart';

/// 유저 2026-10-08: 「3 화면을 프레임만큼만 다시그리도록」 — and, of the
/// clock that has to look at every vsync to be on time: 「소리 싱크나
/// 영상이나 뭐 그런거 정확하기만하면되. 그게 제일 최우선.」
///
/// A frame that was asked for only to LOOK is begun, and not drawn — unless
/// something wants a picture. Counted here: the frames that reach the
/// framework's own `drawFrame` ([LookTestBinding.drawnFrames]).
void main() {
  final binding = LookTestBinding.ensureInitialized();

  const vsync = Duration(microseconds: 16667);

  /// Asks for the next frame only to look in; [looks] is called in it.
  void lookNext(FrameCallback looks) {
    binding.askingOnlyToLook(() => binding.scheduleFrameCallback(looks));
  }

  /// A picture of [shown], and nothing asking for a frame.
  Future<void> settle(WidgetTester tester, ValueNotifier<int> shown) async {
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
    expect(binding.hasScheduledFrame, isFalse, reason: '⛔premise: at rest');
  }

  testWidgets('🚨a frame asked for only to look is begun — what looks is '
      'called, on the vsync — and it is not drawn', (tester) async {
    await settle(tester, ValueNotifier<int>(0));
    final drawn = binding.drawnFrames;
    var looked = 0;

    lookNext((_) => looked += 1);
    expect(binding.hasScheduledFrame, isTrue, reason: 'a vsync is asked for');
    await tester.pump(vsync);

    expect(looked, 1);
    expect(binding.drawnFrames, drawn);
  });

  testWidgets('🚨what the look changes is drawn in the frame that looked', (
    tester,
  ) async {
    final shown = ValueNotifier<int>(0);
    await settle(tester, shown);
    final drawn = binding.drawnFrames;

    lookNext((_) => shown.value = 7);
    await tester.pump(vsync);

    expect(find.text('7'), findsOneWidget, reason: 'built in this frame');
    expect(binding.drawnFrames, drawn + 1);
    expect(
      binding.hasScheduledFrame,
      isFalse,
      reason: 'and no frame is asked for to make up for it',
    );
  });

  testWidgets('🚨frame after frame looked at draws nothing; the one that '
      'changes something is drawn, and the look after it is not', (
    tester,
  ) async {
    final shown = ValueNotifier<int>(0);
    await settle(tester, shown);
    final drawn = binding.drawnFrames;
    var looks = 0;
    void look(Duration _) {
      looks += 1;
      if (looks == 6) {
        shown.value = 1;
      }
      if (looks < 12) {
        lookNext(look);
      }
    }

    lookNext(look);
    for (var frame = 1; frame <= 5; frame += 1) {
      await tester.pump(vsync);
    }
    expect(looks, 5);
    expect(binding.drawnFrames, drawn, reason: 'five looks, nothing drawn');

    await tester.pump(vsync);
    expect(find.text('1'), findsOneWidget);
    expect(binding.drawnFrames, drawn + 1, reason: 'the look that changed it');

    for (var frame = 7; frame <= 12; frame += 1) {
      await tester.pump(vsync);
    }
    expect(looks, 12);
    expect(
      binding.drawnFrames,
      drawn + 1,
      reason: 'a frame that was drawn does not have the next one drawn too',
    );
  });

  testWidgets('a frame someone else asked for as well is drawn — whichever '
      'of the two asked first', (tester) async {
    await settle(tester, ValueNotifier<int>(0));
    final drawn = binding.drawnFrames;

    lookNext((_) {});
    binding.scheduleFrame();
    await tester.pump(vsync);
    expect(binding.drawnFrames, drawn + 1, reason: 'the look asked first');

    binding.scheduleFrame();
    lookNext((_) {});
    await tester.pump(vsync);
    expect(binding.drawnFrames, drawn + 2, reason: 'the look asked second');
  });

  testWidgets('a frame that is forced is drawn, a look waiting or not', (
    tester,
  ) async {
    await settle(tester, ValueNotifier<int>(0));
    final drawn = binding.drawnFrames;

    lookNext((_) {});
    binding.scheduleForcedFrame();
    await tester.pump(vsync);

    expect(binding.drawnFrames, drawn + 1);
  });

  testWidgets('something made dirty while a look waits for its vsync is '
      'drawn on it', (tester) async {
    final shown = ValueNotifier<int>(0);
    await settle(tester, shown);
    final drawn = binding.drawnFrames;

    lookNext((_) {});
    shown.value = 3;
    await tester.pump(vsync);

    expect(find.text('3'), findsOneWidget);
    expect(binding.drawnFrames, drawn + 1);
  });

  // The engine begins frames nobody in the framework asked for — a repaint
  // the platform wants, the first frame of a new surface.
  testWidgets('🚨a frame nobody asked to look in is drawn, as every frame '
      'always was — also right after one that was only looked in', (
    tester,
  ) async {
    await settle(tester, ValueNotifier<int>(0));
    lookNext((_) {});
    await tester.pump(vsync);
    final drawn = binding.drawnFrames;

    binding.handleBeginFrame(null);
    binding.handleDrawFrame();

    expect(binding.drawnFrames, drawn + 1);
  });

  testWidgets('what was to run after the frame runs after a frame that was '
      'only looked in, too', (tester) async {
    await settle(tester, ValueNotifier<int>(0));
    final drawn = binding.drawnFrames;
    var after = 0;

    binding.addPostFrameCallback((_) => after += 1);
    lookNext((_) {});
    await tester.pump(vsync);

    expect(after, 1);
    expect(binding.drawnFrames, drawn);
  });

  testWidgets('🚨the look is over when the asking is: what asks next asks '
      'for a picture — also when the asking threw, and inside another '
      'look it is still that look', (tester) async {
    await settle(tester, ValueNotifier<int>(0));
    final drawn = binding.drawnFrames;

    expect(
      () => binding.askingOnlyToLook(() => throw StateError('asked badly')),
      throwsStateError,
    );
    binding.scheduleFrame();
    await tester.pump(vsync);
    expect(binding.drawnFrames, drawn + 1, reason: 'asked outside the look');

    binding.askingOnlyToLook(() {
      binding.askingOnlyToLook(() {});
      binding.scheduleFrameCallback((_) {});
    });
    await tester.pump(vsync);
    expect(
      binding.drawnFrames,
      drawn + 1,
      reason: 'the look inside ended; the one around it had not',
    );
  });

  // A test cannot start the app's binding — the test's own is there
  // first — so what it wears is asked of its type.
  test('🚨the app\'s own binding wears the law', () {
    expect(<AnicelBinding>[], isA<List<LookOnlyFrames>>());
  });

  // A ticker of the ordinary kind — an animation — asks for its frames to
  // be drawn, and the law leaves it alone.
  testWidgets('an ordinary ticker beside a look: every frame is drawn', (
    tester,
  ) async {
    await settle(tester, ValueNotifier<int>(0));
    final drawn = binding.drawnFrames;
    var looking = true;
    void look(Duration _) {
      if (looking) {
        lookNext(look);
      }
    }

    final ticker = Ticker((_) {});
    addTearDown(ticker.dispose);
    lookNext(look);
    unawaited(ticker.start());
    for (var frame = 0; frame < 4; frame += 1) {
      await tester.pump(vsync);
    }
    expect(binding.drawnFrames, drawn + 4);

    ticker.stop();
    await tester.pump(vsync);
    final afterTheTicker = binding.drawnFrames;
    await tester.pump(vsync);
    await tester.pump(vsync);
    expect(
      binding.drawnFrames,
      afterTheTicker,
      reason: 'the ticker gone, the look alone draws nothing again',
    );
    looking = false;
    await tester.pump(vsync);
  });
}
