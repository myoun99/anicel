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
void main() {
  tearDown(InputInspector.reset);

  Future<void> openEditor(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    InputInspector.visible.value = true;
    await tester.pump();
  }

  String stampOf(String line, String key) =>
      RegExp('@\\d+ $key').firstMatch(line)!.group(0)!;

  testWidgets('a key that arrives and the answer the table gives it carry '
      'ONE stamp — with the modifier the app believes is held', (
    tester,
  ) async {
    await openEditor(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final key = InputInspector.notes['key']!;
    final bind = InputInspector.notes['bind']!;
    expect(key, contains('Arrow Right'));
    expect(key, contains('Control Left'), reason: 'what the app holds down');
    expect(key, contains('focus'));
    expect(bind, contains(EditorActionIds.frameWalkRight));
    expect(
      bind,
      contains(stampOf(key, 'Arrow Right')),
      reason: 'the answer pairs with the key it answers',
    );
  });

  testWidgets('a key the table does not bind says so', (tester) async {
    await openEditor(tester);

    // Q binds nothing by default.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pump();

    expect(InputInspector.notes['bind'], contains('no binding'));
  });

  testWidgets('a key playback spends on a stop says so, and the table never '
      'hears it', (tester) async {
    await openEditor(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('playback-play-button')),
    );
    for (var i = 0; i < 4; i += 1) {
      await tester.pump(const Duration(milliseconds: 42));
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.pump();

    final eat = InputInspector.notes['eat']!;
    expect(eat, contains('stopped playback'));
    expect(
      InputInspector.notes['bind'] ?? '',
      isNot(contains(stampOf(eat, 'Period'))),
      reason: 'a stop is the whole of that press — no action answers it',
    );
  });

  testWidgets('a hidden inspector writes nothing', (tester) async {
    await openEditor(tester);
    InputInspector.visible.value = false;
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(InputInspector.notes['key'], isNull);
    expect(InputInspector.notes['bind'], isNull);
  });
}
