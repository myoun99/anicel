// THE SHORTCUTS EDITOR: THE SEARCH NARROWS THE LIST, RECORD CAPTURES THE
// NEXT KEY AS THE ACTION'S ONLY BINDING, AND RESET ALL PUTS THE DEFAULTS
// BACK.
//
// No test named this dialog (audit 2026-09-03). These pins drive it as a
// user does, on bindings with no store behind them.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_settings_dialog.dart';

void main() {
  Future<EditorShortcutBindings> pump(WidgetTester tester) async {
    final bindings = EditorShortcutBindings();
    addTearDown(bindings.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShortcutSettingsDialog(bindings: bindings)),
      ),
    );
    await tester.pump();
    return bindings;
  }

  Finder recordButtons() => find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('shortcut-record-'),
  );

  testWidgets('the search narrows the list to matching actions', (
    tester,
  ) async {
    await pump(tester);
    final all = recordButtons().evaluate().length;
    expect(all, greaterThan(1));
    await tester.enterText(
      find.byKey(const ValueKey<String>('shortcut-search-field')),
      'zzzz-no-such-action',
    );
    await tester.pump();
    expect(recordButtons(), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey<String>('shortcut-search-field')),
      '',
    );
    await tester.pump();
    expect(recordButtons().evaluate().length, all);
  });

  testWidgets('recording waits past a modifier pressed alone, then takes the '
      'chord it modifies', (tester) async {
    // The same question the playback gate asks (`isModifierKey`): a key
    // that modifies another is not one to bind by itself.
    final bindings = await pump(tester);
    final id = bindings.definitions.first.id;

    await tester.tap(find.byKey(ValueKey<String>('shortcut-record-$id')));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('shortcut-recording-hint')),
      findsOneWidget,
      reason: 'Ctrl alone is not a key to bind — still recording',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final recorded = bindings.activatorsFor(id).single;
    expect(recorded.trigger, LogicalKeyboardKey.f9);
    expect(recorded.control, isTrue);
  });

  testWidgets('record captures the next key, and reset all restores', (
    tester,
  ) async {
    final bindings = await pump(tester);
    final id = bindings.definitions.first.id;
    final defaults = bindings.activatorsFor(id);

    await tester.tap(find.byKey(ValueKey<String>('shortcut-record-$id')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pump();
    // SingleActivator has no `==`: compare the trigger and the modifiers.
    final recorded = bindings.activatorsFor(id).single;
    expect(recorded.trigger, LogicalKeyboardKey.f9);
    expect(recorded.control || recorded.shift || recorded.alt, isFalse);

    await tester.tap(
      find.byKey(const ValueKey<String>('shortcut-reset-all-button')),
    );
    await tester.pump();
    expect(
      bindings.activatorsFor(id).map((a) => a.trigger),
      defaults.map((a) => a.trigger),
    );
  });
}
