import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/input/control_press_claim.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';

/// 🚨★★★A CLICK THAT MOVES A PIXEL IS STILL A CLICK — AND IT IS NEVER A
/// SCROLL.
///
/// 유저 확정 2026-08-30 (board `press-fires-outside-the-arena`), stated as
/// one line:
///
/// > 「**레이어 쪽 버튼은 탭다운, 헤더쪽은 손떼면**으로 충분할거같은데
/// > 맞지? 규칙 단순명쾌하게 정리했으면 하는데」
///
/// ⛔THE PREMISE THIS FILE USED TO HOLD IS GONE. It asserted that the weak
/// claim accepts at the NORMAL slop 「which is where the tap has given up
/// anyway」 — an 18px threshold that existed to keep Flutter's tap alive.
/// 유저 struck it down the same day:
///
/// > 「왜 18px 이딴규칙 설정하려고하는거지? 그게아니라 **클릭이 버튼이면
/// > 스크롤 절대 발생안하게한다**고」
///
/// The reason a threshold could never work is measured, not argued: Flutter
/// hardcodes a MOUSE to a ONE PIXEL drag threshold, so a scroller that takes
/// mouse drags wins the arena before any claim can raise its own bar — and
/// **whatever wins the arena also kills the button's tap.** So the tap stops
/// coming from the arena. [ControlPressClaim] fires the control itself, and
/// is then free to take the drag on the FIRST MOVEMENT, no distance compared
/// at all — 유저: 「1px 이동했는지 같은 px 이동으로 판단하는거 설마 아직도
/// 남아있나?」 · 「싹 깔끔하게 걷어내」.
void main() {
  setUp(debugClearValueControlPointers);
  tearDown(debugClearValueControlPointers);

  /// A claimed button at the head of a scrollable list, so every case can ask
  /// both questions at once: did it fire, and did the list move.
  ///
  /// ⚠️OPAQUE, and that is not decoration: an empty `ColoredBox` is not
  /// hit-testable, so a `deferToChild` claim above it is never offered the
  /// pointer and the whole case would measure nothing.
  Future<({List<int> fires, ScrollController list})> pump(
    WidgetTester tester, {
    PressFire fireOn = PressFire.upInside,
  }) async {
    final fires = <int>[];
    final list = ScrollController();
    addTearDown(list.dispose);
    Widget button = ControlPressClaim(
      onPressed: () => fires.add(fires.length),
      child: const Listener(
        key: ValueKey<String>('button'),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(height: 60),
      ),
    );
    if (fireOn == PressFire.down) {
      button = PressFireScope(fireOn: PressFire.down, child: button);
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
    return (fires: fires, list: list);
  }

  Offset centreOfButton(WidgetTester tester) =>
      tester.getCenter(find.byKey(const ValueKey<String>('button')));

  for (final kind in const [
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.touch,
  ]) {
    testWidgets('${kind.name}: a 2px shake is still a click, and no scroll', (
      tester,
    ) async {
      final (:fires, :list) = await pump(tester);
      final gesture = await tester.startGesture(
        centreOfButton(tester),
        kind: kind,
      );
      await gesture.moveBy(const Offset(0, 2));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, -1));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        fires,
        hasLength(1),
        reason:
            '유저: 「펜마우스만 그자리에서 손떼야 작동함」 — a hand resting '
            'on a mouse is not a drag',
      );
      expect(
        list.offset,
        0,
        reason: 'and the list under it never moved either',
      );
    });

    testWidgets('${kind.name}: released OFF the button, nothing happens', (
      tester,
    ) async {
      // 「손 뗄 때도 해당 버튼 안에서 이루어졌다면」 — so a press that
      // leaves is a press the user changed their mind about. ⛔And it is
      // still not a scroll: 「그 클릭으로서 발생하는 모든 조작은 스크롤을
      // 무시한다」.
      final (:fires, :list) = await pump(tester);
      final gesture = await tester.startGesture(
        centreOfButton(tester),
        kind: kind,
      );
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(fires, isEmpty, reason: 'the release was not inside the button');
      expect(
        list.offset,
        0,
        reason: 'and 200 pixels of drag from a control scrolled nothing at all',
      );
    });

    testWidgets('${kind.name}: wandered off and BACK still counts', (
      tester,
    ) async {
      // The question is asked at the release, not tracked over the move:
      // one instant, one answer. A finger that slides off a small button and
      // corrects itself has not cancelled anything.
      final (:fires, :list) = await pump(tester);
      final gesture = await tester.startGesture(
        centreOfButton(tester),
        kind: kind,
      );
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, -120));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(fires, hasLength(1));
      expect(list.offset, 0);
    });
  }

  testWidgets('🚨inside a swipe column the PRESS is the action', (
    tester,
  ) async {
    // 「레이어 쪽 버튼은 탭다운」. A drag down a rail column paints every row
    // it passes to match the one that was pressed, so the pressed row has to
    // be holding its new value already — the sweep has nothing to spread
    // otherwise. `PressFireScope` is the one place that says which buttons
    // those are.
    final (:fires, :list) = await pump(tester, fireOn: PressFire.down);
    final gesture = await tester.startGesture(centreOfButton(tester));
    await tester.pump();

    expect(
      fires,
      hasLength(1),
      reason: 'it acted on the way down, before anything was released',
    );

    await gesture.moveBy(const Offset(0, 200));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      fires,
      hasLength(1),
      reason: '⛔and exactly once — the release must not fire it again',
    );
    expect(list.offset, 0, reason: 'the sweep is not a scroll either');
  });

  testWidgets('⛔a cancelled gesture is not a release', (tester) async {
    // A claim that fired on cancel would act on gestures the platform took
    // away — a system back swipe, an app switch mid-press.
    final (:fires, :list) = await pump(tester);
    final gesture = await tester.startGesture(centreOfButton(tester));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(fires, isEmpty);
    expect(list.offset, 0);
  });

  testWidgets('⛔a disabled button claims its press and does nothing', (
    tester,
  ) async {
    // Null means disabled, and a dead button is STILL not a scroll surface —
    // otherwise a list would scroll from exactly the buttons that look
    // unpressable, which is the worst possible place to learn the rule.
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
                const ControlPressClaim(
                  child: Listener(
                    key: ValueKey<String>('button'),
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

    final gesture = await tester.startGesture(centreOfButton(tester));
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(list.offset, 0);
  });

  testWidgets('🚨★★★only the DEEPEST claim acts on a press', (tester) async {
    // Flutter's arena gave this away for free — one winner per pointer — and
    // firing from the raw pointer stream instead means every claim on the
    // path hears the same press. 🧪It was found a long way from here: the
    // import table's row and its cell are both claimed, so pressing a cell
    // selected the row too and the cell's own answer never landed
    // (`import_dialog_test`: 「a cell speaks for the SELECTION when its row
    // is in one」). Stated here so the next nesting does not have to.
    final fired = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: ControlPressClaim(
            onPressed: () => fired.add('row'),
            child: SizedBox(
              width: 200,
              height: 100,
              child: Row(
                children: [
                  ControlPressClaim(
                    onPressed: () => fired.add('cell'),
                    child: const Listener(
                      key: ValueKey<String>('cell'),
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox(width: 60, height: 100),
                    ),
                  ),
                  const Expanded(
                    child: Listener(
                      key: ValueKey<String>('rest-of-row'),
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox(height: 100),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('cell')));
    await tester.pumpAndSettle();
    expect(fired, [
      'cell',
    ], reason: 'the row must not answer a press that landed on its cell');

    fired.clear();
    await tester.tap(find.byKey(const ValueKey<String>('rest-of-row')));
    await tester.pumpAndSettle();
    expect(fired, [
      'row',
    ], reason: 'and the row still answers its own empty space');
  });

  testWidgets('⛔a control does not stand down for its OWN strong claim', (
    tester,
  ) async {
    // The swipe column's shape: the weak claim on the outside, the STRONG
    // one (its drag verb) inside. 🧪The first cut of 「deepest wins」 asked
    // `controlOwnsTap`, which answers yes for the strong set too — so this
    // claim saw its own [DragVerbClaim] and believed something deeper had
    // spoken for the press. Every storyboard lane twirl stopped opening
    // (`storyboard_lane_controls_test`, five cases).
    var fired = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: ControlPressClaim(
            onPressed: () => fired += 1,
            child: const DragVerbClaim(
              child: Listener(
                key: ValueKey<String>('button'),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(width: 80, height: 40),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('button')));
    await tester.pumpAndSettle();
    expect(fired, 1, reason: 'its own drag verb is not a deeper control');
  });
}
