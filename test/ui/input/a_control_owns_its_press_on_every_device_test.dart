import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// 🚨★★★A PRESS THAT LANDS ON A CONTROL IS THAT CONTROL'S — ON EVERY DEVICE.
///
/// 유저 2026-08-29: 「펜/마우스/터치를 스크롤 경쟁을 완벽하게 해결. 즉 셋
/// 다 취급 통일하고 슬라이더에 대한 조작은 슬라이더만 조작하게하고
/// **스크롤 애초에 발동안하도록** 이런거를 앱 전체에 적용」.
///
/// The law was half-built. `ControlPressClaim` took a claim and
/// `EagerPanGestureRecognizer` honoured it — but a `Scrollable`'s own drag
/// recogniser asks nobody, so a drag that began on a button still scrolled
/// the list under it. Which devices could do that was a device rule, and a
/// device rule only moves the problem: 유저 「조작이 스크롤러 안에서 전부
/// 스크롤 경쟁자를 갖고있는거는 펜에서 애초에 지금 존재하는거일꺼아니야.
/// **그게 싫다니까?**」
///
/// So the answer stopped being about devices: the claim now takes the arena
/// on the FIRST MOVEMENT, which beats any ancestor scroller's slop.
void main() {
  tearDown(debugClearValueControlPointers);

  Future<ScrollController> pumpList(
    WidgetTester tester, {
    required Widget Function(Widget child) wrap,
  }) async {
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
                wrap(
                  // ⚠️OPAQUE, and that is not decoration: an empty
                  // `ColoredBox` is not hit-testable, so a `deferToChild`
                  // claim above it is never offered the pointer and the
                  // whole case would measure nothing. Real controls are
                  // buttons and are hittable; the fixture has to be too.
                  const Listener(
                    key: ValueKey<String>('control'),
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(height: 60),
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
    return list;
  }

  Future<double> dragFromControl(
    WidgetTester tester,
    ScrollController list,
    PointerDeviceKind kind,
  ) async {
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>('control'))),
      kind: kind,
    );
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final moved = list.offset;
    await g.up();
    await tester.pumpAndSettle();
    return moved;
  }

  for (final kind in const [
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.mouse,
  ]) {
    testWidgets('${kind.name}: a drag that STARTS ON A CONTROL never '
        'scrolls the list under it', (tester) async {
      final list = await pumpList(
        tester,
        wrap: (child) => ControlPressClaim(child: child),
      );
      expect(
        list.position.maxScrollExtent,
        greaterThan(0),
        reason: 'the list must be able to scroll, or this proves nothing',
      );

      expect(
        await dragFromControl(tester, list, kind),
        0,
        reason:
            '유저: 「터치 좌표가 버튼인데 거기서 움직였다고 스크롤이 '
            '발생하는게 심각한 버그야」 — and it must be the same answer '
            'for ${kind.name} as for the other two',
      );
    });

    testWidgets('${kind.name}: the SAME drag off the control scrolls', (
      tester,
    ) async {
      // ⛔The control. Without this a claim that swallowed everything would
      // pass the case above — including the day it swallows the whole panel.
      //
      // 🚨THE MOUSE IS NO LONGER EXEMPT (유저 확정 2026-08-30). It spent a
      // round out of `dragDevices` because Flutter hardcodes a mouse to a
      // ONE PIXEL drag threshold, so a scrollable that took mouse drags ate
      // every click that wobbled. That is fixed at the root instead of by
      // keeping the device out: a claimed control no longer needs to win a
      // tap, so it can take the arena at one pixel too.
      final list = await pumpList(tester, wrap: (child) => child);
      expect(
        await dragFromControl(tester, list, kind),
        greaterThan(0),
        reason:
            'every device drags to scroll off a control, and the claim '
            'above is what keeps that from starting ON one',
      );
    });
  }

  testWidgets('🚨a control with a drag VERB of its own is not swallowed', (
    tester,
  ) async {
    // The strong claim marks 「a drag from here IS this thing's verb」 (a
    // swipe column, a slider). Absorbing there would kill the gesture the
    // strong claim exists to protect, so the absorbing recognisers decline
    // exactly that pointer — and the order works out because pointer-down
    // dispatch is deepest-first.
    final list = await pumpList(
      tester,
      wrap: (child) => ControlPressClaim(
        child: Listener(
          onPointerDown: (event) => claimPointerForValueControl(event.pointer),
          onPointerUp: (event) => releasePointerForValueControl(event.pointer),
          onPointerCancel: (event) =>
              releasePointerForValueControl(event.pointer),
          child: child,
        ),
      ),
    );

    expect(
      await dragFromControl(tester, list, PointerDeviceKind.touch),
      greaterThan(0),
      reason:
          'the strong claim means the drag belongs to something REAL; the '
          'weak claim must stand down for it, or a swipe column can never '
          'run again',
    );
  });

  testWidgets('🚨a REAL shared button outside the chrome list holds its '
      'press through Material, Tooltip and all', (tester) async {
    // The fixture above proves the MECHANISM on a bare `Listener`. This
    // proves the law survives a real widget's own tree — [PanelFlyoutButton]
    // is the app's shared menu button and it wraps its ink in a `Material`
    // and a `Tooltip`, either of which could have swallowed the claim.
    //
    // ⛔It is also a button the hand-kept `chrome` list never named. Panels,
    // dialogs and the export screens were all 「deliberately NOT here」 until
    // 유저 2026-08-30: 「그 외 버튼도 싹 다 확인이야」.
    //
    // ⚠️All three devices, and each one measures something: every
    // one of them drag-scrolls off a control now, so a zero here is the
    // claim doing its job rather than the device being absent.
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
                PanelFlyoutButton(
                  key: const ValueKey<String>('control'),
                  label: 'Menu',
                  entriesBuilder: () => const <PanelFlyoutItem>[],
                ),
                for (var i = 0; i < 8; i++) const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final kind in const [
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
      PointerDeviceKind.mouse,
    ]) {
      expect(
        await dragFromControl(tester, list, kind),
        0,
        reason:
            '${kind.name}: 「터치 좌표가 버튼인데 거기서 움직였다고 '
            '스크롤이 발생하는게 심각한 버그야」',
      );
      expect(list.offset, 0, reason: 'and it did not fling either');
    }
  });
}
