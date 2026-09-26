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
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';
import '../helpers/project_scratch_folder.dart';

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
    deleteAfterSessionEnds(directory);
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

  // 🪦The SESSION round-trip lived here — persist through the injected
  // store, restore on construction — and it raced its own save: it gave the
  // fire-and-forget write a fixed 50 ms and failed under a bulk run
  // (2026-09-24; it passed alone). It also never reset the app-wide value
  // the first session had set, so it passed with the restore switched off —
  // measured: that mutant stayed green here and went red in the sibling.
  // `editor_app_settings_test` takes the same round-trip for every family,
  // language included, waiting on the files and resetting in between.
  // ⛔Do not bring a second copy back.

  test('the sheet header labels follow the notation language', () {
    expect(
      TimesheetDocumentPainter.headerFieldLabel(
        TimesheetHeaderField.episode,
        timesheetWordsIn(AppLanguage.ja),
      ),
      '話数',
    );
    // UI-R11 #4: the user's studio wording — タイトル/タイム/原画/シート.
    expect(
      TimesheetDocumentPainter.headerFieldLabel(
        TimesheetHeaderField.title,
        timesheetWordsIn(AppLanguage.ja),
      ),
      'タイトル',
    );
    expect(
      TimesheetDocumentPainter.headerFieldLabel(
        TimesheetHeaderField.time,
        timesheetWordsIn(AppLanguage.ja),
      ),
      'タイム',
    );
    expect(
      TimesheetDocumentPainter.headerFieldLabel(
        TimesheetHeaderField.name,
        timesheetWordsIn(AppLanguage.ja),
      ),
      '原画',
    );
    expect(
      TimesheetDocumentPainter.headerFieldLabel(
        TimesheetHeaderField.sheet,
        timesheetWordsIn(AppLanguage.ja),
      ),
      'シート',
    );
    expect(timesheetWordsIn(AppLanguage.ja).hold, '止め');
    // The English table keeps the reference forms' wording.
    expect(
      TimesheetDocumentPainter.headerFieldLabel(
        TimesheetHeaderField.episode,
        timesheetWordsIn(AppLanguage.en),
      ),
      'Ep.no',
    );
    expect(timesheetWordsIn(AppLanguage.ja).repeat, 'リピート');
    expect(timesheetWordsIn(AppLanguage.ko).repeat, '리피트');
  });

  testWidgets('the section switches the notation language on the session', (
    tester,
  ) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    // The section itself, as the Preferences dialog mounts it (SAVE-1).
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LanguageSettingsSection(session: session)),
      ),
    );
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
