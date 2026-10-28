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
import 'package:anicel/src/ui/import/import_preview.dart';
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
  /// The entry a file holding it fails to be put in place for.
  String? refused;

  /// Whether the window said it was importing while the settings went in.
  final saidWhilePutting = <String?>[];

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('anicel-settings-window');
    put = [];
    refused = null;
    saidWhilePutting.clear();
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
    // Over a route of its own, as the workspace opens it — so that a run
    // that lands closes it.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ImportDialog(
                  session: session,
                  initialPaths: paths,
                  putSettingsInPlace: puts
                      ? (file, rows) async {
                          saidWhilePutting.add(
                            tester
                                .widget<Text>(
                                  find.byKey(
                                    const ValueKey<String>('import-status'),
                                  ),
                                )
                                .data,
                          );
                          if (file.documents.containsKey(refused)) {
                            throw StateError('disk full');
                          }
                          put.add((
                            file: file,
                            rows: [for (final row in rows) row.id],
                          ));
                        }
                      : null,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return session;
  }

  /// [row]'s 「넣을 곳」 answered [option], by its cell.
  Future<void> answer(WidgetTester tester, String row, String option) async {
    await tester.tap(find.byKey(ValueKey<String>('import-cell-into-$row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>('import-option-into-$option')));
    await tester.pumpAndSettle();
  }

  ImportFileTable table(WidgetTester tester) =>
      tester.widget<ImportFileTable>(find.byType(ImportFileTable));

  ImportColumn<Object?> column(WidgetTester tester, String id) =>
      table(tester).columns.singleWhere((column) => column.id == id);

  String statusLine(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('import-status')))
      .data!;

  Future<void> leaveOut(WidgetTester tester, String row) =>
      answer(tester, row, 'left-out');

  Future<void> importAll(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    session.playbackRig.prerenderScheduler.cancel();
    // The window's own way out, where the run closed it.
    await tester.pump(const Duration(milliseconds: 400));
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
    expect(
      [for (final value in into.values) into.labelOf(value)],
      contains(AppText.strings.imIntoSettings),
      reason: 'the header speaks for the settings rows too',
    );
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
    expect(
      tester
          .widget<ImportPreview>(
            find.byKey(const ValueKey<String>('import-preview')),
          )
          .path,
      isNull,
      reason: 'a setting shows nothing',
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
    expect(find.byType(ImportDialog), findsNothing, reason: 'it landed');
  });

  testWidgets('every row left out, nothing goes in place — and nothing is '
      'warned of', (tester) async {
    final path = aSettingsFile({'accent_settings.json': accent});
    final session = await openOn(tester, [path]);
    final row = '$path#accent_settings.json';

    await leaveOut(tester, row);
    expect(statusLine(tester), isEmpty);
    await answer(tester, row, 'settings');
    expect(statusLine(tester), AppText.strings.imSettingsGoInPlace);
    await leaveOut(tester, row);
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await tester.pump();
    session.playbackRig.prerenderScheduler.cancel();

    expect(put, isEmpty);
    expect(table(tester).rows, hasLength(1), reason: 'no run happened');
  });

  testWidgets('a put that fails is said of its file, and its rows stay to '
      'be pressed again — what went in leaves the list', (tester) async {
    final kept = aSettingsFile({'accent_settings.json': accent});
    final failing = aSettingsFile({
      'language_settings.json': language,
    }, name: 'Other.anisettings');
    final session = await openOn(tester, [kept, failing]);
    refused = 'language_settings.json';

    await importAll(tester, session);

    expect([for (final done in put) done.rows], [
      ['accent_settings.json'],
    ]);
    expect(saidWhilePutting, [
      AppText.strings.imStatusImporting,
      AppText.strings.imStatusImporting,
    ], reason: 'the window says what it is doing, not what it will');
    expect(
      [for (final row in table(tester).rows) row.path],
      ['$failing#language_settings.json'],
    );
    expect(find.text(AppText.strings.imWarningCount(1)), findsOneWidget);

    refused = null;
    await importAll(tester, session);
    expect(put.last.rows, ['language_settings.json']);
    expect(put, hasLength(2), reason: 'what went in is not put again');
    expect(find.byType(ImportDialog), findsNothing);
  });

  testWidgets('a press on a setting\'s row speaks for the settings of the '
      'selection — a file\'s answer stays as it was', (tester) async {
    final picture = (await tester.runAsync(
      () => writeSolidPng(tempDir, 'A1.png'),
    ))!;
    final path = aSettingsFile({'accent_settings.json': accent});
    await openOn(tester, [picture, path]);
    final row = '$path#accent_settings.json';
    var into = column(tester, 'into');
    into.onPick([picture], into.answersFor(picture).last);
    await tester.pump();
    into = column(tester, 'into');
    final filesWord = into.cellWordOf(picture);
    expect(filesWord, AppText.strings.panelMedia, reason: 'premise');

    into.onPick([picture, row], into.answersFor(row).last);
    await tester.pump();

    into = column(tester, 'into');
    expect(into.cellWordOf(row), AppText.strings.imExcluded);
    expect(into.cellWordOf(picture), filesWord);
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
