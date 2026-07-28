import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/services/persistence/app_language_settings_store.dart';
import 'package:anicel/src/ui/dialogs/language_settings_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_notation.dart';

/// UI-R10 #7: TWO language settings — program (app chrome) and notation
/// (what prints on submissions). Defaults: program=en, notation=ja.
void main() {
  // The languages are an APP-WIDE setting (AppText), not per-session, so
  // each test starts from the product defaults rather than inheriting
  // whatever the previous one selected.
  setUp(() => AppText.settings.value = const AppLanguageSettings());

  test('defaults: program English, notation Japanese', () {
    const settings = AppLanguageSettings();
    expect(settings.programLanguage, AppLanguage.en);
    expect(settings.notationLanguage, AppLanguage.ja);
  });

  test('the store round-trips both settings', () async {
    final directory = await Directory.systemTemp.createTemp('qa-lang');
    addTearDown(() => directory.delete(recursive: true));
    final store = AppLanguageSettingsStore(
      filePath: '${directory.path}/language_settings.json',
    );

    expect(await store.load(), isNull, reason: 'missing file = defaults');

    const settings = AppLanguageSettings(
      programLanguage: AppLanguage.ko,
      notationLanguage: AppLanguage.fr,
    );
    await store.save(settings);
    expect(await store.load(), settings);
  });

  test('the session persists changes through the injected store and '
      'restores them on construction', () async {
    final directory = await Directory.systemTemp.createTemp('qa-lang');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/language_settings.json';

    final first = EditorSessionManager(
      initialProject: createDefaultProject(),
      languageSettingsStore: AppLanguageSettingsStore(filePath: path),
    );
    first.setLanguageSettings(
      const AppLanguageSettings(
        programLanguage: AppLanguage.ja,
        notationLanguage: AppLanguage.en,
      ),
    );
    // The save is fire-and-forget; give it a beat.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    first.dispose();

    final second = EditorSessionManager(
      initialProject: createDefaultProject(),
      languageSettingsStore: AppLanguageSettingsStore(filePath: path),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(second.languageSettings.value.programLanguage, AppLanguage.ja);
    expect(second.languageSettings.value.notationLanguage, AppLanguage.en);
    second.dispose();
  });

  test('the sheet header labels follow the notation language', () {
    expect(
      TimesheetDocumentPainter.headerFieldLabel(
        TimesheetHeaderField.episode,
        TimesheetNotation.of(AppLanguage.ja),
      ),
      '話数',
    );
    // UI-R11 #4: the user's studio wording — タイトル/タイム/原画/シート.
    expect(
      TimesheetDocumentPainter.headerFieldLabel(
        TimesheetHeaderField.title,
        TimesheetNotation.of(AppLanguage.ja),
      ),
      'タイトル',
    );
    expect(
      TimesheetDocumentPainter.headerFieldLabel(
        TimesheetHeaderField.time,
        TimesheetNotation.of(AppLanguage.ja),
      ),
      'タイム',
    );
    expect(
      TimesheetDocumentPainter.headerFieldLabel(
        TimesheetHeaderField.name,
        TimesheetNotation.of(AppLanguage.ja),
      ),
      '原画',
    );
    expect(
      TimesheetDocumentPainter.headerFieldLabel(
        TimesheetHeaderField.sheet,
        TimesheetNotation.of(AppLanguage.ja),
      ),
      'シート',
    );
    expect(TimesheetNotation.of(AppLanguage.ja).hold, '止め');
    // The default stays the reference forms' English wording.
    expect(
      TimesheetDocumentPainter.headerFieldLabel(TimesheetHeaderField.episode),
      'Ep.no',
    );
    expect(TimesheetNotation.of(AppLanguage.ja).repeat, 'リピート');
    expect(TimesheetNotation.of(AppLanguage.ko).repeat, '리피트');
  });

  testWidgets('the dialog switches the notation language on the session', (
    tester,
  ) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showLanguageSettingsDialog(context, session: session),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings-program-language')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-notation-language')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(
      session.languageSettings.value.notationLanguage,
      AppLanguage.en,
    );
    expect(
      session.languageSettings.value.programLanguage,
      AppLanguage.en,
      reason: 'the program language stays untouched',
    );
  });
}
