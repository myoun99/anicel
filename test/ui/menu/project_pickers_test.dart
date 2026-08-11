import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';

/// PICK-2/PICK-3: the project open and Save-As flows on the platforms that
/// ask for a folder.
///
/// These are new because the flow they cover had NO test at all. Both
/// injection seams on `EditorTopStrip` were declared and never used — by
/// anything, in lib or test — so a green suite said nothing whatsoever about
/// opening or saving a project. The in-app browser this replaces was the only
/// piece of it with coverage, and it is gone.
///
/// Everything here drives the real widgets: a tap on the row, typed text in
/// the field, a tap on Replace. A test that called the callbacks directly
/// would survive the dialog losing its buttons.
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_pickers_');
    debugUseFolderPickerOverride = true;
    // The fake carries a BOOKMARK. Without one, replacing `grant.bookmark`
    // with a hardcoded null anywhere in the pick functions left the whole
    // suite green — and on iPad that mutation stores every recent-projects
    // entry without its security-scoped token, so after relaunch every
    // remembered project is refused. That is the exact failure the folder
    // model exists to prevent, so it is pinned.
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async =>
        FolderGrant.granted(
          path: folder.path.replaceAll('\\', '/'),
          bookmark: 'BOOK==',
        );
  });
  tearDown(() {
    debugUseFolderPickerOverride = null;
    FolderPicker.debugFolderPicker = null;
    try {
      folder.deleteSync(recursive: true);
    } on Object {
      // A leaked handle on Windows must not fail the suite.
    }
  });

  void writeProject(String name, {DateTime? modified}) {
    final file = File('${folder.path}/$name')..writeAsStringSync('x');
    if (modified != null) {
      file.setLastModifiedSync(modified);
    }
  }

  /// Runs [action] from inside a real Navigator + ScaffoldMessenger, which
  /// the flows need for their dialogs and their error snackbar.
  Future<ProjectPick?> runFlow(
    WidgetTester tester,
    Future<ProjectPick?> Function(BuildContext context) action,
  ) async {
    ProjectPick? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await action(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    // Settled TWICE. The flow crosses two async gaps before a dialog exists
    // — the injected picker's future, then `showDialog` — and a single
    // settle can return between them, so the caller finds no dialog. It
    // passed alone and failed once in a six-file run, which is the shape of
    // that race rather than of a real defect.
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    return result;
  }

  group('opening', () {
    testWidgets('one project still goes through the chooser', (tester) async {
      // REPLACES 'a folder with one project opens it directly'. The skip made
      // what came back after picking a folder depend on a count the user
      // could not see; the window now opens whatever is in there. The
      // bookmark assertion stays — it rides through the chooser too.
      writeProject('only.anicel');
      ProjectPick? pick;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => pick = await pickProjectToOpen(context),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('project-chooser-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.text('only.anicel'));
      await tester.pumpAndSettle();
      expect(pick?.path, '${folder.path.replaceAll('\\', '/')}/only.anicel');
      expect(pick?.folderBookmark, 'BOOK==');
    });

    test('the folder picker applies to exactly three platforms', () {
      // Every widget test here sets debugUseFolderPickerOverride, so the
      // platform tuple behind it is never evaluated by them. Pinned directly:
      // dropping macOS or iOS from it sends them back to the OS FILE dialog,
      // which grants the project file and leaves its sibling .assets/ folder
      // outside the grant.
      for (final platform in ['android', 'ios', 'macos']) {
        expect(folderPickerAppliesTo(platform), isTrue, reason: platform);
      }
      for (final platform in ['windows', 'linux', 'fuchsia']) {
        expect(folderPickerAppliesTo(platform), isFalse, reason: platform);
      }
    });

    testWidgets('a folder with several asks which', (tester) async {
      writeProject('a.anicel', modified: DateTime(2026, 1, 1));
      writeProject('b.anicel', modified: DateTime(2026, 8, 11));
      ProjectPick? pick;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => pick = await pickProjectToOpen(context),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('project-chooser-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.text('a.anicel'));
      await tester.pumpAndSettle();
      expect(pick?.path,endsWith('/a.anicel'));
    });

    testWidgets('cancelling the folder pick opens nothing', (tester) async {
      writeProject('only.anicel');
      FolderPicker.debugFolderPicker =
          ({String? initialDirectory}) async => const FolderGrant.cancelled();
      expect(await runFlow(tester, pickProjectToOpen), isNull);
    });

    testWidgets('a folder with no projects says so', (tester) async {
      final pick = await runFlow(tester, pickProjectToOpen);
      expect(
        find.byKey(const ValueKey<String>('project-chooser-empty')),
        findsOneWidget,
      );
      expect(pick, isNull);
    });
  });

  group('saving', () {
    Future<ProjectPick?> runSave(WidgetTester tester, String suggested) =>
        runFlow(
          tester,
          (context) => pickProjectSaveTarget(context, suggested, folder.path),
        );

    testWidgets('the folder grant is followed by a name prompt', (
      tester,
    ) async {
      // iOS has no save panel — Apple never shipped one — so the name is
      // asked in-app on every folder-picking platform.
      ProjectPick? pick;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => pick = await pickProjectSaveTarget(
                  context,
                  'Suggested.anicel',
                  folder.path,
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('project-save-name-dialog')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('project-save-name-field')),
        'Cut 12',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('project-save-name-confirm')),
      );
      await tester.pumpAndSettle();
      expect(pick?.path, '${folder.path.replaceAll('\\', '/')}/Cut 12.anicel');
      expect(pick?.folderBookmark, 'BOOK==');
    });

    testWidgets('a name that already ends in .anicel is not doubled', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => pickProjectSaveTarget(
                  context,
                  'x.anicel',
                  folder.path,
                ).then((value) => _captured = value),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('project-save-name-field')),
        'Scene.anicel',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('project-save-name-confirm')),
      );
      await tester.pumpAndSettle();
      expect(_captured?.path, endsWith('/Scene.anicel'));
      expect(_captured?.path, isNot(contains('.anicel.anicel')));
    });

    testWidgets('an empty name is refused rather than saved', (tester) async {
      await runSave(tester, 'Suggested.anicel');
      await tester.enterText(
        find.byKey(const ValueKey<String>('project-save-name-field')),
        '   ',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('project-save-name-confirm')),
      );
      await tester.pumpAndSettle();
      // Still open: the prompt reports the error instead of popping.
      expect(
        find.byKey(const ValueKey<String>('project-save-name-dialog')),
        findsOneWidget,
      );
    });

    testWidgets('overwriting an existing project asks first', (tester) async {
      // The system save dialog would normally ask this. It is not in this
      // flow, so the app has to.
      writeProject('Taken.anicel');
      ProjectPick? pick;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => pick = await pickProjectSaveTarget(
                  context,
                  'x.anicel',
                  folder.path,
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('project-save-name-field')),
        'Taken',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('project-save-name-confirm')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('project-save-replace-dialog')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('project-save-replace-cancel')),
      );
      await tester.pumpAndSettle();
      expect(pick?.path,isNull, reason: 'declining Replace must not save');
    });

    testWidgets('confirming Replace returns the target', (tester) async {
      writeProject('Taken.anicel');
      ProjectPick? pick;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => pick = await pickProjectSaveTarget(
                  context,
                  'x.anicel',
                  folder.path,
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('project-save-name-field')),
        'Taken',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('project-save-name-confirm')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('project-save-replace-confirm')),
      );
      await tester.pumpAndSettle();
      expect(pick?.path, endsWith('/Taken.anicel'));
      // The Replace branch is a SEPARATE return statement from the plain
      // save, so it needs its own assertion or the bookmark can be dropped
      // on exactly that path.
      expect(pick?.folderBookmark, 'BOOK==');
    });

    testWidgets('cancelling the folder pick never asks for a name', (
      tester,
    ) async {
      FolderPicker.debugFolderPicker =
          ({String? initialDirectory}) async => const FolderGrant.cancelled();
      expect(await runSave(tester, 'x.anicel'), isNull);
      expect(
        find.byKey(const ValueKey<String>('project-save-name-dialog')),
        findsNothing,
      );
    });
  });

  group('a folder with no filesystem path', () {
    testWidgets('is explained rather than silently ignored', (tester) async {
      // Android's Drive / SD / USB case. Collapsing it into a silent cancel
      // would leave the user tapping Open and nothing happening.
      FolderPicker.debugFolderPicker = ({String? initialDirectory}) async =>
          const FolderGrant.noFilesystemPath();
      final pick = await runFlow(tester, pickProjectToOpen);
      expect(pick, isNull);
      expect(
        find.byKey(const ValueKey<String>('folder-no-path-dialog')),
        findsOneWidget,
      );
    });
  });
}

ProjectPick? _captured;
