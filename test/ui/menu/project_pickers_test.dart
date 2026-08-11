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
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async =>
        FolderGrant.granted(path: folder.path.replaceAll('\\', '/'));
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
    await tester.pumpAndSettle();
    return result;
  }

  group('opening', () {
    testWidgets('a folder with one project opens it directly', (tester) async {
      writeProject('only.anicel');
      final pick = await runFlow(tester, pickProjectToOpen);
      expect(pick?.path, '${folder.path.replaceAll('\\', '/')}/only.anicel');
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
      expect(pick?.path,'${folder.path.replaceAll('\\', '/')}/Cut 12.anicel');
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
      expect(pick?.path,endsWith('/Taken.anicel'));
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
