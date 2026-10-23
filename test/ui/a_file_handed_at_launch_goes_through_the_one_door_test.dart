import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart' show AnicelApp;
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/native/handed_files.dart';
import 'package:anicel/src/services/brush_pack_file.dart';
import 'package:anicel/src/services/brush_preset_file_service.dart';
import 'package:anicel/src/services/brush_tip_library_service.dart';
import 'package:anicel/src/services/persistence/app_language_settings_store.dart';
import 'package:anicel/src/services/persistence/file_type_groups.dart'
    show openableExtensions;
import 'package:anicel/src/services/persistence/recent_projects.dart';
import 'package:anicel/src/services/persistence/recent_projects_store.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/dialogs/app_confirm_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:anicel/src/ui/text/app_strings.dart';

import '../helpers/project_scratch_folder.dart';
import '../helpers/settle_async.dart';
import '../helpers/wait_window.dart';

/// The [saved] language — none unless the test gives one — said only when
/// the test says so; the brush library's read waits for it.
class _LateLanguage extends AppLanguageSettingsStore {
  _LateLanguage([this.saved]) : super(filePath: 'unused');

  final AppLanguageSettings? saved;

  final gate = Completer<void>();

  @override
  Future<AppLanguageSettings?> load() async {
    await gate.future;
    return saved;
  }

  @override
  Future<void> save(AppLanguageSettings settings) async {}
}

/// `open-door-windows-open-with`: a file opened with Anicel from the
/// Explorer — 「연결 프로그램」, a double-click — arrives as a launch argument,
/// and goes through the one door a drop on the window goes through (F-282-Q5,
/// 유저 2026-10-09: 「최대한 통일하고싶음」).
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_handed_');
    deleteAfterSessionEnds(folder);
  });
  tearDown(() {
    AppRecent.projects.value = const RecentProjects();
    RecentProjectsStore().save(const RecentProjects());
  });

  String spelled(String path) => path.replaceAll(r'\', '/');

  // A file NO door takes. This was `notes.txt` until a program's shortcut
  // files became something the door opens (I-107-Q2, 유저 2026-10-22:
  // 「다섯 다」 — TVPaint's list is a .txt): from then on it was read as
  // shortcuts, the notice never came, and the read still held the file when
  // the folder went. An extension no group names cannot drift that way.
  String nothingOpens() {
    final path = '${spelled(folder.path)}/notes.xyz';
    File(path).writeAsStringSync('not a picture');
    return path;
  }

  /// The app on [home], its first frame drawn — the frame after which the
  /// launch knocks.
  Future<void> pumpApp(WidgetTester tester, HomePage home) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pump();
  }

  /// The platform saying [handed] on [HandedFiles.channel]. The reply is
  /// null only when nothing hears the channel.
  Future<ByteData?> platformSays(
    WidgetTester tester,
    List<Object?> handed, [
    String method = HandedFiles.openMethod,
  ]) {
    final reply = Completer<ByteData?>();
    unawaited(
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        HandedFiles.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, handed),
        ),
        reply.complete,
      ),
    );
    return reply.future;
  }

  final notice = find.byKey(const ValueKey<String>('unsupported-file-notice'));

  /// The files the notice on screen names.
  List<String> named(WidgetTester tester) => tester
      .widget<AppConfirmDialog>(find.byType(AppConfirmDialog))
      .details
      .single
      .lines;

  testWidgets('🎯a project handed at launch opens in a tab of its own', (
    tester,
  ) async {
    final path = '${spelled(folder.path)}/Handed.anicel';
    final seed = EditorSessionManager(initialProject: createDefaultProject());
    await tester.runAsync(
      () => seed.projectDoor.saveProjectToFile(
        path,
        asked: SaveAsked.byAPerson,
      ),
    );
    seed.dispose();

    await pumpApp(
      tester,
      HomePage(initialProject: createDefaultProject(), handedAtLaunch: [path]),
    );
    final projects = tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip))
        .projects;
    await settleBehindTheWaitWindow(
      tester,
      () => projects.sessions.length == 2,
    );
    await tester.pumpAndSettle();

    expect(projects.sessions, hasLength(2));
    expect(find.text('Handed'), findsWidgets, reason: 'its tab, by its name');
  });

  testWidgets('a file nothing opens is said, as a drop says it', (
    tester,
  ) async {
    final path = nothingOpens();

    await pumpApp(
      tester,
      HomePage(initialProject: createDefaultProject(), handedAtLaunch: [path]),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('unsupported-file-notice')),
      findsOneWidget,
    );
  });

  // Card open-door-windows-open-with (서피스 AI 실기 2026-10-23): an app
  // started cold with a file nothing opens refused it in English — the
  // language it starts in — under a Japanese list of it. The launch knocks
  // in the first frame and a notice's words are written as it opens, while
  // the language the app was left in is read after that frame (F-170).
  testWidgets('🎯a file handed at launch is said in the language the app '
      'was left in, which is read after the first frame', (tester) async {
    AppText.settings.value = const AppLanguageSettings();
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
    final ja = AppStrings.of(AppLanguage.ja);
    final language = _LateLanguage(
      const AppLanguageSettings(programLanguage: AppLanguage.ja),
    );
    final path = nothingOpens();

    await pumpApp(
      tester,
      HomePage(
        initialProject: createDefaultProject(),
        languageSettingsStore: language,
        handedAtLaunch: [path],
      ),
    );
    // Long enough for a door that did NOT wait to have knocked.
    await lendBothClocks(
      tester,
      rounds: 10,
      beat: const Duration(milliseconds: 50),
    );
    expect(
      AppText.strings.unsupportedFileTitle,
      isNot(ja.unsupportedFileTitle),
      reason: 'LIVENESS — the app starts in another language',
    );
    language.gate.complete();
    await tester.pumpAndSettle();

    final said = tester.widget<AppConfirmDialog>(find.byType(AppConfirmDialog));
    expect(said.title, ja.unsupportedFileTitle);
    expect(said.message, ja.unsupportedFileMessage(openableExtensions));
    expect(named(tester), [path]);
  });

  // The channel's files can come as early: Android says the file that
  // started the app there once Dart hears it, and a second Anicel may knock
  // the moment the first is up.
  testWidgets('what the platform says before the saved language is back is '
      'said in that language too', (tester) async {
    AppText.settings.value = const AppLanguageSettings();
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
    final ja = AppStrings.of(AppLanguage.ja);
    final language = _LateLanguage(
      const AppLanguageSettings(programLanguage: AppLanguage.ja),
    );
    final path = nothingOpens();

    await pumpApp(
      tester,
      HomePage(
        initialProject: createDefaultProject(),
        languageSettingsStore: language,
      ),
    );
    await platformSays(tester, [path]);
    await lendBothClocks(
      tester,
      rounds: 10,
      beat: const Duration(milliseconds: 50),
    );
    language.gate.complete();
    await tester.pumpAndSettle();

    final said = tester.widget<AppConfirmDialog>(find.byType(AppConfirmDialog));
    expect(said.title, ja.unsupportedFileTitle);
    expect(named(tester), [path]);
  });

  // The same card's 덤: the import window named a file Windows opened the
  // app with `C:\Users\…`, where 「開く」 named the same file `C:/Users/…`.
  testWidgets('a file handed in Windows\' spelling is named as a pick names '
      'it', (tester) async {
    final path = nothingOpens();

    await pumpApp(
      tester,
      HomePage(
        initialProject: createDefaultProject(),
        handedAtLaunch: [path.replaceAll('/', r'\')],
      ),
    );
    await tester.pumpAndSettle();

    expect(named(tester), [path]);
  });

  testWidgets('the app hands its shell what it was opened with', (
    tester,
  ) async {
    final path = nothingOpens();
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(AnicelApp(handedAtLaunch: [path]));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('unsupported-file-notice')),
      findsOneWidget,
    );
  });

  // open-door-windows-open-with-Q1 (유저 2026-10-22: 「떠 있는 창의 새
  // 탭으로」): a second Anicel hands its files to the running window, which
  // says them on [HandedFiles.channel] — heard while the window is here.
  testWidgets('what a second Anicel hands the running window goes through '
      'the same door, and nothing once the window has gone', (tester) async {
    final path = nothingOpens();

    await pumpApp(tester, HomePage(initialProject: createDefaultProject()));
    await tester.pumpAndSettle();
    expect(notice, findsNothing, reason: 'CONTROL: nothing said yet');
    await platformSays(tester, [path], 'somethingElse');
    await tester.pumpAndSettle();
    expect(notice, findsNothing, reason: 'only what it says to open opens');
    expect(
      await platformSays(tester, [path]),
      isNotNull,
      reason: 'the window hears',
    );
    await tester.pumpAndSettle();
    expect(notice, findsOneWidget);
    expect(named(tester), [path]);

    await tester.pumpWidget(const SizedBox());
    expect(
      await platformSays(tester, [path]),
      isNull,
      reason: 'nothing hears once it is gone',
    );
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
  });

  // open-door-android-share (F-282-Q5, 유저 2026-10-09: 「최대한
  // 통일하고싶음」): Android says what another app shares with Anicel or
  // opens it with on the same channel, each file as its picker says one —
  // a path, or a document with no path behind it (PICK-7).
  testWidgets('what another app hands Android goes through the same door — '
      'a document by the name its provider gives, a path by its path', (
    tester,
  ) async {
    final path = nothingOpens();
    Future<void> closeTheNotice() async {
      await tester.tap(find.byKey(const ValueKey<String>('app-notice-close')));
      await tester.pumpAndSettle();
    }

    await pumpApp(tester, HomePage(initialProject: createDefaultProject()));
    await tester.pumpAndSettle();

    await platformSays(tester, [
      {'uri': 'content://drive/doc/9', 'name': 'notes.xyz', 'size': 13},
    ]);
    await tester.pumpAndSettle();
    expect(notice, findsOneWidget);
    expect(
      named(tester),
      ['notes.xyz'],
      reason: 'judged and named by its own name — its URI says nothing',
    );
    await closeTheNotice();

    await platformSays(tester, [
      {'path': path, 'bookmark': null},
    ]);
    await tester.pumpAndSettle();
    expect(notice, findsOneWidget, reason: 'a FILE: no folder is handed');
    expect(named(tester), [path]);
    await closeTheNotice();
  });

  testWidgets('nothing handed, nothing opened and nothing said', (
    tester,
  ) async {
    await pumpApp(tester, HomePage(initialProject: createDefaultProject()));
    await tester.pumpAndSettle();

    final projects = tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip))
        .projects;
    expect(projects.sessions, hasLength(1));
    expect(
      find.byKey(const ValueKey<String>('unsupported-file-notice')),
      findsNothing,
    );
  });

  // The launch knocks in the first frame — before the brush library has
  // been read, and the read puts back what its file holds. Here the read
  // waits for a language that comes late, so a brush brought before it
  // would be the one thing in the file the read then finds.
  testWidgets('a brush handed at launch joins the library once it has been '
      'read, built-ins and all', (tester) async {
    final language = _LateLanguage();
    final path = '${spelled(folder.path)}/Handed.anibrush';
    File(path).writeAsStringSync(
      encodeBrushPack(
        BrushPack(
          presets: [
            BrushPreset(
              id: const BrushPresetId('handed-pen'),
              name: 'Handed pen',
              settings: BrushSettings(size: 3),
            ),
          ],
        ),
      ),
      encoding: utf8,
    );

    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialProject: createDefaultProject(),
          presetFileService: BrushPresetFileService(
            filePath: '${spelled(folder.path)}/brush_presets.json',
          ),
          tipLibraryService: BrushTipLibraryService(
            directoryPath: '${spelled(folder.path)}/tips',
          ),
          languageSettingsStore: language,
          handedAtLaunch: [path],
        ),
      ),
    );
    // Long enough for a brush that did NOT wait to be read and brought.
    await lendBothClocks(
      tester,
      rounds: 10,
      beat: const Duration(milliseconds: 50),
    );
    language.gate.complete();

    List<BrushPreset> presets() {
      final panels = find.byType(BrushPresetPanel);
      return panels.evaluate().isEmpty
          ? const []
          : tester.widget<BrushPresetPanel>(panels.first).presets;
    }

    bool holds(String name) => presets().any((preset) => preset.name == name);

    expect(
      await settleAsync(tester, () => holds('Handed pen')),
      isTrue,
      reason: 'the handed brush never joined the library',
    );
    expect(
      presets().any((preset) => preset.id.value == 'builtin-g-pen'),
      isTrue,
      reason: 'the built-ins are still there',
    );
  });
}
