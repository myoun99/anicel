import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';

/// PICK-6: the project open and Save-As flows, now that a project is ONE
/// file.
///
/// Rewritten from the folder-grant version. Everything it pinned — the
/// chooser window, the in-app name prompt, the overwrite confirmation, the
/// three-platform routing tuple — was scaffolding around two facts that
/// stopped being true: a project had siblings, and iOS could not ask for a
/// name. It has neither now.
///
/// What survives is the assertion those tests were really for: **the
/// bookmark rides through**. Replacing it with a hardcoded null anywhere in
/// these functions must fail here, because on Apple that mutation stores
/// every recent-projects entry without its security-scoped token and every
/// remembered project is refused after relaunch.
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_pickers_');
  });
  tearDown(() {
    FolderPicker.debugFilePicker = null;
    FolderPicker.debugFileExporter = null;
    try {
      folder.deleteSync(recursive: true);
    } on Object {
      // A leaked handle on Windows must not fail the suite.
    }
  });

  void installFilePicker(List<FolderGrant> answer) {
    FolderPicker.debugFilePicker =
        ({
          required List<XTypeGroup> acceptedTypeGroups,
          required bool allowMultiple,
        }) async => answer;
  }

  /// Runs [action] from inside a real Navigator + ScaffoldMessenger, which
  /// the flows need for their notices.
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
    // Settled TWICE: the flow crosses two async gaps before a dialog can
    // exist, and a single settle can return between them.
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    return result;
  }

  group('opening', () {
    testWidgets('the picked file IS the project, chooser and all gone', (
      tester,
    ) async {
      installFilePicker(const [
        FolderGrant.granted(
          path: '/work/C-045/scene.anicel',
          bookmark: 'BOOK==',
          kind: GrantKind.file,
        ),
      ]);
      final pick = await runFlow(tester, pickProjectToOpen);
      expect(pick?.path, '/work/C-045/scene.anicel');
      // The bookmark is what makes a recent-projects entry outlive a
      // relaunch. Dropping it here would be invisible until the next launch.
      expect(pick?.folderBookmark, 'BOOK==');
      // Nothing asks WHICH project any more — there is no folder to look in.
      expect(
        find.byKey(const ValueKey<String>('project-chooser-dialog')),
        findsNothing,
      );
    });

    testWidgets('cancelling opens nothing', (tester) async {
      installFilePicker(const [FolderGrant.cancelled()]);
      expect(await runFlow(tester, pickProjectToOpen), isNull);
    });

    testWidgets('a location with no filesystem path is explained', (
      tester,
    ) async {
      // Android's Drive / SD / USB case. Collapsing it into a silent cancel
      // would leave the user tapping Open and nothing happening.
      installFilePicker(const [FolderGrant.noFilesystemPath()]);
      final pick = await runFlow(tester, pickProjectToOpen);
      expect(pick, isNull);
      expect(
        find.byKey(const ValueKey<String>('folder-no-path-dialog')),
        findsOneWidget,
      );
    });
  });

  group('saving', () {
    String? offeredSource;
    String? offeredName;

    void installExporter(FolderGrant Function(String sourcePath) answer) {
      offeredSource = null;
      offeredName = null;
      FolderPicker.debugFileExporter =
          ({required String sourcePath, String? suggestedName}) async {
            offeredSource = sourcePath;
            offeredName = suggestedName;
            return answer(sourcePath);
          };
    }

    Future<ProjectPick?> runSave(WidgetTester tester, String suggested) =>
        runFlow(
          tester,
          (context) => pickProjectSaveTarget(context, suggested, folder.path),
        );

    testWidgets('the system dialog decides name and place — no in-app prompt', (
      tester,
    ) async {
      installExporter(
        (_) => const FolderGrant.granted(
          path: '/drive/Cut 12.anicel',
          bookmark: 'BOOK==',
          kind: GrantKind.file,
        ),
      );
      final pick = await runSave(tester, 'Suggested');
      expect(pick?.path, '/drive/Cut 12.anicel');
      expect(pick?.folderBookmark, 'BOOK==');
      // Both prompts existed only because iOS had no save panel. The export
      // picker asks for the name itself, and the system asks about
      // replacing.
      expect(
        find.byKey(const ValueKey<String>('project-save-name-dialog')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('project-save-replace-dialog')),
        findsNothing,
      );
    });

    testWidgets('what is offered is a PLACEHOLDER, not the project', (
      tester,
    ) async {
      // 🚨The whole reason this indirection exists: a finished project can be
      // gigabytes now that media lives inside it, and staging one in the app
      // container would need the space twice — then fail AFTER the user
      // chose a name and a place. Handing over anything project-sized here
      // would put that failure back.
      late int offeredLength;
      late List<int> offeredBytes;
      installExporter((sourcePath) {
        final file = File(sourcePath);
        offeredLength = file.lengthSync();
        offeredBytes = file.readAsBytesSync();
        return const FolderGrant.granted(
          path: '/drive/x.anicel',
          kind: GrantKind.file,
        );
      });
      await runSave(tester, 'x');
      // An empty but VALID zip: the 22-byte end-of-central-directory record.
      expect(offeredLength, 22);
      expect(offeredBytes.take(4), [0x50, 0x4B, 0x05, 0x06]);
    });

    testWidgets('the suffix is added once and only once', (tester) async {
      installExporter(
        (_) => const FolderGrant.granted(
          path: '/drive/x.anicel',
          kind: GrantKind.file,
        ),
      );
      await runSave(tester, 'Scene');
      expect(offeredName, 'Scene.anicel');

      await runSave(tester, 'Scene.anicel');
      expect(offeredName, 'Scene.anicel');
      expect(offeredName, isNot(contains('.anicel.anicel')));
    });

    testWidgets('cancelling saves nothing and leaves no staged file', (
      tester,
    ) async {
      installExporter((_) => const FolderGrant.cancelled());
      final pick = await runSave(tester, 'x');
      expect(pick, isNull);
      // The placeholder never left, so it must not be left behind either.
      expect(File(offeredSource!).existsSync(), isFalse);
      expect(Directory(offeredSource!).parent.existsSync(), isFalse);
    });

    testWidgets('a refused export says so rather than saving', (tester) async {
      installExporter((_) => const FolderGrant.noFilesystemPath());
      final pick = await runSave(tester, 'x');
      expect(pick, isNull);
      expect(
        find.byKey(const ValueKey<String>('folder-no-path-dialog')),
        findsOneWidget,
      );
    });
  });
}
