import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';

/// **F-22 — a bare key belongs to the field you are typing in.**
///
/// 유저 2026-08-24: 「멤버에서 클릭해서 숫자 수동편집시 **1부터 5까지의
/// 숫자입력이 안먹히는거같음**」 — and 1…5 are five of the app's bare-key
/// shortcuts.
///
/// 🚨[EditorShortcutManager] was written for exactly this and had never
/// fired: it asked whether the primary focus context's own widget was an
/// `EditableText`, and `EditableText` builds a `Focus` around itself and
/// hands THAT node out. The comparison was false for every text field in
/// the app — so every digit typed into one ran a shortcut, and 'b' in a
/// rename dialog switched tools.
void main() {
  Future<int> firesWhile(
    WidgetTester tester, {
    required Widget body,
    bool control = false,
  }) async {
    var fired = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Shortcuts.manager(
          manager: EditorShortcutManager(
            shortcuts: <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.digit1, control: control):
                  VoidCallbackIntent(() => fired += 1),
            },
          ),
          child: Actions(
            actions: <Type, Action<Intent>>{
              VoidCallbackIntent: VoidCallbackAction(),
            },
            child: Scaffold(body: body),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (control) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    if (control) {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    await tester.pumpAndSettle();
    return fired;
  }

  testWidgets('a digit typed into a TextField runs no shortcut', (
    tester,
  ) async {
    expect(
      await firesWhile(
        tester,
        body: const TextField(
          key: ValueKey<String>('probe-field'),
          autofocus: true,
        ),
      ),
      0,
      reason: '1…5 are shortcuts AND the digits you type into a value '
          'editor; the field you are in decides',
    );
  });

  testWidgets('and with an ordinary control focused it still runs', (
    tester,
  ) async {
    expect(
      await firesWhile(
        tester,
        // Focused, and not a field. ⚠️It has to be focused at all: key
        // events dispatch from the primary focus UP, so a tree with nothing
        // focused never reaches the manager and would prove nothing.
        body: const Focus(autofocus: true, child: SizedBox.expand()),
      ),
      1,
      reason: 'the guard stands the shortcut DOWN in a field — it does not '
          'take it away',
    );
  });

  testWidgets('⛔a MODIFIED shortcut still resolves in a field', (
    tester,
  ) async {
    expect(
      await firesWhile(
        tester,
        control: true,
        body: const TextField(
          key: ValueKey<String>('probe-field'),
          autofocus: true,
        ),
      ),
      1,
      reason: 'Ctrl+key is not something anyone types INTO a field, and the '
          'ones the field itself owns (Ctrl+Z) are consumed below us',
    );
  });
}
