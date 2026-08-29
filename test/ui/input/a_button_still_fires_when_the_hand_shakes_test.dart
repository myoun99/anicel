import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';

/// 🚨★★★A CLICK THAT MOVES A PIXEL IS STILL A CLICK.
///
/// 유저 2026-08-30: 「지금 버튼이 펜이랑 마우스 조작이 바꼈어. 터치는 잘 버튼
/// 다 눌리는데 **펜마우스만 그자리에서 손떼야 작동함**」.
///
/// [ControlPressClaim] mounts absorbing drag recognisers so a drag that
/// starts on a control never scrolls the list under it. They were built on
/// the SLIDER's recogniser, whose `hasSufficientGlobalDistanceToAccept`
/// returns true — it takes the arena on the FIRST movement, because for a
/// slider the drag IS the verb and there is no tap to protect.
///
/// ⛔A button is the opposite case. Winning the arena at one pixel kills the
/// tap, and a mouse or pen almost always emits a move between down and up
/// while a clean finger tap emits none — which is exactly why the user saw
/// touch working and the other two not.
///
/// ⇒ The weak claim accepts at the NORMAL slop, which is where the tap has
/// given up anyway. It still beats the ancestor scroller, because pointer
/// dispatch is deepest-first and the arena awards a tie to the member added
/// first.
void main() {
  Future<({int taps, ScrollController list})> pump(
    WidgetTester tester, {
    required bool claimed,
  }) async {
    var taps = 0;
    final list = ScrollController();
    addTearDown(list.dispose);
    Widget button = SizedBox(
      height: 60,
      child: Material(
        child: InkWell(
          key: const ValueKey<String>('button'),
          onTap: () => taps += 1,
          child: const SizedBox.expand(),
        ),
      ),
    );
    if (claimed) {
      button = ControlPressClaim(child: button);
    }
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            height: 200,
            child: ListView(
              controller: list,
              children: [
                button,
                for (var i = 0; i < 8; i++) const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (taps: taps, list: list);
  }

  /// A press, a shake no bigger than a hand resting on a mouse, a release in
  /// roughly the same place.
  Future<void> shakyClick(WidgetTester tester, PointerDeviceKind kind) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>('button'))),
      kind: kind,
    );
    await gesture.moveBy(const Offset(0, 2));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -1));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  for (final kind in const [
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.touch,
  ]) {
    testWidgets('${kind.name}: a 2px shake does not eat the tap', (
      tester,
    ) async {
      var taps = 0;
      final list = ScrollController();
      addTearDown(list.dispose);
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              height: 200,
              child: ListView(
                controller: list,
                children: [
                  ControlPressClaim(
                    child: SizedBox(
                      height: 60,
                      child: Material(
                        child: InkWell(
                          key: const ValueKey<String>('button'),
                          onTap: () => taps += 1,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                  for (var i = 0; i < 8; i++) const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await shakyClick(tester, kind);

      expect(
        taps,
        1,
        reason:
            '유저: 「펜마우스만 그자리에서 손떼야 작동함」 — a click is not '
            'required to be perfectly still',
      );
      expect(
        list.offset,
        0,
        reason:
            'and the claim still does its job: the shake did not scroll the '
            'list either',
      );
    });
  }

  testWidgets('🚨a REAL drag from the button still scrolls nothing', (
    tester,
  ) async {
    // ⛔The control for the fix: raising the threshold must not give the
    // scroller back the drags this claim exists to absorb.
    final pumped = await pump(tester, claimed: true);
    expect(pumped.list.position.maxScrollExtent, greaterThan(0));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>('button'))),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 6; i += 1) {
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      pumped.list.offset,
      0,
      reason:
          '유저 (3회): 「터치 좌표가 버튼인데 거기서 움직였다고 스크롤이 '
          '발생하는게 심각한 버그야」',
    );
  });
}
