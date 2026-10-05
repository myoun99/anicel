import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';

/// 🗣️F-241 (유저 2026-09-29): 「컨트롤 좌우 화살표 … 됏다가 안됏다가
/// 이상함」, and F-241-Q1: not the X-sheet — 「가로 타임라인에서
/// 안먹혓음」. So the inspector follows a key: that it ARRIVED (`key`,
/// with what the app believes is held and where focus is), what the
/// shortcut table ANSWERED (`bind`), and whether playback SPENT it on a stop
/// (`eat`) — each line stamped with the key's own time, so a screenshot of
/// the failing press says where it went.
///
/// ONE editor for the whole walk: a full-app pump is seconds, and every step
/// here reads the same editor (09-29: 「그런 테스트 하나하나가 느리게」).
void main() {
  tearDown(InputInspector.reset);

  String stampOf(String line, String key) =>
      RegExp('@\\d+ $key').firstMatch(line)!.group(0)!;

  testWidgets('the inspector follows a key to where it went — arrived, '
      'answered or unbound, spent on a stop — and writes nothing hidden', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    InputInspector.visible.value = true;
    await tester.pump();

    // Arrived and answered: one stamp, with the modifier the app holds.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final key = InputInspector.notes['key']!;
    expect(
      key,
      contains(RegExp(r'held \[Control Left, Key Z\]')),
      reason: 'read as it ARRIVES — the key itself down, with the modifier '
          'the app believes is held',
    );
    expect(key, contains('focus'));
    expect(
      InputInspector.notes['bind'],
      allOf(contains(EditorActionIds.undo), contains(stampOf(key, 'Key Z'))),
      reason: 'the answer pairs with the key it answers',
    );

    // Unbound: J binds nothing by default (↩️it was Q, the onion skin's
    // since F-261).
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    expect(InputInspector.notes['bind'], contains('no binding'));

    // Hidden: nothing is written.
    InputInspector.visible.value = false;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(InputInspector.notes['bind'], contains('Key J'));
    InputInspector.visible.value = true;
    await tester.pump();

    // Spent on a stop: the table never hears it.
    await tester.tap(
      find.byKey(const ValueKey<String>('playback-play-button')),
    );
    for (var i = 0; i < 4; i += 1) {
      await tester.pump(const Duration(milliseconds: 42));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    final eat = InputInspector.notes['eat']!;
    expect(eat, contains('stopped playback'));
    expect(
      InputInspector.notes['bind'],
      isNot(contains(stampOf(eat, 'Key E'))),
      reason: 'a stop is the whole of that press — no action answers it',
    );

    // 🗣️F-232 (유저 2026-10-02): 「언두 안먹는다는거 … 가능하면 근본/구조적
    // 으로 해결해줘」. An undo that does nothing says so, and the census says
    // which contact it was refused for — the press that never lifts.
    expect(InputInspector.pinned['census'], 'census none');
    final held = await tester.startGesture(
      const Offset(700, 400),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(
      InputInspector.pinned['census'],
      matches(r'^census mouse#\d+ \+\d+\.\ds$'),
    );
    expect(InputInspector.notes['gate'], isNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      InputInspector.notes['gate'],
      'gate undo refused → a contact is down',
    );

    await held.up();
    await tester.pump();
    expect(InputInspector.pinned['census'], 'census none');
  });
}
