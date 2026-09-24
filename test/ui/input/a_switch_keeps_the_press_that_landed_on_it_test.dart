import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
import 'package:anicel/src/ui/widgets/boolean_dot.dart';
import 'package:anicel/src/ui/widgets/settings_rows.dart';

/// 🚨★★★A PRESS THAT LANDS ON A SWITCH BELONGS TO THAT SWITCH.
///
/// The app's law, four times stated (`control_press_claim.dart` carries the
/// quotes), had reached every button and no switch: the two shared switch
/// widgets wrapped a bare Material control, so a scroller above one could
/// take the pointer — and whatever wins the arena also kills the control's
/// own tap. Settings, the export window and the import table all scroll.
///
/// 🧪**MEASURED, and only ONE DEVICE loses it: the mouse.** On the old code
/// a 2px shake toggles under a stylus and a finger and does NOT under a
/// mouse, on both widgets. Flutter hardcodes a mouse to
/// `kPrecisePointerHitSlop` — ONE pixel, ignoring the gesture settings for
/// that kind alone — so the scroller wins before the switch's own tap can,
/// while the other two kinds still have 18px of room. It is the same shape
/// 유저 reported for buttons on 2026-08-30 (「펜마우스만 그자리에서 손떼야
/// 작동함」).
///
/// ⚠️So the release-off and disabled cases below are green on the old code
/// too. They are here because the claim has to KEEP them — taking the first
/// movement is exactly what could have broken them — not because this round
/// won them.
///
/// 🚨**Answered by 유저 (board `press-law-switches`): 탭만** — pressed and
/// released on the switch toggles it, and the thumb drag Material gives a
/// switch is gone. That is the same `PressFire.upInside` every other control
/// outside a rail column already has, so the switches gain no rule of their
/// own; they stop being the exception.
///
/// ⚠️What this does NOT change is the look: a press that wobbles loses the
/// Material pressed ink, which is the standing answer on
/// `press-look-dies-on-a-wobble` (유저 `leave-it`, 2026-08-30) — 동작이
/// 우선. The toggle still lands.
void main() {
  setUp(debugClearValueControlPointers);
  tearDown(debugClearValueControlPointers);

  /// ⛔THE SCAFFOLD IS NOT DECORATION. A `Switch` asserts on a `Material`
  /// ancestor, and the first draft of this file went straight from
  /// `MaterialApp` to `Align`: every case failed, red for a build assertion
  /// instead of for the law, and the red-first run proved nothing at all.
  ///
  /// One shell for all three cases, so the fixture cannot drift between
  /// them — the switch under test at the head of a scrollable list, which
  /// is what lets each case ask both questions at once: did it toggle, and
  /// did the list move.
  Future<void> pumpListHeadedBy(
    WidgetTester tester,
    ScrollController list,
    Widget head,
  ) => tester.pumpWidget(
    MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 200,
            child: ListView(
              controller: list,
              children: [
                head,
                for (var i = 0; i < 8; i++) const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Offset centreOfSwitch(WidgetTester tester) =>
      tester.getCenter(find.byType(BooleanDot));

  /// The two shared boolean shapes, live and disabled. A round that claimed
  /// only one of them would leave the other's callers bare.
  ///
  /// ↩️They were two Material SWITCHES (`CompactSwitch` and the settings
  /// row's `SwitchListTile`) until the app's one boolean replaced them —
  /// the ring, dotted when on (guide-sym ⑥⑧; board
  /// `a-panel-with-a-switch-can-never-bake`). The law these cases hold did
  /// not change with the look.
  final shapes =
      <({String name, Widget Function(ValueChanged<bool>) live, Widget dead})>[
        (
          name: 'BooleanDotButton',
          live: _booleanDotButton,
          dead: const BooleanDotButton(
            keyValue: 'probe',
            tooltip: 'Ask',
            value: false,
            onChanged: null,
          ),
        ),
        (
          name: 'SettingsSwitchRow',
          live: _settingsSwitchRow,
          dead: const SettingsSwitchRow(
            label: 'Ask',
            value: false,
            onChanged: null,
          ),
        ),
      ];

  for (final shape in shapes) {
    for (final kind in const [
      PointerDeviceKind.mouse,
      PointerDeviceKind.stylus,
      PointerDeviceKind.touch,
    ]) {
      testWidgets(
        '${shape.name} · ${kind.name}: a 2px shake still toggles, and the '
        'list does not move',
        (tester) async {
          final changes = <bool>[];
          final list = ScrollController();
          addTearDown(list.dispose);
          await pumpListHeadedBy(tester, list, shape.live(changes.add));
          final finger = await tester.startGesture(
            centreOfSwitch(tester),
            kind: kind,
          );
          await finger.moveBy(const Offset(0, 2));
          await tester.pump();
          await finger.up();
          await tester.pumpAndSettle();
          expect(
            changes,
            <bool>[true],
            reason: 'the press landed on the switch, so the switch has it',
          );
          expect(list.offset, 0, reason: 'and it was never a scroll');
        },
      );
    }

    testWidgets('${shape.name}: a STILL click fires once, not twice', (
      tester,
    ) async {
      // ⛔THE CASE THAT CATCHES A DOUBLE FIRE. With any movement the claim
      // takes the arena and a control's own tap is rejected, so a live
      // inner callback costs nothing — both mutants that left one live
      // stayed green until this case existed. A click that does not move is
      // where Flutter's tap still gets through, and then a live control and
      // its claim both fire: the value toggles and toggles back. (The row
      // draws the ring as a GLYPH for exactly this reason — a button of its
      // own inside the row's claim would be that second fire.)
      final changes = <bool>[];
      final list = ScrollController();
      addTearDown(list.dispose);
      await pumpListHeadedBy(tester, list, shape.live(changes.add));
      await tester.tapAt(centreOfSwitch(tester));
      await tester.pumpAndSettle();
      expect(
        changes,
        <bool>[true],
        reason: 'the claim fires it, and the control under the claim is '
            'silent — two fires would land the switch back where it was',
      );
    });

    testWidgets('${shape.name}: a press released OFF it does nothing at all', (
      tester,
    ) async {
      final changes = <bool>[];
      final list = ScrollController();
      addTearDown(list.dispose);
      await pumpListHeadedBy(tester, list, shape.live(changes.add));
      final finger = await tester.startGesture(
        centreOfSwitch(tester),
        kind: PointerDeviceKind.touch,
      );
      await finger.moveBy(const Offset(0, 120));
      await tester.pump();
      await finger.up();
      await tester.pumpAndSettle();
      expect(changes, isEmpty, reason: 'released outside: no toggle');
      expect(
        list.offset,
        0,
        reason: 'and no scroll either — the press was the switch\'s from the '
            'moment it landed',
      );
    });

    testWidgets('${shape.name}: a disabled switch still keeps the press', (
      tester,
    ) async {
      final list = ScrollController();
      addTearDown(list.dispose);
      await pumpListHeadedBy(tester, list, shape.dead);
      final finger = await tester.startGesture(
        centreOfSwitch(tester),
        kind: PointerDeviceKind.touch,
      );
      await finger.moveBy(const Offset(0, 40));
      await tester.pump();
      await finger.up();
      await tester.pumpAndSettle();
      expect(
        list.offset,
        0,
        reason: 'a press on a dead control is still not a scroll',
      );
    });
  }
}

Widget _booleanDotButton(ValueChanged<bool> onChanged) => BooleanDotButton(
  keyValue: 'probe',
  tooltip: 'Ask',
  value: false,
  onChanged: onChanged,
);

Widget _settingsSwitchRow(ValueChanged<bool> onChanged) =>
    SettingsSwitchRow(label: 'Ask', value: false, onChanged: onChanged);
