import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/owning_axis_grip.dart';

/// 🚨★★★**A PRESS THAT LANDS ON A GRIP BELONGS TO THAT GRIP — SCROLLING
/// INCLUDED.**
///
/// 🗣️유저 2026-08-14, 확정·⛔재론 금지: 「**슬라이더위에서 조작하기
/// 시작하면 슬라이더조작하는거고 그 외가 스크롤인거야**」. And again on
/// 2026-09-18 (F-163), on a block edge: 「프레임블록 엣지 클릭한채로
/// **세로이동하면 세로스크롤 작동함** … 저번에 말한대로 버튼은 절대 밖으로
/// 제스쳐 새지않음. **해당 법 재사용/통일해서** 엣지에서 클릭시작하면
/// 새지않도록」.
///
/// ⛔**THE WALKOVER IS THE WHOLE POINT, so the drag here is ACROSS the
/// grip's own axis.** A horizontal grip pulled straight down moves 0 along
/// its axis, so a threshold on |dx| can never be crossed and the scroller
/// wins without a race. That is why the recogniser accepts on the FIRST
/// movement rather than at a distance — 유저 2026-08-30 had every px
/// comparison taken out of this decision.
void main() {
  Future<ScrollController> pumpGripInAScroller(
    WidgetTester tester, {
    required Axis axis,
    required List<String> log,
  }) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: ListView(
              controller: controller,
              children: [
                const SizedBox(height: 80),
                Center(
                  child: OwningAxisGrip(
                    axis: axis,
                    configure: (recognizer) {
                      recognizer
                        ..dragStartBehavior = DragStartBehavior.down
                        ..onStart = ((_) {
                          log.add('start');
                        })
                        ..onUpdate = ((details) {
                          log.add('move ${details.primaryDelta}');
                        });
                    },
                    child: const SizedBox(
                      key: ValueKey<String>('grip'),
                      width: 40,
                      height: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> dragOn(WidgetTester tester, Offset by) async {
    final grip = find.byKey(const ValueKey<String>('grip'));
    final gesture = await tester.startGesture(
      tester.getCenter(grip),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    for (var i = 0; i < 6; i += 1) {
      await gesture.moveBy(by);
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('🚨a drag ACROSS a horizontal grip does not scroll the list '
      'under it', (tester) async {
    final log = <String>[];
    final controller = await pumpGripInAScroller(
      tester,
      axis: Axis.horizontal,
      log: log,
    );
    final before = controller.offset;

    await dragOn(tester, const Offset(0, -12));

    expect(
      controller.offset,
      before,
      reason:
          '🚨유저: 「엣지 클릭한채로 세로이동하면 세로스크롤 작동함」 — the '
          'press landed on the grip, so the scroller never had it',
    );
    expect(
      log,
      isNotEmpty,
      reason: '⛔and the grip HELD it: 「you are operating this grip now」',
    );
  });

  testWidgets('⛔and the value still follows the grip\'s OWN axis only', (
    tester,
  ) async {
    // The other half of 「you are operating this grip now」: holding the
    // pointer is not the same as moving the value. A cross-axis drag
    // reports zero along the axis, so nothing changes — and that is not a
    // direction TEST, it is what `primaryDelta` already means.
    final log = <String>[];
    await pumpGripInAScroller(tester, axis: Axis.horizontal, log: log);

    await dragOn(tester, const Offset(0, -12));
    final moved = log.where((line) => line.startsWith('move ')).toList();
    expect(moved, isNotEmpty, reason: '⛔전제: the grip heard the drag');
    for (final line in moved) {
      expect(
        line,
        'move 0.0',
        reason: 'a cross-axis pull holds the grip and changes nothing',
      );
    }
  });

  testWidgets('⛔a press that is NOT on the grip still scrolls', (
    tester,
  ) async {
    // 🚨THE CONTROL. 유저's law has two halves — 「슬라이더위에서 … 그 외가
    // 스크롤인거야」 — and without this one the pin would pass on a build
    // that had simply broken scrolling.
    final log = <String>[];
    final controller = await pumpGripInAScroller(
      tester,
      axis: Axis.horizontal,
      log: log,
    );
    final before = controller.offset;

    // ⚠️Aimed BELOW the grip, not at the list's centre — which is where the
    // grip sits, so `drag(find.byType(ListView))` would have pressed the
    // very thing this control exists to avoid.
    final grip = tester.getRect(find.byKey(const ValueKey<String>('grip')));
    final gesture = await tester.startGesture(
      grip.bottomCenter + const Offset(0, 60),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    for (var i = 0; i < 6; i += 1) {
      await gesture.moveBy(const Offset(0, -14));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      controller.offset,
      greaterThan(before),
      reason: '그 외는 스크롤이다',
    );
    expect(log, isEmpty, reason: '⛔and the grip heard nothing');
  });
}
