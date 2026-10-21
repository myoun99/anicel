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
import 'package:anicel/src/services/persistence/recent_projects.dart';
import 'package:anicel/src/services/persistence/recent_projects_store.dart';
import 'package:anicel/src/ui/brush/brush_preset_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;

import '../helpers/project_scratch_folder.dart';
import '../helpers/settle_async.dart';
import '../helpers/wait_window.dart';

/// No saved language, said only when the test says so — and the brush
/// library's read waits for it.
class _LateLanguage extends AppLanguageSettingsStore {
  _LateLanguage() : super(filePath: 'unused');

  final gate = Completer<void>();

  @override
  Future<AppLanguageSettings?> load() async {
    await gate.future;
    return null;
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

  /// The app on [home], its first frame drawn — the frame after which the
  /// launch knocks.
  Future<void> pumpApp(WidgetTester tester, HomePage home) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pump();
  }

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
    final path = '${spelled(folder.path)}/notes.txt';
    File(path).writeAsStringSync('not a picture');

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

  testWidgets('the app hands its shell what it was opened with', (
    tester,
  ) async {
    final path = '${spelled(folder.path)}/notes.txt';
    File(path).writeAsStringSync('not a picture');
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
    final path = '${spelled(folder.path)}/notes.txt';
    File(path).writeAsStringSync('not a picture');
    // The reply is null only when nothing hears the channel.
    Future<ByteData?> runnerSays([String method = HandedFiles.openMethod]) {
      final reply = Completer<ByteData?>();
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        HandedFiles.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, [path]),
        ),
        reply.complete,
      );
      return reply.future;
    }

    final notice = find.byKey(
      const ValueKey<String>('unsupported-file-notice'),
    );

    await pumpApp(tester, HomePage(initialProject: createDefaultProject()));
    await tester.pumpAndSettle();
    expect(notice, findsNothing, reason: 'CONTROL: nothing said yet');
    await runnerSays('somethingElse');
    await tester.pumpAndSettle();
    expect(notice, findsNothing, reason: 'only what it says to open opens');
    expect(await runnerSays(), isNotNull, reason: 'the window hears');
    await tester.pumpAndSettle();
    expect(notice, findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(await runnerSays(), isNull, reason: 'nothing hears once it is gone');
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
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
