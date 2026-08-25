import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart'
    show anicelProjectSuffix;
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
    FolderPicker.debugSaveDestinationPicker = null;
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

  group('saving, desktop (a real save dialog answers with a path)', () {
    // Pinned, not inherited: the local machine and the Windows/Linux CI
    // shards are desktop anyway, but the macOS runner is DESKTOP HARDWARE
    // on a SCOPED platform — there the scoped branch runs and this
    // group's seam is never consulted (first seen on the Apple workflow,
    // which skips lib/test-only pushes and surfaced it days late).
    setUp(() => FolderPicker.debugOperatingSystem = 'windows');
    tearDown(() => FolderPicker.debugOperatingSystem = null);

    String? askedName;

    void installDestinationPicker(FolderGrant answer) {
      askedName = null;
      FolderPicker.debugSaveDestinationPicker =
          ({required String suggestedName, String? initialDirectory}) async {
            askedName = suggestedName;
            return answer;
          };
    }

    Future<ProjectPick?> runSave(WidgetTester tester, String suggested) =>
        runFlow(
          tester,
          (context) => pickProjectSaveTarget(context, suggested, folder.path),
        );

    testWidgets('the dialog decides name and place; nothing is staged and '
        'nothing moves', (tester) async {
      // The old shape staged a 22-byte placeholder in the system temp and
      // renamed it onto the answer — which cannot cross volumes (Save As to
      // any drive but the temp's failed, OS error 17, measured) and which
      // replaced the LIVE project with 22 bytes when the dialog pointed at
      // it. A path is the whole answer on desktop.
      installDestinationPicker(
        const FolderGrant.granted(
          path: '/drive/Cut 12.anicel',
          kind: GrantKind.file,
        ),
      );
      final pick = await runSave(tester, 'Suggested');
      expect(askedName, 'Suggested$anicelProjectSuffix');
      expect(pick?.path, '/drive/Cut 12.anicel');
      expect(
        find.byKey(const ValueKey<String>('save-as-replace-dialog')),
        findsNothing,
      );
    });

    testWidgets('a bare typed name gets the suffix', (tester) async {
      installDestinationPicker(
        FolderGrant.granted(
          path: '${folder.path.replaceAll('\\', '/')}/Typed Name',
          kind: GrantKind.file,
        ),
      );
      final pick = await runSave(tester, 'Typed Name');
      expect(
        pick?.path,
        '${folder.path.replaceAll('\\', '/')}/Typed Name$anicelProjectSuffix',
      );
      // The suffixed spot is free, so no question to re-ask.
      expect(
        find.byKey(const ValueKey<String>('save-as-replace-dialog')),
        findsNothing,
      );
    });

    /// F-14's residual half: the system dialog's replace prompt ran against
    /// the TYPED name, so "type Foo over an existing Foo.anicel" silently
    /// overwrote a project nobody was asked about. Appending the suffix
    /// claims a different path — when that path is taken, the question is
    /// asked again about the real target.
    testWidgets('appending the suffix onto a TAKEN name re-asks the replace '
        'question', (tester) async {
      final victim = File('${folder.path}/Typed Name$anicelProjectSuffix')
        ..writeAsBytesSync(List<int>.filled(30, 7));
      installDestinationPicker(
        FolderGrant.granted(
          path: '${folder.path.replaceAll('\\', '/')}/Typed Name',
          kind: GrantKind.file,
        ),
      );

      ProjectPick? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await pickProjectSaveTarget(
                      context,
                      'Typed Name',
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
        find.byKey(const ValueKey<String>('save-as-replace-dialog')),
        findsOneWidget,
      );

      // Declining keeps the other project whole and saves nothing.
      await tester.tap(
        find.byKey(const ValueKey<String>('save-as-replace-cancel')),
      );
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(victim.readAsBytesSync().first, 7);

      // Accepting claims it.
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('save-as-replace-confirm')),
      );
      await tester.pumpAndSettle();
      expect(
        result?.path,
        '${folder.path.replaceAll('\\', '/')}/Typed Name$anicelProjectSuffix',
      );
    });

    testWidgets('cancelling saves nothing', (tester) async {
      installDestinationPicker(const FolderGrant.cancelled());
      expect(await runSave(tester, 'x'), isNull);
    });
  });

  group('saving, scoped (no save panel — the export picker moves a staged '
      'file)', () {
    String? offeredSource;
    String? offeredName;

    setUp(() {
      FolderPicker.debugOperatingSystem = 'ios';
    });
    tearDown(() {
      FolderPicker.debugOperatingSystem = null;
    });

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

    Future<ProjectPick?> runSave(
      WidgetTester tester,
      String suggested, {
      String? currentProjectPath,
    }) => runFlow(
      tester,
      (context) => pickProjectSaveTarget(
        context,
        suggested,
        folder.path,
        currentProjectPath: currentProjectPath,
      ),
    );

    testWidgets('a never-saved project offers the minimal valid archive', (
      tester,
    ) async {
      // Nothing exists to copy yet, and a valid empty zip means anything
      // opening the spot before the save lands reads an empty project
      // rather than a corrupt file.
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
      expect(offeredLength, 22);
      expect(offeredBytes.take(4), [0x50, 0x4B, 0x05, 0x06]);
    });

    testWidgets('a SAVED project offers the live archive, whole — never a '
        'decoy', (tester) async {
      // 🚨The picker MOVES its source over whatever the user points it at.
      // With a placeholder staged, pointing Save As at the CURRENT project
      // file replaced the only copy of every clean cel with 22 bytes before
      // the save could read them, and pointing it at any other project left
      // a 22-byte husk if the save then failed. With the real bytes staged,
      // the destination holds a complete archive until the save lands.
      final current = File('${folder.path}/live.anicel')
        ..writeAsBytesSync(List<int>.generate(64, (i) => i), flush: true);
      List<int>? offeredBytes;
      installExporter((sourcePath) {
        offeredBytes = File(sourcePath).readAsBytesSync();
        return const FolderGrant.granted(
          path: '/drive/elsewhere.anicel',
          kind: GrantKind.file,
        );
      });

      late BuildContext flowContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              flowContext = context;
              return const SizedBox();
            },
          ),
        ),
      );
      // runAsync: staging COPIES the archive with real async dart:io, which
      // the fake test clock would otherwise never complete.
      final pick = await tester.runAsync(
        () => pickProjectSaveTarget(
          flowContext,
          'live',
          folder.path,
          currentProjectPath: current.path,
        ),
      );

      expect(offeredBytes, List<int>.generate(64, (i) => i));
      expect(
        current.existsSync(),
        isTrue,
        reason: 'a COPY was staged — the live file never moves',
      );
      expect(pick?.path, '/drive/elsewhere.anicel');
    });

    testWidgets('the suffix rides the suggested name', (tester) async {
      installExporter(
        (_) => const FolderGrant.granted(
          path: '/drive/x.anicel',
          kind: GrantKind.file,
        ),
      );
      await runSave(tester, 'Scene');
      expect(offeredName, 'Scene$anicelProjectSuffix');

      await runSave(tester, 'Scene$anicelProjectSuffix');
      expect(offeredName, 'Scene$anicelProjectSuffix');
      expect(offeredName, isNot(contains('.anicel.anicel')));
    });

    testWidgets('the placed path is kept AS-IS, suffix or not', (
      tester,
    ) async {
      // The security scope and the bookmark cover exactly the item the
      // picker placed. The old flow deleted a bare-named placement and
      // claimed the suffixed sibling — a path the sandbox refuses and a
      // bookmark naming a file that no longer existed. A bare-named project
      // is reachable; an unsaveable one is not.
      final placed = File('${folder.path}/Typed Name');
      installExporter((sourcePath) {
        File(sourcePath).renameSync(placed.path);
        return FolderGrant.granted(path: placed.path, kind: GrantKind.file);
      });

      final pick = await runSave(tester, 'Typed Name');

      expect(pick?.path, placed.path);
      expect(
        placed.existsSync(),
        isTrue,
        reason: 'the real save writes over THIS one — it claimed the spot',
      );
    });

    testWidgets('cancelling saves nothing and leaves no staged file', (
      tester,
    ) async {
      installExporter((_) => const FolderGrant.cancelled());
      final pick = await runSave(tester, 'x');
      expect(pick, isNull);
      // The staged file never left, so it must not be left behind either.
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
