import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/layer_effect.dart' show EffectKind;
import 'package:anicel/src/services/persistence/recent_projects.dart';
import 'package:anicel/src/services/persistence/recent_projects_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/open_projects.dart';
import 'package:anicel/src/ui/session/effects_and_fx.dart' show TrackChain;
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:anicel/src/ui/text/app_strings.dart';
import '../../helpers/os_file_drop.dart';
import '../../helpers/project_scratch_folder.dart';
import '../../helpers/wait_window.dart';

/// F-247 (유저 2026-09-30): 「드래그앤드롭으로 외부파일 임포트시 확장자?에
/// 맞도록. anicel이면 배치창이아니라 새 프로젝트로 열도록. tvpp도 똑같이」.
///
/// The drop arrives the way the OS hands it over — through the drop
/// plugin's channel, entered · moved · dropped — so the window's own drop
/// target decides the point is inside it and hands the paths on. A test
/// that called the handler would survive the target losing its callback.
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_dropped_project_');
    // Every test's folder goes, not only the two that open a project out of
    // it: the others left theirs in the temp (2026-10-08).
    deleteAfterSessionEnds(folder);
    AppRecent.projects.value = const RecentProjects();
    RecentProjectsStore().save(const RecentProjects());
  });

  tearDown(() {
    AppRecent.projects.value = const RecentProjects();
    RecentProjectsStore().save(const RecentProjects());
  });

  String spelled(String path) => path.replaceAll(r'\', '/');

  /// A file named [name] that is nothing in particular — which door a
  /// dropped file reaches is decided by its name.
  String fileNamed(String name) {
    final path = '${spelled(folder.path)}/$name';
    File(path).writeAsStringSync('x');
    return path;
  }

  /// A project file that really opens — its track wearing an effect of
  /// [plugin], where one is named.
  Future<String> projectNamed(
    WidgetTester tester,
    String name, {
    FxPluginDescription? plugin,
  }) async {
    final path = '${spelled(folder.path)}/$name';
    final session = EditorSessionManager(initialProject: createDefaultProject());
    if (plugin != null) {
      session.effectsAndFx.addEffect(
        TrackChain(session.repository.requireProject().tracks.first.id),
        EffectKind.plugin,
        plugin: plugin,
      );
    }
    await tester.runAsync(
      () => session.projectDoor.saveProjectToFile(
        path,
        asked: SaveAsked.byAPerson,
      ),
    );
    session.dispose();
    return path;
  }

  Future<OpenProjects> pumpApp(WidgetTester tester) async {
    // One device pixel to a logical one, so the point a drop is heard at
    // means the same on every platform (Windows and Android hand it over
    // in device pixels).
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    return tester.widget<EditorTopStrip>(find.byType(EditorTopStrip)).projects;
  }

  /// [paths] dropped on the middle of the window — the drawing floor.
  Future<void> drop(WidgetTester tester, List<String> paths) =>
      osDrop(tester, paths, at: tester.getCenter(find.byType(EditorWorkspace)));

  /// Lends the disk real time and the test clock a beat, by turns, until
  /// [done] says so, or [settleAsync]'s patience has run out — the open's
  /// linger passed in one step ([settleBehindTheWaitWindow]; ↩️walked 50ms
  /// a frame until 10-20).
  Future<void> until(WidgetTester tester, bool Function() done) async {
    await settleBehindTheWaitWindow(tester, done);
    await tester.pump();
  }

  final waitWindow = find.byKey(const ValueKey<String>('open-progress-dialog'));
  final pluginsNotHere = find.byKey(
    const ValueKey<String>('fx-plugins-not-on-device-notice'),
  );

  /// The paths the import window was handed — the door's grants.
  List<String?> handedTo(WidgetTester tester) => [
    for (final grant
        in tester.widget<ImportDialog>(find.byType(ImportDialog)).picked)
      grant.path,
  ];

  testWidgets('🎯a dropped .anicel opens in a tab of its own — the import '
      'window never comes up', (tester) async {
    final path = await projectNamed(tester, 'Cut 12.anicel');
    final projects = await pumpApp(tester);

    await drop(tester, [path]);
    expect(find.byType(ImportDialog), findsNothing);
    await until(tester, () => projects.sessions.length == 2);

    expect(projects.sessions.length, 2, reason: 'it opened, beside the first');
    expect(spelled(projects.active.projectFile.path!), path);
    expect(find.byType(ImportDialog), findsNothing);
    expect(pluginsNotHere, findsNothing, reason: 'it wears none');
  });

  testWidgets('a project wearing a plugin this device has not is told so '
      'after it opens — by the plugin\'s name (🗣️I-132-Q28)', (tester) async {
    final glow = FxPluginDescription.fromJson({
      'spec': 1,
      'id': 'com.example.glow',
      'name': 'Glow',
      'vendor': 'Example',
      'version': '1',
      'can': ['cpu'],
      'params': <Object?>[],
    })!;
    final path = await projectNamed(tester, 'Cut 12.anicel', plugin: glow);
    await pumpApp(tester);

    await drop(tester, [path]);
    await until(tester, () => pluginsNotHere.evaluate().isNotEmpty);

    expect(
      find.descendant(
        of: pluginsNotHere,
        matching: find.text(AppText.strings.fxPluginsNotOnDevice(['Glow'])),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a project with the folder older builds kept beside it is '
      'told so after it opens — by the folder\'s name', (tester) async {
    final path = await projectNamed(tester, 'Cut 12.anicel');
    Directory('${spelled(folder.path)}/Cut 12.assets').createSync();
    await pumpApp(tester);
    final notice = find.byKey(
      const ValueKey<String>('legacy-assets-folder-notice'),
    );

    await drop(tester, [path]);
    await until(tester, () => notice.evaluate().isNotEmpty);

    Finder saying(String text) =>
        find.descendant(of: notice, matching: find.textContaining(text));
    expect(saying('Cut 12.assets'), findsOneWidget);
    expect(
      saying(spelled(folder.path)),
      findsNothing,
      reason: 'the name, not the path to it',
    );
  });

  testWidgets('a dropped .tvpp goes through the same door — the TVPaint '
      'reader is what answers it', (tester) async {
    final path = fileNamed('Clip.tvpp');
    final projects = await pumpApp(tester);
    final notTvpp = find.text(AppText.strings.imNotTvpp);

    await drop(tester, [path]);
    expect(find.byType(ImportDialog), findsNothing);
    await until(tester, () => notTvpp.evaluate().isNotEmpty);

    expect(
      notTvpp,
      findsOneWidget,
      reason: 'a file that is no TVPaint project is said to be one by the '
          'door that reads TVPaint projects — nothing else says it',
    );
    expect(projects.sessions.length, 1);
  });

  testWidgets('a dropped .clip goes through the same door — the CLIP STUDIO '
      'reader is what answers it', (tester) async {
    final path = fileNamed('Scene.clip');
    final projects = await pumpApp(tester);
    final notClip = find.text(AppText.strings.imNotClip);

    await drop(tester, [path]);
    expect(find.byType(ImportDialog), findsNothing);
    await until(tester, () => notClip.evaluate().isNotEmpty);

    expect(
      notClip,
      findsOneWidget,
      reason: 'a file that is no CLIP STUDIO file is said to be one by the '
          'door that reads them — nothing else says it',
    );
    expect(projects.sessions.length, 1);
  });

  testWidgets('a dropped picture still comes in through the import window, '
      'and the open door stays shut', (tester) async {
    final path = fileNamed('picture.png');
    await pumpApp(tester);

    await drop(tester, [path]);

    expect(handedTo(tester), [path]);
    expect(waitWindow, findsNothing);
  });

  testWidgets('one drop that holds both takes its files in first, and opens '
      'the project once that window is closed', (tester) async {
    final project = await projectNamed(tester, 'Cut 12.anicel');
    final picture = fileNamed('picture.png');
    final projects = await pumpApp(tester);

    await drop(tester, [project, picture]);

    final window = find.byType(ImportDialog);
    expect(
      handedTo(tester),
      [picture],
      reason: 'the project is not one of the files taken in',
    );
    expect(
      waitWindow,
      findsNothing,
      reason: 'the files go into the project the drop landed on — an open '
          'now would take that project off the screen',
    );

    Navigator.of(tester.element(window)).pop();
    await until(tester, () => projects.sessions.length == 2);

    expect(projects.sessions.length, 2);
    expect(spelled(projects.active.projectFile.path!), project);
  });
}
