import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/recent_projects.dart';
import 'package:anicel/src/services/persistence/recent_projects_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/menu/project_open_door.dart';
import 'package:anicel/src/ui/open_projects.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'package:anicel/src/ui/text/app_strings.dart';
import '../../helpers/project_scratch_folder.dart';

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

  /// A project file that really opens.
  Future<String> projectNamed(WidgetTester tester, String name) async {
    final path = '${spelled(folder.path)}/$name';
    final session = EditorSessionManager(initialProject: createDefaultProject());
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

  /// [paths] dropped on the middle of the window, as the plugin hears it.
  Future<void> drop(WidgetTester tester, List<String> paths) async {
    final at = tester.getCenter(find.byType(EditorWorkspace));
    const codec = StandardMethodCodec();
    Future<void> hear(String method, Object arguments) =>
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'desktop_drop',
          codec.encodeMethodCall(MethodCall(method, arguments)),
          (_) {},
        );
    await hear('entered', <double>[at.dx, at.dy]);
    await hear('updated', <double>[at.dx, at.dy]);
    await hear('performOperation', paths);
    await tester.pump();
    await tester.pump();
  }

  const patience = Duration(seconds: 60);

  /// Pumps real time until [done] says so, or [patience] has run out.
  Future<void> until(WidgetTester tester, bool Function() done) async {
    final deadline = DateTime.now().add(patience);
    while (!done() && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
    await tester.pump();
  }

  final waitWindow = find.byKey(const ValueKey<String>('open-progress-dialog'));

  test('「열기」 opens what its one list names — by name, in any case', () {
    expect(opensAsProject('C:/work/Cut 12.anicel'), isTrue);
    expect(opensAsProject('/work/CUT 12.ANICEL'), isTrue);
    expect(opensAsProject('/work/clip.tvpp'), isTrue);
    expect(opensAsProject('/work/Clip.TVPP'), isTrue);
    for (final extension in projectOpenExtensions) {
      expect(opensAsProject('/work/x.$extension'), isTrue, reason: extension);
    }
    expect(opensAsProject('/work/picture.png'), isFalse);
    expect(opensAsProject('/work/movie.mp4'), isFalse);
    expect(opensAsProject('/work/notes.anicel.txt'), isFalse);
    expect(
      opensAsProject('/work/anicel'),
      isFalse,
      reason: 'a folder named like the extension is not a project file',
    );
  });

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

  testWidgets('a dropped picture still comes in through the import window, '
      'and the open door stays shut', (tester) async {
    final path = fileNamed('picture.png');
    await pumpApp(tester);

    await drop(tester, [path]);

    expect(tester.widget<ImportDialog>(find.byType(ImportDialog)).initialPaths, [
      path,
    ]);
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
      tester.widget<ImportDialog>(window).initialPaths,
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
