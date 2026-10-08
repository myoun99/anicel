// THE SHORTCUTS EDITOR: THE SEARCH NARROWS THE LIST, RECORD CAPTURES THE
// NEXT KEY AS THE ACTION'S ONLY BINDING, AND RESET ALL PUTS THE DEFAULTS
// BACK.
//
// No test named this dialog (audit 2026-09-03). These pins drive it as a
// user does, on bindings with no store behind them.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_settings_dialog.dart';
import 'package:anicel/src/ui/shortcuts/touch_shortcuts.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

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

  // F-230: the touch column picks from the shared list, 「없음」 first.
  testWidgets('a touch gesture is picked from the list, and 「none」 unbinds '
      'it', (tester) async {
    final bindings = await pump(tester);
    final id = bindings.definitions.first.id;
    final trigger = find.byKey(ValueKey<String>('shortcut-touch-$id'));

    Future<void> pick(String row) async {
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>('shortcut-touch-$id-$row')));
      await tester.pumpAndSettle();
    }

    final other = TouchGesture.values.firstWhere(
      (gesture) => gesture != bindings.touchGestureFor(id),
    );
    await pick(other.name);
    expect(bindings.touchGestureFor(id), other);
    await pick('none');
    expect(bindings.touchGestureFor(id), isNull);
  });

  // 🗣️F-318 (유저 2026-10-08): 「동일한 단축키 있을때 빨간 경고메시지가 영어로
  // 뜨고, 단축키 할당 해제 버튼같은게 없음」.
  group('🚨F-318', () {
    // A key no action ships with — a clash made here is these two rows'.
    const spare = SingleActivator(LogicalKeyboardKey.f20);
    final banner = find.byKey(
      const ValueKey<String>('shortcut-conflict-banner'),
    );
    final list = find.byKey(const ValueKey<String>('shortcut-action-list'));

    /// Whether the warning is SHOWN — its line is laid out either way.
    bool warns(WidgetTester tester) => tester
        .widget<Visibility>(
          find.ancestor(of: banner, matching: find.byType(Visibility)),
        )
        .visible;

    void speak(AppLanguage language) {
      final before = AppText.settings.value;
      addTearDown(() => AppText.settings.value = before);
      AppText.settings.value = AppLanguageSettings(programLanguage: language);
    }

    /// The first row with a key and no touch gesture — the plainest row
    /// there is, and at the top of the list.
    String aKeyedRow(EditorShortcutBindings bindings) => bindings.definitions
        .firstWhere(
          (row) =>
              bindings.activatorsFor(row.id).isNotEmpty &&
              bindings.touchGestureFor(row.id) == null,
        )
        .id;

    /// Two rows put on one key.
    (String, String) clash(EditorShortcutBindings bindings) {
      final [first, second, ...] = bindings.definitions;
      bindings
        ..setActivators(first.id, const [spare])
        ..setActivators(second.id, const [spare]);
      expect(bindings.conflictedActionIds, {first.id, second.id});
      return (first.id, second.id);
    }

    AppIconButton button(WidgetTester tester, String what, String id) =>
        tester.widget<AppIconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is AppIconButton &&
                widget.keyValue == 'shortcut-$what-$id',
          ),
        );

    Future<void> tap(WidgetTester tester, String what, String id) async {
      await tester.tap(find.byKey(ValueKey<String>('shortcut-$what-$id')));
      await tester.pump();
    }

    for (final language in AppLanguage.values) {
      testWidgets('the warning for a shared key speaks the program language '
          '(${language.name}) — and its line is there before any key '
          'clashes, so the list does not move when it shows', (tester) async {
        speak(language);
        final bindings = await pump(tester);
        expect(warns(tester), isFalse, reason: 'nothing to warn of yet');
        expect(banner, findsOneWidget, reason: 'and its place is kept');
        final listBefore = tester.getRect(list);
        final lineBefore = tester.getRect(banner);
        expect(lineBefore.height, greaterThan(0));

        clash(bindings);
        await tester.pump();

        expect(warns(tester), isTrue);

        final words = AppStrings.of(language).shortcutConflictBanner;
        expect(tester.widget<Text>(banner).data, words);
        if (language != AppLanguage.en) {
          expect(
            words,
            isNot(AppStrings.of(AppLanguage.en).shortcutConflictBanner),
            reason: '⛔premise: the table has this language\'s sentence',
          );
        }
        expect(tester.getRect(banner), lineBefore);
        expect(tester.getRect(list), listBefore);
      });
    }

    testWidgets('a row\'s key is taken off by its own button — its default '
        'too — and the reset beside it brings the default back', (
      tester,
    ) async {
      final bindings = await pump(tester);
      final id = aKeyedRow(bindings);
      final defaults = [
        for (final activator in bindings.activatorsFor(id)) activator.trigger,
      ];
      final row = find.byKey(ValueKey<String>('shortcut-row-$id'));
      expect(
        find.descendant(of: row, matching: find.byType(Chip)),
        findsWidgets,
        reason: '⛔premise: the row shows its key',
      );
      expect(button(tester, 'reset', id).onPressed, isNull, reason: '⛔premise');

      await tap(tester, 'unassign', id);

      expect(bindings.activatorsFor(id), isEmpty);
      expect(
        bindings.isOverridden(id),
        isTrue,
        reason: '「no key」 is an answer the bindings keep',
      );
      expect(
        find.descendant(of: row, matching: find.byType(Chip)),
        findsNothing,
      );
      expect(
        button(tester, 'unassign', id).onPressed,
        isNull,
        reason: 'nothing left to take off',
      );

      await tap(tester, 'reset', id);
      expect(
        [for (final activator in bindings.activatorsFor(id)) activator.trigger],
        defaults,
      );
      expect(button(tester, 'unassign', id).onPressed, isNotNull);
    });

    testWidgets('taking the key off ends a recording under way for that row', (
      tester,
    ) async {
      final bindings = await pump(tester);
      final id = aKeyedRow(bindings);
      final hint = find.byKey(
        const ValueKey<String>('shortcut-recording-hint'),
      );
      await tap(tester, 'record', id);
      expect(hint, findsOneWidget, reason: '⛔premise');

      await tap(tester, 'unassign', id);

      expect(hint, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pump();
      expect(bindings.activatorsFor(id), isEmpty, reason: 'nothing recorded');
    });

    testWidgets('a clash ends when one of its rows gives the key up', (
      tester,
    ) async {
      final bindings = await pump(tester);
      final (kept, given) = clash(bindings);
      await tester.pump();
      expect(warns(tester), isTrue, reason: '⛔premise');

      await tap(tester, 'unassign', given);

      expect(warns(tester), isFalse);
      expect(bindings.conflictedActionIds, isEmpty);
      expect(bindings.activatorsFor(kept).single.trigger, spare.trigger);
    });

    testWidgets('the button says what it does in the program language', (
      tester,
    ) async {
      speak(AppLanguage.ko);
      final bindings = await pump(tester);
      expect(
        button(tester, 'unassign', aKeyedRow(bindings)).tooltip,
        AppStrings.of(AppLanguage.ko).shortcutUnassign,
      );
    });
  });
}
