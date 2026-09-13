import 'package:flutter/foundation.dart';
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
    LogicalKeyboardKey key = LogicalKeyboardKey.digit1,
    bool control = false,
    bool meta = false,
  }) async {
    var fired = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Shortcuts.manager(
          manager: EditorShortcutManager(
            shortcuts: <ShortcutActivator, Intent>{
              SingleActivator(key, control: control, meta: meta):
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
    final modifier = meta
        ? LogicalKeyboardKey.metaLeft
        : (control ? LogicalKeyboardKey.controlLeft : null);
    if (modifier != null) {
      await tester.sendKeyDownEvent(modifier);
    }
    await tester.sendKeyEvent(key);
    if (modifier != null) {
      await tester.sendKeyUpEvent(modifier);
    }
    await tester.pumpAndSettle();
    return fired;
  }

  const field = TextField(key: ValueKey<String>('probe-field'), autofocus: true);

  // 🚨I-19 binds Ctrl+C/V/X to the timeline's clipboard. The case below says
  // a modified key 「the field itself owns (Ctrl+Z)」 is 「consumed below us」
  // — and that was never how the tree is built: this manager sits BETWEEN
  // the field and the app's text-editing shortcuts, so it hears the key
  // first. Measured here, the way the user would meet it: Ctrl+C in a
  // rename box copying a FRAME.
  for (final key in const [
    LogicalKeyboardKey.keyC,
    LogicalKeyboardKey.keyV,
    LogicalKeyboardKey.keyX,
    LogicalKeyboardKey.keyZ,
  ]) {
    testWidgets('Ctrl+${key.keyLabel} in a TextField stays the field\'s', (
      tester,
    ) async {
      expect(
        await firesWhile(tester, body: field, key: key, control: true),
        0,
        reason: 'the field\'s own text shortcut binds this key, so the field '
            'keeps it',
      );
    });
  }

  testWidgets('…and on a Mac the field keeps ⌘C, the key ITS table binds', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      expect(
        await firesWhile(
          tester,
          body: field,
          key: LogicalKeyboardKey.keyC,
          meta: true,
        ),
        0,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

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
      reason: 'Ctrl+key is not something anyone types INTO a field; only the '
          'keys the field\'s own text shortcuts bind stay with it (below)',
    );
  });
}
