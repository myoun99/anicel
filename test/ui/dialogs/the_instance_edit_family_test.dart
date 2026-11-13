import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/dialogs/instance_edit_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// The instance-edit family's window — named by no test until 2026-09-05.
/// Its camera kind went with the camera's own key window (F-17,
/// 2026-09-11): the camera row edits its keys in the common key window.
///
/// 🚨The shell owns no chrome: what it holds is what the FAMILY shares —
/// the stable action keys every kind's tests and muscle memory rely on,
/// the optional Delete, and the preview slot below the fields.
void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    Widget? preview,
    VoidCallback? onSubmit,
    VoidCallback? onDelete,
    bool keepDefault = true,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InstanceEditDialogShell(
          title: 'Edit',
          body: const Text('fields'),
          preview: preview,
          onSubmit: keepDefault ? (onSubmit ?? () {}) : onSubmit,
          onDelete: onDelete,
        ),
      ),
    ),
  );

  group('the shell', () {
    testWidgets('🚨the action keys are STABLE across every kind — tests and '
        'muscle memory both rely on them', (tester) async {
      await pumpShell(tester);

      expect(
        find.byKey(const ValueKey<String>('instance-edit-dialog')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('instance-edit-ok-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('instance-edit-cancel-button')),
        findsOneWidget,
      );
    });

    /// 🗣️F-584 (유저 2026-11-12): 「이름 저장이아니라 확인이 맞지않나」;
    /// F-584-Q1 (유저 2026-11-13): 「블록 편집 창 둘 (SE · 지시)」 — the two
    /// wear this one shell, and the windows that write settings their Save.
    testWidgets('its primary button says the block is taken as written, in '
        'every language — not Save', (tester) async {
      addTearDown(
        () => AppText.settings.value = const AppLanguageSettings(),
      );
      final primary = find.byKey(
        const ValueKey<String>('instance-edit-ok-button'),
      );
      const words = {
        AppLanguage.en: 'OK',
        AppLanguage.ja: 'OK',
        AppLanguage.ko: '확인',
        AppLanguage.fr: 'OK',
        AppLanguage.zhHans: '确定',
      };
      expect(words.keys, AppLanguage.values);

      for (final MapEntry(key: language, value: word) in words.entries) {
        AppText.settings.value = AppLanguageSettings(programLanguage: language);
        await pumpShell(tester, onDelete: () {});
        await tester.pump();

        expect(
          find.descendant(of: primary, matching: find.text(word)),
          findsOneWidget,
          reason: '$language',
        );
        expect(find.text(AppText.strings.commonSave), findsNothing);
      }
    });

    testWidgets('⛔DELETE appears only when the kind offers one', (
      tester,
    ) async {
      await pumpShell(tester);
      expect(
        find.byKey(const ValueKey<String>('instance-edit-delete-button')),
        findsNothing,
      );

      await pumpShell(tester, onDelete: () {});
      expect(
        find.byKey(const ValueKey<String>('instance-edit-delete-button')),
        findsOneWidget,
      );
    });

    testWidgets('a null onSubmit DISABLES the confirm rather than hiding it '
        '— nothing selected yet is not a reason for the button to vanish', (
      tester,
    ) async {
      await pumpShell(tester, onSubmit: null, keepDefault: false);

      expect(
        find.byKey(const ValueKey<String>('instance-edit-ok-button')),
        findsOneWidget,
        reason: 'still there',
      );

      var submits = 0;
      await pumpShell(tester, onSubmit: () => submits += 1);
      await tester.tap(
        find.byKey(const ValueKey<String>('instance-edit-ok-button')),
      );
      await tester.pumpAndSettle();
      expect(submits, 1, reason: 'and live when there is something to save');
    });

    testWidgets('the preview slot is HIDDEN when the kind has none — an '
        'empty pane is not a preview', (tester) async {
      await pumpShell(tester);
      expect(find.text('a preview'), findsNothing);

      await pumpShell(tester, preview: const Text('a preview'));
      expect(find.text('a preview'), findsOneWidget);
    });
  });
}
