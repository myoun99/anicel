import 'dart:io';

import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/provider_documents.dart';
import 'package:anicel/src/ui/dialogs/app_confirm_dialog.dart';
import 'package:anicel/src/ui/dialogs/folder_pick_flow.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PICK-7: a picked FILE with no filesystem path — a Drive document on
/// Android — goes where it can be worked on, and is told where it cannot.
///
/// 🗣️유저 2026-09-27 (갤탭): 「클라우드에있는 fu 열려고하니까 이 위치에는
/// 폴더경로가 없다고 클라우드 서비스 동기화 앱 쓰라는데 … ios는 바로
/// 되게했는데 안드로이드는 어쩔수 없나?」 — a project OPENS from one now
/// (through a working copy); a door that needs a real file still says
/// what it said.
void main() {
  const noPath = ValueKey<String>('folder-no-path-dialog');
  const drive = ProviderDocument(
    uri: 'content://drive/doc/7',
    name: 'Cut.anicel',
    length: 12,
  );

  tearDown(() {
    FolderPicker.debugFilePicker = null;
    ProviderDocuments.debugReset();
  });

  void pickerAnswers(List<FolderGrant> grants) {
    FolderPicker.debugFilePicker =
        ({required acceptedTypeGroups, required allowMultiple}) async =>
            grants;
  }

  Future<void> run(
    WidgetTester tester,
    Future<void> Function(BuildContext context) pick,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => pick(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('🎯the PROJECT door takes a document — by its URI, with its '
      'name kept for what comes after', (tester) async {
    pickerAnswers(const [FolderGrant.providerDocument(drive)]);
    ProjectPick? picked;

    await run(tester, (context) async {
      picked = await pickProjectFile(
        context,
        supportedExtensions: const ['anicel', 'tvpp'],
      );
    });

    expect(find.byKey(noPath), findsNothing);
    expect(picked?.path, drive.uri);
    expect(picked?.placed, isFalse);
    expect(ProviderDocuments.nameOf(drive.uri), 'Cut.anicel');
  });

  testWidgets('a document is judged by its NAME — its URI says nothing of '
      'what it is', (tester) async {
    pickerAnswers(const [
      FolderGrant.providerDocument(
        ProviderDocument(uri: 'content://drive/doc/9', name: 'notes.txt'),
      ),
    ]);
    ProjectPick? picked;
    var answered = false;

    await run(tester, (context) async {
      picked = await pickProjectFile(
        context,
        supportedExtensions: const ['anicel', 'tvpp'],
      );
      answered = true;
    });

    expect(
      find.byKey(const ValueKey<String>('unsupported-file-notice')),
      findsOneWidget,
    );
    expect(
      tester.widget<AppConfirmDialog>(find.byType(AppConfirmDialog)).details,
      ['notes.txt'],
      reason: 'the refusal names the file the person picked, not its URI',
    );
    await tester.tap(find.byKey(const ValueKey<String>('app-notice-close')));
    await tester.pumpAndSettle();
    expect(answered, isTrue);
    expect(picked, isNull);
  });

  group('placing a written file into a document', () {
    String? poured;

    setUp(() {
      poured = null;
      FolderPicker.debugFileExporter =
          ({required String sourcePath, String? suggestedName}) async {
            poured = File(sourcePath).readAsStringSync();
            return const FolderGrant.providerDocument(drive);
          };
    });
    tearDown(() => FolderPicker.debugFileExporter = null);

    Future<bool> writeProject(String path) async {
      File(path).writeAsStringSync('the project');
      return true;
    }

    testWidgets('🎯Save As keeps what the picker poured in as the document\'s '
        'WORKING COPY — moved out of the staging folder, answered as a '
        'path', (tester) async {
      FolderGrant? placed;

      await run(tester, (context) async {
        placed = await placeStagedFileForUser(
          context,
          suggestedName: 'Cut.anicel',
          write: writeProject,
          keepsSavingThere: true,
        );
      });

      expect(poured, 'the project');
      final copy = placed?.path;
      expect(copy, isNotNull);
      expect(File(copy!).readAsStringSync(), 'the project');
      expect(ProviderDocuments.documentBehind(copy), drive);
      expect(ProviderDocuments.workingCopyOf(drive.uri), copy);
    });

    testWidgets('an export into a document keeps NO copy — nothing saves '
        'into it again', (tester) async {
      FolderGrant? placed;

      await run(tester, (context) async {
        placed = await placeStagedFileForUser(
          context,
          suggestedName: 'Cut.anicel',
          write: writeProject,
        );
      });

      expect(poured, 'the project');
      expect(placed?.document, drive);
      expect(placed?.path, isNull);
      expect(ProviderDocuments.workingCopyOf(drive.uri), isNull);
    });
  });

  testWidgets('🚨a door that needs a real file says what a Drive folder says '
      '— and keeps the real files picked beside the document', (tester) async {
    pickerAnswers(const [
      FolderGrant.providerDocument(drive),
      FolderGrant.granted(path: '/sdcard/Pictures/a.png', kind: GrantKind.file),
    ]);
    List<FolderGrant>? grants;

    await run(tester, (context) async {
      grants = await pickFileGrantsForUser(
        context,
        supportedExtensions: const ['png', 'anicel'],
        allowMultiple: true,
      );
    });

    expect(find.byKey(noPath), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('folder-no-path-close')));
    await tester.pumpAndSettle();
    expect(grants?.map((grant) => grant.path), ['/sdcard/Pictures/a.png']);
  });

  testWidgets('🎯a door that reads a document through a copy of its own '
      'takes it — and its NAME is kept, for the copy to be called what the '
      'provider calls it', (tester) async {
    pickerAnswers(const [
      FolderGrant.providerDocument(
        ProviderDocument(uri: 'content://drive/doc/3', name: 'A1.png'),
      ),
      FolderGrant.granted(path: '/sdcard/Pictures/a.png', kind: GrantKind.file),
    ]);
    List<FolderGrant>? grants;

    await run(tester, (context) async {
      grants = await pickFileGrantsForUser(
        context,
        supportedExtensions: const ['png'],
        allowMultiple: true,
        acceptsDocuments: true,
      );
    });

    expect(find.byKey(noPath), findsNothing);
    expect(grants?.map((grant) => grant.document?.uri ?? grant.path), [
      'content://drive/doc/3',
      '/sdcard/Pictures/a.png',
    ]);
    expect(ProviderDocuments.nameOf('content://drive/doc/3'), 'A1.png');
  });
}
