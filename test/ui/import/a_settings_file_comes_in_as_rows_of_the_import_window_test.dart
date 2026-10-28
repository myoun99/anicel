import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/brush_preset_file_service.dart';
import 'package:anicel/src/services/persistence/app_accent_settings_store.dart';
import 'package:anicel/src/services/persistence/app_language_settings_store.dart';
import 'package:anicel/src/services/persistence/app_onion_skin_settings_store.dart';
import 'package:anicel/src/services/persistence/settings_file.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/import/import_file_table.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/wait_window.dart';

/// I-142-Q6 (유저 2026-10-29): 「임포트 창에 설정 파일의 행으로」 — a file of
/// every setting comes in through the window every file comes in through, a
/// row a setting (Q9), each asked one question: the settings, in place of
/// what is there (Q3 · Q7: 「지금 것은 사라집니다」), or nowhere.
void main() {
  late Directory tempDir;
  late List<({SettingsFile file, List<String> rows})> put;
  StateError? refusal;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('anicel-settings-window');
    put = [];
    refusal = null;
  });
  tearDown(() => deleteTempQuietly(tempDir));

  /// A settings file named [name] holding [documents].
  String aSettingsFile(
    Map<String, Map<String, dynamic>> documents, {
    String name = 'Mine.anisettings',
  }) {
    final file = File('${tempDir.path}/$name')
      ..writeAsStringSync(encodeSettingsFile(documents));
    return file.path;
  }

  Future<EditorSessionManager> openOn(
    WidgetTester tester,
    List<String> paths, {
    bool puts = true,
  }) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(
            session: session,
            initialPaths: paths,
            putSettingsInPlace: puts
                ? (file, rows) async {
                    if (refusal case final error?) {
                      throw error;
                    }
                    put.add((
                      file: file,
                      rows: [for (final row in rows) row.id],
                    ));
                  }
                : null,
          ),
        ),
      ),
    );
    await tester.pump();
    return session;
  }

  ImportFileTable table(WidgetTester tester) =>
      tester.widget<ImportFileTable>(find.byType(ImportFileTable));

  ImportColumn<Object?> column(WidgetTester tester, String id) =>
      table(tester).columns.singleWhere((column) => column.id == id);

  String statusLine(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('import-status')))
      .data!;

  /// [row]'s 「넣을 곳」 answered 「제외」, by its cell.
  Future<void> leaveOut(WidgetTester tester, String row) async {
    await tester.tap(find.byKey(ValueKey<String>('import-cell-into-$row')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('import-option-into-left-out')),
    );
    await tester.pumpAndSettle();
  }

  Future<void> importAll(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    session.playbackRig.prerenderScheduler.cancel();
  }

  final accent = {'version': AppAccentSettingsStore.version, 'hue': 1};
  final language = {'version': AppLanguageSettingsStore.version, 'ui': 'ko'};
  final brushes = {
    'brush_presets.json': {'version': BrushPresetFileService.libraryVersion},
  };

  testWidgets('a row for each setting the file holds — the brushes one — '
      'each answered 「설정」, with the warning that what is there goes', (
    tester,
  ) async {
    final path = aSettingsFile({
      'accent_settings.json': accent,
      ...brushes,
      'window.json': {'version': 1},
    });
    await openOn(tester, [path]);

    final rows = table(tester).rows;
    expect([for (final row in rows) row.path], [
      '$path#accent_settings.json',
      '$path#brushes',
    ]);
    expect([for (final row in rows) row.name], [
      AppText.strings.prefsAccent,
      AppText.strings.brBrushesTitle,
    ]);
    final into = column(tester, 'into');
    for (final row in rows) {
      expect(into.cellWordOf(row.path), AppText.strings.imIntoSettings);
    }
    for (final other in table(tester).columns.skip(1)) {
      expect(other.appliesTo(rows.first.path), isFalse, reason: other.id);
    }
    expect(statusLine(tester), AppText.strings.imSettingsGoInPlace);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('import-source-line')),
          )
          .data,
      path,
    );
  });

  testWidgets('Import puts in place what each row answered 「설정」 — not a '
      'row left out, nor one this build cannot read', (tester) async {
    final path = aSettingsFile({
      'accent_settings.json': accent,
      'language_settings.json': language,
      'onion_skin_settings.json': {
        'version': AppOnionSkinSettingsStore.version + 1,
      },
    });
    final session = await openOn(tester, [path]);
    final onion = '$path#onion_skin_settings.json';
    final into = column(tester, 'into');
    expect(into.answersFor(onion), hasLength(1), reason: 'locked');
    expect(into.cellWordOf(onion), AppText.strings.imSettingsUnreadable);

    await leaveOut(tester, '$path#language_settings.json');
    expect(
      column(tester, 'into').cellWordOf('$path#language_settings.json'),
      AppText.strings.imExcluded,
    );

    await importAll(tester, session);

    expect(put, hasLength(1));
    expect(put.single.rows, ['accent_settings.json']);
    expect(put.single.file.documents['accent_settings.json'], accent);
  });

  testWidgets('every row left out, nothing goes in place — and nothing is '
      'warned of', (tester) async {
    final path = aSettingsFile({'accent_settings.json': accent});
    final session = await openOn(tester, [path]);

    await leaveOut(tester, '$path#accent_settings.json');
    expect(statusLine(tester), isEmpty);
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await tester.pump();
    session.playbackRig.prerenderScheduler.cancel();

    expect(put, isEmpty);
    expect(table(tester).rows, hasLength(1), reason: 'no run happened');
  });

  testWidgets('a put that fails is said of its file, and its rows stay to '
      'be pressed again', (tester) async {
    final path = aSettingsFile({'accent_settings.json': accent});
    final session = await openOn(tester, [path]);
    refusal = StateError('disk full');

    await importAll(tester, session);

    expect(put, isEmpty);
    expect(
      [for (final row in table(tester).rows) row.path],
      ['$path#accent_settings.json'],
    );
    expect(
      find.text(AppText.strings.imWarningCount(1)),
      findsOneWidget,
    );

    refusal = null;
    await importAll(tester, session);
    expect(put.single.rows, ['accent_settings.json']);
  });

  testWidgets('a file that brings no setting this build reads is named, and '
      'brings no row', (tester) async {
    final broken = File('${tempDir.path}/Broken.anisettings')
      ..writeAsStringSync('{"anicelSettings": 1, "docu');
    final bound = aSettingsFile({
      'window.json': {'version': 1},
    }, name: 'Window.anisettings');
    await openOn(tester, [broken.path, bound]);

    expect(table(tester).rows, isEmpty);
    expect(find.text(AppText.strings.imWarningCount(2)), findsOneWidget);
  });

  testWidgets('with nothing to put settings in place, or beside a cut '
      'folder, a settings file brings no row', (tester) async {
    final path = aSettingsFile({'accent_settings.json': accent});
    await openOn(tester, [path], puts: false);
    expect(table(tester).rows, isEmpty);

    final folder = Directory('${tempDir.path}/cut')..createSync();
    await tester.runAsync(() => writeSolidPng(tempDir, 'cut/A1.png'));
    await tester.pumpWidget(const SizedBox());
    await openOn(tester, [folder.path, path]);
    final rows = table(tester).rows;
    expect(rows.any((row) => row.path.startsWith('$path#')), isFalse);
    expect(rows.last.name, contains('Mine.anisettings'));
  });
}
