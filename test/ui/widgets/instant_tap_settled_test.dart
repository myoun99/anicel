import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/input/eager_pan_gesture_recognizer.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/widgets/instant_tap_region.dart';

/// 🚨T10's missing signal: **the release, and only when nothing travelled.**
///
/// 유저 확정 2026-08-14: 「탭다운 하면 **먼저 기존 선택된거 삭제**하게 하면 …」
/// and 「**클릭하고 떼면 뭐든 비우게**」 — two different jobs at two different
/// moments, which `onTap` alone cannot carry because it fires at ONE of them
/// depending on the device.
///
/// | moment | job |
/// |---|---|
/// | DOWN | move the active target; clear only if the press landed outside the selection |
/// | RELEASE, no travel | clear |
///
/// ⛔Clearing on the down unconditionally kills a move drag that starts
/// inside a selection — measured, not assumed: flipping
/// `AppInput.timelineCellPressSeeks` on by itself makes an SE row move stop
/// committing. ⛔Clearing only on the release leaves a range drag that began
/// OUTSIDE a selection carrying the old one the whole way, and a drag has
/// travel, so it would never clear at all.
void main() {
  Widget harness({
    required void Function(Offset) onTap,
    void Function(Offset)? onSettledTap,
    bool Function(PointerDeviceKind)? pressSeeksFor,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: InstantTapRegion(
          key: const ValueKey<String>('region'),
          onTap: onTap,
          onSettledTap: onSettledTap,
          pressSeeksFor: pressSeeksFor,
          behavior: HitTestBehavior.opaque,
          child: const SizedBox(width: 200, height: 200),
        ),
      ),
    ),
  );

  testWidgets('a mouse tap fires the primary on the DOWN and settles on the '
      'release — both, in that order', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(
      harness(
        onTap: (_) => events.add('tap'),
        onSettledTap: (_) => events.add('settled'),
        pressSeeksFor: (_) => true,
      ),
    );

    final region = find.byKey(const ValueKey<String>('region'));
    final gesture = await tester.startGesture(
      tester.getCenter(region),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(events, ['tap'], reason: 'the press acted, the release has not');

    await gesture.up();
    await tester.pump();
    expect(
      events,
      ['tap', 'settled'],
      reason: 'and the release says it turned out to be a tap',
    );
  });

  testWidgets('a press that TRAVELS never settles', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(
      harness(
        onTap: (_) => events.add('tap'),
        onSettledTap: (_) => events.add('settled'),
        pressSeeksFor: (_) => true,
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>('region'))),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(
      events,
      ['tap'],
      reason: 'a drag picked what it was about to drag, and settled nothing — '
          'this is what keeps a range drag from clearing at its own end',
    );
  });

  testWidgets('a finger that stays put owes BOTH, and one that scrolls owes '
      'neither', (tester) async {
    final events = <String>[];
    Widget build() => harness(
      onTap: (_) => events.add('tap'),
      onSettledTap: (_) => events.add('settled'),
      // The default: a finger acts on the release, because its press is
      // ambiguous with the start of a scroll (UI-R23 feedback #2).
    );

    await tester.pumpWidget(build());
    final region = find.byKey(const ValueKey<String>('region'));

    var gesture = await tester.startGesture(
      tester.getCenter(region),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    expect(events, isEmpty, reason: 'a finger withholds on the press');
    await gesture.up();
    await tester.pump();
    expect(
      events,
      ['tap', 'settled'],
      reason: 'the release owes the primary action AND the settle',
    );

    events.clear();
    gesture = await tester.startGesture(
      tester.getCenter(region),
      kind: PointerDeviceKind.touch,
    );
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(events, isEmpty, reason: 'a scroll is not a tap at either end');
  });

  testWidgets('a cancel settles nothing', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(
      harness(
        onTap: (_) => events.add('tap'),
        onSettledTap: (_) => events.add('settled'),
        pressSeeksFor: (_) => true,
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>('region'))),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.cancel();
    await tester.pump();

    expect(events, ['tap'], reason: 'the press acted; the gesture never ended');
  });

  // 🚨「Did it travel」 stopped telling a tap from a drag (F-238 made a
  // one-frame move fit inside this region's slop): a press whose drag
  // CHANGED something is no tap, and its drag says so by the pointer.
  group('a press an edit drag took a step with', () {
    const pointer = 71;
    setUp(debugClearValueControlPointers);

    Future<List<String>> pressAndRelease(
      WidgetTester tester, {
      required bool stepped,
    }) async {
      final events = <String>[];
      await tester.pumpWidget(
        harness(
          onTap: (_) => events.add('tap'),
          onSettledTap: (_) => events.add('settled'),
          // A finger: the primary is owed on the release.
          pressSeeksFor: (_) => false,
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey<String>('region'))),
        kind: PointerDeviceKind.touch,
        pointer: pointer,
      );
      await gesture.moveBy(const Offset(3, 0));
      if (stepped) {
        // As the drag under the same pointer does, once it has changed
        // something.
        markPointerDragStepped(pointer);
      }
      await gesture.up();
      await tester.pump();
      return events;
    }

    testWidgets('settles nothing and owes no tap, though it barely moved', (
      tester,
    ) async {
      expect(await pressAndRelease(tester, stepped: true), isEmpty);
    });

    testWidgets('the same press with no drag under it is a tap', (
      tester,
    ) async {
      expect(await pressAndRelease(tester, stepped: false), [
        'tap',
        'settled',
      ]);
    });
  });

  group('an eager pan tells the taps what its drag did', () {
    const pointer = 72;
    setUp(debugClearValueControlPointers);

    /// A pan over the whole screen whose owner answers [stepped].
    Widget pan({required bool Function() stepped}) => MaterialApp(
      home: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          EagerPanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<EagerPanGestureRecognizer>(
                EagerPanGestureRecognizer.new,
                (recognizer) {
                  recognizer.draggedAStep = stepped;
                  recognizer.onStart = (_) {};
                  recognizer.onUpdate = (_) {};
                  recognizer.onEnd = (_) {};
                },
              ),
        },
        child: const SizedBox.expand(),
      ),
    );

    testWidgets('a drag that changed something marks its pointer, and lets '
        'it go with the pointer', (tester) async {
      var stepped = false;
      await tester.pumpWidget(pan(stepped: () => stepped));
      final gesture = await tester.startGesture(
        const Offset(100, 100),
        pointer: pointer,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(4, 0));
      expect(
        pointerDragTookAStep(pointer),
        isFalse,
        reason: 'the pan has started — a mouse\'s does at a pixel — and '
            'nothing has changed: still a click',
      );

      stepped = true;
      await gesture.moveBy(const Offset(4, 0));
      expect(pointerDragTookAStep(pointer), isTrue);

      await gesture.up();
      expect(
        pointerDragTookAStep(pointer),
        isFalse,
        reason: 'a mark that outlived its pointer would be a leak',
      );
    });
  });
}
