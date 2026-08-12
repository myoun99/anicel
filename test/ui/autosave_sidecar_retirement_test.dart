import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/services/persistence/project_autosave_service.dart';
import 'package:anicel/src/services/persistence/recent_projects.dart';
import 'package:anicel/src/services/persistence/recent_projects_store.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';

/// A sidecar holds UNSAVED work, so it dies at every moment that work stops
/// existing: a manual save (it landed in the file), a close WITHOUT saving
/// (the user threw it away), and a DECLINED recovery (the user picked the
/// saved file over it).
///
/// Only the first of the three was implemented. The other two left the
/// sidecar alive, so the next open offered to restore exactly what the user
/// had discarded — and declining did not retire it either, which re-asked
/// the same question at every open until the next manual save. Moho ships
/// that bug; Krita and Adobe Animate both retire on a clean exit.
///
/// The point of retiring at ALL THREE is that a surviving sidecar then means
/// "this session died without any of them" — a crash — which is the entire
/// signal recovery reads. Miss one and the signal lies.
///
/// The widget tests here drive the real dialogs. The open and save paths hop
/// to a background isolate, which `pumpAndSettle` alone never advances, so
/// they lend the real event loop through [settleIsolate] — a handler test
/// would survive the dialog losing its buttons, which is exactly the class of
/// bug this round fixed.
void main() {
  late Directory folder;
  late String projectPath;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_sidecar_retire_');
    projectPath = '${folder.path.replaceAll('\\', '/')}/Cut 12.anicel';
    AppSave.settings.value = const AppSaveSettings();
    AppRecent.projects.value = const RecentProjects();
    RecentProjectsStore().save(const RecentProjects());
  });
  tearDown(() {
    AppSave.settings.value = const AppSaveSettings();
    AppRecent.projects.value = const RecentProjects();
    RecentProjectsStore().save(const RecentProjects());
    try {
      folder.deleteSync(recursive: true);
    } on Object {
      // A leaked handle on Windows must not fail the suite.
    }
  });

  /// The fixture's project name. Distinct from the shell's own starting
  /// project, so the repository holding it IS the proof that the open
  /// finished — the isolate hop makes "did it land yet" otherwise
  /// unobservable from a widget test.
  const openedName = 'Opened From Disk';

  /// A real, openable `.anicel` written WITHOUT the save service — the
  /// archive builder is a pure function, so the fixture needs no isolate and
  /// the widget tests can set up synchronously.
  void writeRealProject(String path) {
    File(path).writeAsBytesSync(
      buildAnicelArchiveBytes(
        project: createDefaultProject().copyWith(name: openedName),
        cels: const [],
      ),
    );
  }

  /// A sidecar that is NEWER than [path] — enough to arm the recovery
  /// prompt, whose condition is pure file metadata. Its bytes only matter
  /// when the user accepts, and these tests decline.
  String writeNewerSidecar(String path, {String bytes = 'not an archive'}) {
    final sidecar = '$path.autosave';
    File(sidecar).writeAsStringSync(bytes);
    File(sidecar).setLastModifiedSync(
      File(path).lastModifiedSync().add(const Duration(minutes: 5)),
    );
    return sidecar;
  }

  group('the law itself', () {
    test('retiring kills EVERY candidate location, not just the one the '
        'CURRENT setting names', () {
      // The sidecar-directory setting may have moved since a sidecar was
      // written, and the stale one is exactly the one that would go on
      // offering to restore discarded work.
      final custom = Directory('${folder.path}/elsewhere')..createSync();
      final beside = File('$projectPath.autosave')..writeAsStringSync('a');
      AppSave.settings.value = AppSaveSettings(
        sidecarDirectory: custom.path.replaceAll('\\', '/'),
      );
      final inCustom = File(AppSave.sidecarPathFor(projectPath))
        ..writeAsStringSync('b');
      expect(beside.path, isNot(inCustom.path));

      ProjectAutosaveService.retireSidecarsFor(projectPath);

      expect(beside.existsSync(), isFalse, reason: 'the old location too');
      expect(inCustom.existsSync(), isFalse);
    });

    test('retiring a project with no sidecar anywhere is silent', () {
      ProjectAutosaveService.retireSidecarsFor(projectPath);
    });
  });

  group('the session', () {
    test('discarding retires the open project\'s sidecar', () async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      await s.saveProjectToFile(projectPath);
      await s.writeAutosaveSnapshot(s.autosaveSidecarPath!);
      final sidecar = File(s.autosaveSidecarPath!);
      expect(sidecar.existsSync(), isTrue, reason: 'the tick wrote one');

      s.discardAutosaveSidecar();

      expect(sidecar.existsSync(), isFalse);
    });

    test('a NEVER-SAVED project has nothing to discard', () {
      // Its dirty ticks ask for a real file instead of writing a sidecar,
      // so there is no path to retire and no null to trip over.
      EditorSessionManager(
        initialProject: createDefaultProject(),
      ).discardAutosaveSidecar();
    });

    test('Save As retires the OLD path\'s sidecar in EVERY candidate '
        'location, not only the one the setting names now', () async {
      // The previous spelling of this test set no sidecar directory, so
      // "every candidate" collapsed to the single string it had already
      // captured and the whole thing passed against the pre-change code.
      // With a custom directory configured, the beside-the-file sidecar of
      // the abandoned path is a location only the new code reaches.
      final custom = Directory('${folder.path}/sidecars')..createSync();
      final s = EditorSessionManager(initialProject: createDefaultProject());
      await s.saveProjectToFile(projectPath);
      final beside = File('$projectPath.autosave')..writeAsStringSync('old');
      AppSave.settings.value = AppSaveSettings(
        sidecarDirectory: custom.path.replaceAll('\\', '/'),
      );
      final inCustom = File(AppSave.sidecarPathFor(projectPath))
        ..writeAsStringSync('newer');
      expect(beside.path, isNot(inCustom.path));

      await s.saveProjectToFile(
        '${folder.path.replaceAll('\\', '/')}/Cut 13.anicel',
      );

      expect(inCustom.existsSync(), isFalse);
      expect(
        beside.existsSync(),
        isFalse,
        reason: 'the location the setting no longer names still holds work',
      );
    });

    test('a RECOVERED session keeps its sidecar when closed without saving '
        '— it is the previous session\'s only copy', () async {
      // Recovery points every cel ref inside the sidecar and clears the RAM
      // tiers, and it arrives dirty with zero edits — so the exit gate
      // fires before the user has touched anything, with Close as the
      // primary button. Retiring there deletes the crash work at one tap.
      final s = EditorSessionManager(initialProject: createDefaultProject());
      await s.saveProjectToFile(projectPath);
      final sidecar = '$projectPath.autosave';
      await s.writeAutosaveSnapshot(sidecar);

      final recovered = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      await recovered.openProjectFromFile(sidecar, recoverAs: projectPath);
      recovered.discardAutosaveSidecar();

      expect(File(sidecar).existsSync(), isTrue);

      // And saving DOES retire it: the work is in the project file now, so
      // the exception ends with the reason for it.
      await recovered.saveProjectToFile(projectPath);
      expect(File(sidecar).existsSync(), isFalse);
    });

    test('an ordinary open does not inherit the recovery exception',
        () async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      await s.saveProjectToFile(projectPath);
      final sidecar = '$projectPath.autosave';
      await s.writeAutosaveSnapshot(sidecar);
      await s.openProjectFromFile(sidecar, recoverAs: projectPath);
      // …then opens something else the normal way.
      final other = '${folder.path.replaceAll('\\', '/')}/Cut 99.anicel';
      await s.saveProjectToFile(other);
      await s.openProjectFromFile(other);
      final otherSidecar = File('$other.autosave')..writeAsStringSync('x');

      s.discardAutosaveSidecar();

      expect(otherSidecar.existsSync(), isFalse);
    });

    test('an autosave tick stands down while a manual save runs', () async {
      // A tick that lands after the save's retirement leaves a sidecar for
      // a project that was saved and closed cleanly, and the next open then
      // offers to recover it. Sync deletion does not close that window —
      // it settles delete-versus-write, and this is write-versus-delete.
      final s = EditorSessionManager(initialProject: createDefaultProject());
      await s.saveProjectToFile(projectPath);
      s.createCut(); // Any command raises the dirty flag.
      var ticked = false;
      final autosave = ProjectAutosaveService(
        isDirty: () => s.hasUnsavedChanges && !s.autosaveShouldStandDown,
        writeSnapshot: (path) async {
          ticked = true;
          await s.writeAutosaveSnapshot(path);
        },
        autosavePath: () => s.autosaveSidecarPath!,
      );

      final saving = s.saveProjectToFile(projectPath);
      await autosave.tick();
      await saving;

      expect(ticked, isFalse, reason: 'the tick fired inside the save');
      expect(File('$projectPath.autosave').existsSync(), isFalse);
    });

    test('a plain Save As still retires the old path\'s sidecar', () async {
      // Otherwise the ORIGINAL keeps a sidecar nobody will ever retire —
      // the work moved to a new file, so reopening the old one would offer
      // to restore a session that no longer belongs to it.
      final s = EditorSessionManager(initialProject: createDefaultProject());
      await s.saveProjectToFile(projectPath);
      await s.writeAutosaveSnapshot(s.autosaveSidecarPath!);
      final oldSidecar = File(s.autosaveSidecarPath!);
      expect(oldSidecar.existsSync(), isTrue);

      final newPath = '${folder.path.replaceAll('\\', '/')}/Cut 13.anicel';
      await s.saveProjectToFile(newPath);

      expect(oldSidecar.existsSync(), isFalse);
    });
  });

  group('the shell', () {
    /// Lends the REAL event loop until [ready], because the save and open
    /// paths finish on a background isolate and `pumpAndSettle` only turns
    /// the fake clock. Polls rather than sleeping a fixed span so a fast
    /// machine stays fast and a slow one still passes.
    Future<void> settleIsolate(
      WidgetTester tester,
      bool Function() ready,
    ) async {
      for (var attempt = 0; attempt < 200; attempt += 1) {
        await tester.pump();
        if (ready()) {
          return;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
      }
      await tester.pump();
    }

    Future<void> openProjectMenu(WidgetTester tester) async {
      final button = find.byKey(
        const ValueKey<String>('top-strip-project-button'),
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    /// Opens [projectPath] through the Recent row — the real menu, a real
    /// tap — and returns once the session has ADOPTED it, proven by the
    /// repository holding the fixture's project.
    ///
    /// Waiting on anything already true before the tap (the seeded recent
    /// list, say) passes instantly and leaves the session still on its
    /// starting project — which is a green test for a path never walked.
    Future<void> openThroughRecent(WidgetTester tester) async {
      final seeded = const RecentProjects().withOpened(
        RecentProject(path: projectPath),
      );
      AppRecent.projects.value = seeded;
      RecentProjectsStore().save(seeded);

      ProjectRepository? repository;
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(onRepositoryCreated: (r) => repository = r),
        ),
      );
      await tester.pumpAndSettle();
      await openProjectMenu(tester);
      await tester.tap(
        find.byKey(ValueKey<String>('menu-recent-$projectPath')),
      );
      await settleIsolate(
        tester,
        () => repository?.currentProject?.name == openedName,
      );
      await tester.pumpAndSettle();
      expect(
        repository?.currentProject?.name,
        openedName,
        reason: 'the rest of this test is meaningless without the open',
      );
    }

    testWidgets('Close on the exit gate retires the sidecar — discarding '
        'the work discards its snapshot', (tester) async {
      writeRealProject(projectPath);
      await openThroughRecent(tester);

      // Dirty again, and a sidecar for that dirt.
      final newFrame = find.byKey(const ValueKey<String>('new-frame-button'));
      await tester.ensureVisible(newFrame);
      await tester.pumpAndSettle();
      await tester.tap(newFrame);
      await tester.pumpAndSettle();
      final sidecar = File(writeNewerSidecar(projectPath));
      expect(sidecar.existsSync(), isTrue);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('system-exit-close')),
      );
      await tester.pumpAndSettle();

      expect(
        sidecar.existsSync(),
        isFalse,
        reason: '"저장 안 하고 닫기 = 버리기" is only literally true if the '
            'next open cannot resurrect what was discarded',
      );
    });

    testWidgets('declining recovery retires the sidecar — the answer is '
        'about THIS sidecar, not a deferral', (tester) async {
      writeRealProject(projectPath);
      final sidecar = File(writeNewerSidecar(projectPath));
      final seeded = const RecentProjects().withOpened(
        RecentProject(path: projectPath),
      );
      AppRecent.projects.value = seeded;
      RecentProjectsStore().save(seeded);

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      await openProjectMenu(tester);
      await tester.tap(
        find.byKey(ValueKey<String>('menu-recent-$projectPath')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('recover-autosave-dialog')),
        findsOneWidget,
        reason: 'a newer sidecar arms the prompt',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('recover-open-saved-button')),
      );
      await settleIsolate(tester, () => !sidecar.existsSync());

      expect(
        sidecar.existsSync(),
        isFalse,
        reason: 'left alive it re-asks at every open until the next save',
      );
    });

    testWidgets('a declined sidecar SURVIVES when the saved file will not '
        'open — that is when it is the last copy', (tester) async {
      // Retiring before the open succeeds would delete the user's only
      // remaining version of the work at exactly the moment the file they
      // chose instead turned out to be unreadable.
      File(projectPath).writeAsStringSync('not an archive either');
      final sidecar = File(writeNewerSidecar(projectPath));
      final seeded = const RecentProjects().withOpened(
        RecentProject(path: projectPath),
      );
      AppRecent.projects.value = seeded;
      RecentProjectsStore().save(seeded);

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      await openProjectMenu(tester);
      await tester.tap(
        find.byKey(ValueKey<String>('menu-recent-$projectPath')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('recover-open-saved-button')),
      );
      // Waits for the failure to surface rather than for a fixed span, so
      // the assertion is not just "we did not wait long enough".
      await settleIsolate(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
      await tester.pumpAndSettle();

      expect(sidecar.existsSync(), isTrue);
    });
  });
}
