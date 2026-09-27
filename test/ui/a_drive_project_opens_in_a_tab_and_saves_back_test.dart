import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/provider_documents.dart';
import 'package:anicel/src/services/persistence/recent_projects.dart';
import 'package:anicel/src/services/persistence/recent_projects_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/open_projects.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;

import '../helpers/project_scratch_folder.dart';
import '../models/import/tvpp_test_builder.dart';

/// PICK-7 through the window: a project in a Drive document on Android is
/// opened from the Open button into a tab of its own, saved back into the
/// document from the menu, shown again rather than opened twice, and
/// reopened from Recents on the next run.
///
/// 🗣️유저 2026-09-27 (갤탭): 「클라우드에있는 fu 열려고하니까 … 폴더경로가
/// 없다고 … ios는 바로 되게했는데 안드로이드는 어쩔수 없나?」 → Q1 「드라이브
/// 파일을 그대로 읽고, 저장은 통째로 다시 쓴다」.
void main() {
  late Directory folder;
  late Map<String, String> documents;

  Future<Map<Object?, Object?>?> provider(
    String method,
    Map<String, Object?> arguments,
  ) async {
    switch (method) {
      case 'copyDocument':
        final destination = arguments['destinationPath']! as String;
        final source = documents[arguments['uri']];
        if (source == null) {
          return {'status': 'unavailable'};
        }
        File(source).copySync(destination);
        return {
          'status': 'granted',
          'items': [
            {'path': destination},
          ],
        };
      case 'writeDocument':
        final uri = arguments['uri']! as String;
        File(arguments['sourcePath']! as String).copySync(documents[uri]!);
        return {
          'status': 'granted',
          'items': [
            {'uri': uri},
          ],
        };
      case 'documentTransferred':
        return {'value': 0};
    }
    return null;
  }

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_drive_tabs_');
    documents = {};
    ProviderDocuments.debugChannel = provider;
  });

  tearDown(() {
    FolderPicker.debugFilePicker = null;
    ProviderDocuments.debugReset();
    AppRecent.projects.value = const RecentProjects();
    RecentProjectsStore().save(const RecentProjects());
  });

  String spelled(String path) => path.replaceAll(r'\', '/');

  /// [bytes] as the document [uri] names.
  void hand(String uri, List<int> bytes) {
    final file = File('${spelled(folder.path)}/document-${documents.length}');
    file.writeAsBytesSync(bytes);
    documents[uri] = file.path;
  }

  Future<List<int>> projectBytes(WidgetTester tester) async {
    final seed = '${spelled(folder.path)}/seed.anicel';
    final session = EditorSessionManager(initialProject: createDefaultProject());
    await tester.runAsync(
      () => session.projectDoor.saveProjectToFile(
        seed,
        asked: SaveAsked.byAPerson,
      ),
    );
    session.dispose();
    return File(seed).readAsBytesSync();
  }

  Future<int> cutsIn(WidgetTester tester, String path) async =>
      (await tester.runAsync(
        () => const AnicelFileService().open(filePath: path),
      ))!.project.tracks.first.cuts.length;

  Future<OpenProjects> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    return tester.widget<EditorTopStrip>(find.byType(EditorTopStrip)).projects;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Pumps real time until [done] says so.
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var attempt = 0; attempt < 200 && !done(); attempt += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
    await tester.pumpAndSettle();
  }

  Future<void> openDocument(
    WidgetTester tester,
    OpenProjects projects,
    ProviderDocument document, {
    required bool Function() done,
  }) async {
    FolderPicker.debugFilePicker = ({
      required List<XTypeGroup> acceptedTypeGroups,
      required bool allowMultiple,
    }) async => [FolderGrant.providerDocument(document)];
    await tapKey(tester, 'top-strip-project-button');
    await tester.tap(find.byKey(const ValueKey<String>('menu-file-open')));
    await until(tester, done);
  }

  const drive = ProviderDocument(
    uri: 'content://drive/doc/cut',
    name: 'Cut.anicel',
  );

  testWidgets('🎯a Drive project opens in a tab of its own under its own '
      'name, and the menu\'s Save puts the work back IN THE DOCUMENT', (
    tester,
  ) async {
    deleteAfterSessionEnds(folder);
    hand(drive.uri, await projectBytes(tester));
    final projects = await pumpApp(tester);

    await openDocument(
      tester,
      projects,
      drive,
      done: () => projects.sessions.length == 2,
    );

    final opened = projects.active;
    final copy = ProviderDocuments.workingCopyOf(drive.uri);
    expect(copy, isNotNull, reason: 'CONTROL: it opened');
    expect(opened.projectFile.path, copy);
    expect(find.text('Cut'), findsWidgets, reason: 'the tab says its name');
    final before = await cutsIn(tester, documents[drive.uri]!);
    opened.cutVerbs.createCut();
    await tester.pump();

    await tapKey(tester, 'top-strip-project-button');
    await tester.tap(find.byKey(const ValueKey<String>('menu-file-save')));
    var saved = before;
    for (var attempt = 0; attempt < 200 && saved == before; attempt += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      saved = await cutsIn(tester, documents[drive.uri]!);
    }
    // The save's window lingers a beat after it lands, then goes.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(saved, before + 1, reason: 'the DOCUMENT holds the save');
    expect(opened.projectFile.hasUnsavedChanges, isFalse);
    expect(
      AppRecent.projects.value.entries.first,
      RecentProject(path: drive.uri, displayName: 'Cut.anicel'),
      reason: 'Recents keeps the document, not the copy that goes with the '
          'run',
    );
  });

  testWidgets('a Drive project already open is SHOWN, not opened a second '
      'time', (tester) async {
    deleteAfterSessionEnds(folder);
    hand(drive.uri, await projectBytes(tester));
    final projects = await pumpApp(tester);
    await openDocument(
      tester,
      projects,
      drive,
      done: () => projects.sessions.length == 2,
    );
    final opened = projects.active;
    await tapKey(tester, 'project-tab-0');
    expect(projects.active, isNot(same(opened)), reason: 'CONTROL');

    await openDocument(tester, projects, drive, done: () => false);

    expect(projects.sessions, hasLength(2), reason: 'one writer per document');
    expect(projects.active, same(opened));
  });

  testWidgets('a TVPaint project in Drive opens as a project, told by its '
      'NAME — its URI says nothing of what it is', (tester) async {
    deleteAfterSessionEnds(folder);
    const tvpp = ProviderDocument(
      uri: 'content://drive/doc/tvpp',
      name: 'next.tvpp',
    );
    final b = TvppBuilder()
      ..projectProperties(cameraWidth: 64, cameraHeight: 48)
      ..clipProperties('next')
      ..clipHeader(width: 64, height: 48)
      ..layerHead('A', end: 0, count: 1, layerId: 901)
      ..layerExt(const {})
      ..zchkSlot(srawRecord(List<int>.filled(64 * 48, 0), 64, 48))
      ..clipConfig();
    hand(tvpp.uri, b.bytes);
    final projects = await pumpApp(tester);

    await openDocument(
      tester,
      projects,
      tvpp,
      done: () => projects.sessions.length == 2,
    );

    expect(projects.sessions, hasLength(2));
    expect(projects.active.repository.requireProject().name, 'next');
    expect(projects.active.projectFile.path, isNull);
  });

  testWidgets('🎯the next run reopens a Drive project from Recents — through '
      'its document, under the name the row kept', (tester) async {
    deleteAfterSessionEnds(folder);
    hand(drive.uri, await projectBytes(tester));
    final seeded = const RecentProjects().withOpened(
      RecentProject(path: drive.uri, displayName: 'Cut.anicel'),
    );
    AppRecent.projects.value = seeded;
    RecentProjectsStore().save(seeded);
    final projects = await pumpApp(tester);

    await tapKey(tester, 'top-strip-project-button');
    final recents = find.byKey(const ValueKey<String>('menu-recent-projects'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(recents));
    await tester.pumpAndSettle();
    expect(find.text('Cut'), findsWidgets, reason: 'the row says its name');
    await tester.tap(find.byKey(ValueKey<String>('menu-recent-${drive.uri}')));
    await until(tester, () => projects.sessions.length == 2);

    final path = projects.active.projectFile.path;
    expect(path, ProviderDocuments.workingCopyOf(drive.uri));
    expect(path, endsWith('/Cut.anicel'));
  });
}
