import 'dart:async';
import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/core/path_names.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/provider_documents.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/import/import_file_table.dart';
import 'package:anicel/src/ui/menu/opened_files_door.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/import_warnings.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/staged_carry.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/text_finders.dart';
import '../../helpers/wait_window.dart';

/// PICK-7 in the import window: a file picked from Google Drive on Android —
/// a document with no filesystem path — is read through a copy of its own
/// in this run's room and comes in CARRIED; the copy goes once its bytes
/// are the project's.
///
/// 🗣️유저 2026-09-27: 「안한것 다 해줘. 임포트 드라이브로 할때라던가」 — the
/// media import still answered a Drive file with 「이 위치에는 폴더 경로가
/// 없습니다」 after a project had learned to open from one.
void main() {
  const uri = 'content://drive/doc/1';
  const drive = ProviderDocument(uri: uri, name: 'A1.png');
  late Directory temp;
  late Map<String, String> documents;
  late List<String> copiedTo;
  late bool stopped;

  /// Holds a copy mid-way while it is open: true lets it land, false is
  /// the provider answering a stop.
  Completer<bool>? holdCopy;

  /// The native side's contract (`MainActivity.copyDocument`), over files.
  Future<Map<Object?, Object?>?> provider(
    String method,
    Map<String, Object?> arguments,
  ) async {
    switch (method) {
      case 'copyDocument':
        final destination = arguments['destinationPath']! as String;
        copiedTo.add(destination);
        if (!(await holdCopy?.future ?? true)) {
          return {'status': 'cancelled'};
        }
        File(documents[arguments['uri']]!).copySync(destination);
        return {
          'status': 'granted',
          'items': [
            {'path': destination},
          ],
        };
      case 'cancelDocumentCopy':
        stopped = true;
        if (holdCopy case final hold? when !hold.isCompleted) {
          hold.complete(false);
        }
        return null;
      case 'documentTransferred':
        return {'value': 0};
    }
    return null;
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('anicel-drive-import');
    documents = {};
    copiedTo = [];
    stopped = false;
    holdCopy = null;
    ProviderDocuments.debugChannel = provider;
  });

  tearDown(() {
    FolderPicker.debugFilePicker = null;
    ProviderDocuments.debugReset();
    deleteTempQuietly(temp);
  });

  void pickerAnswers(List<FolderGrant> grants) {
    FolderPicker.debugFilePicker =
        ({required acceptedTypeGroups, required allowMultiple}) async =>
            grants;
  }

  /// The one door's pick (F-282 — the window picks nothing itself), and the
  /// window opened on what it handed over, as the media panel's ＋ opens
  /// it — then the pick, and any copy it starts, given their turn to
  /// answer.
  Future<EditorSessionManager> openPicked(
    WidgetTester tester, {
    bool poolOnly = true,
  }) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final picked = await pickFilesToOpen(context);
                if (!context.mounted) {
                  return;
                }
                await showDialog<void>(
                  context: context,
                  builder: (_) => ImportDialog(
                    session: s,
                    poolOnly: poolOnly,
                    picked: picked,
                  ),
                );
              },
              child: const Text('import'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('import'));
    for (var tries = 0; tries < 20; tries += 1) {
      await tester.pump();
    }
    return s;
  }

  /// Presses Import and waits for the window to close — it closes once
  /// every file has landed.
  Future<void> runImport(WidgetTester tester, EditorSessionManager s) async {
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    final window = find.byKey(const ValueKey<String>('import-dialog'));
    // The fake clock too: the window leaves on its route's way out, which
    // only that clock plays. ↩️It lent the real loop alone, so the window
    // never left, and the whole patience ran out — sixty seconds a test
    // (10-19).
    final closed = await settleAsync(
      tester,
      () => window.evaluate().isEmpty,
      step: const Duration(milliseconds: 50),
    );
    expect(closed, isTrue, reason: 'the window closes once the files landed');
    await tester.pumpAndSettle();
  }

  Finder fileCell(String path) =>
      find.byKey(ValueKey<String>('import-cell-file-$path'));

  testWidgets('🎯a Drive file comes in CARRIED, called what Drive calls it — '
      'and the copy it was read through is gone once its bytes are the '
      'project\'s', (tester) async {
    final bytes = await tester.runAsync(() => writeSolidPng(temp, 'doc.png'));
    documents[uri] = bytes!;
    pickerAnswers(const [FolderGrant.providerDocument(drive)]);
    final s = await openPicked(tester);

    expect(
      find.byKey(const ValueKey<String>('folder-no-path-dialog')),
      findsNothing,
      reason: 'taken, not refused',
    );
    final copy = ProviderDocuments.workingCopyOf(uri);
    expect(copy, isNotNull);
    expect(fileNameOfPath(copy!), 'A1.png');
    expect(File(copy).readAsBytesSync(), File(bytes).readAsBytesSync());
    expect(
      find.text('A1.png'),
      findsOneWidget,
      reason: 'the source bar names the document — the room its copy lies '
          'in is nowhere the person keeps anything',
    );
    expect(find.text(copy), findsNothing);
    expect(
      find.descendant(of: fileCell(copy), matching: find.text('Keep')),
      findsOneWidget,
    );

    // ⚠️Brought into view first: the table scrolls sideways in a window too
    // narrow for it, and a tap that misses the cell would offer nothing
    // either — the findsNothing below would pass on a miss.
    await tester.ensureVisible(fileCell(copy));
    await tester.pump();
    await tester.tap(fileCell(copy));
    await settleLoadedPages(tester);
    expect(
      find.byKey(const ValueKey<String>('import-option-file-reference')),
      findsNothing,
      reason: 'a pointer at a copy that goes with the run points at nothing '
          'next time — the answer is locked, not offered',
    );

    await runImport(tester, s);

    final asset = s.mediaPool.mediaAssets.single;
    expect(asset.carried, isTrue);
    expect(asset.name, 'A1');
    expect(
      stagedCopyIn(s, asset.path),
      isNotNull,
      reason: 'the project holds the bytes (「품은 순간 데이터를 가지고」)',
    );
    expect(find.byKey(const ValueKey<String>('import-dialog')), findsNothing);
    expect(
      Directory(File(copy).parent.path).existsSync(),
      isFalse,
      reason: 'the copy it was read through is not a second copy that stays '
          '(「사본 남으면 진짜 용서안할게」)',
    );
    expect(ProviderDocuments.workingCopyOf(uri), isNull);
  });

  testWidgets('a file picked BESIDE a Drive file is still the person\'s to '
      'link — and Link pressed for both rows at once links only that one',
      (tester) async {
    final (local, bytes) = (await tester.runAsync(
      () async => (
        await writeSolidPng(temp, 'local.png'),
        await writeSolidPng(temp, 'doc.png'),
      ),
    ))!;
    documents[uri] = bytes;
    pickerAnswers([
      const FolderGrant.providerDocument(drive),
      FolderGrant.granted(path: local, kind: GrantKind.file),
    ]);
    final s = await openPicked(tester);
    final copy = ProviderDocuments.workingCopyOf(uri)!;

    await tester.ensureVisible(fileCell(copy));
    await tester.pump();
    await tester.tap(fileCell(copy));
    await settleLoadedPages(tester);
    expect(
      find.byKey(const ValueKey<String>('import-option-file-reference')),
      findsNothing,
    );

    // Both rows selected: a cell press speaks for every selected row. Each
    // is pressed on its NAME, brought back into view — the list is wider
    // than this window and was slid sideways to reach the cell above, so a
    // row's middle is no longer in the window (↩️it was pressed there until
    // the place column kept its room, F-582-Q1, and the press fell on the
    // barrier and closed the window).
    for (final path in [copy, local]) {
      final name = find.byKey(ValueKey<String>('import-name-$path'));
      await tester.ensureVisible(name);
      await tester.pump();
      await tester.tap(name);
      await settleLoadedPages(tester);
    }
    await tester.ensureVisible(fileCell(local));
    await tester.pumpAndSettle();
    await tester.tap(fileCell(local));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('import-option-file-reference')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: fileCell(local), matching: find.text('Link')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: fileCell(copy), matching: find.text('Keep')),
      findsOneWidget,
      reason: 'the answer the document cannot give does not stick to it',
    );

    await runImport(tester, s);

    final carried = {
      for (final asset in s.mediaPool.mediaAssets)
        fileNameOfPath(asset.path): asset.carried,
    };
    expect(carried, {'A1.png': true, 'local.png': false});
  });

  testWidgets('🚨Stop while the copy comes: nothing is listed, the file is '
      'named in the warnings the status line opens, and no folder is left in '
      'the room', (
    tester,
  ) async {
    holdCopy = Completer<bool>();
    pickerAnswers(const [FolderGrant.providerDocument(drive)]);
    await openPicked(tester);
    expect(copiedTo, hasLength(1), reason: 'the copy is under way');
    expect(
      tester
          .widget<ButtonStyleButton>(
            find.byKey(const ValueKey<String>('import-run-button')),
          )
          .onPressed,
      isNull,
      reason: 'nothing runs while the first file is still coming',
    );
    // The wait after a pick is said on the window's own status line — no
    // wait window stands over a pick.
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('import-status')))
          .data,
      startsWith(
        AppText.strings.openWaitingReadingTemplate.split('{sec}').first,
      ),
      reason: 'the status line says the wait — and the copy is bytes coming '
          'in, from the provider\'s network or its cache: the app cannot '
          'tell, so it says it is reading (F-621-Q2)',
    );

    await tester.tap(find.byKey(const ValueKey<String>('import-cancel-button')));
    for (var tries = 0; tries < 10; tries += 1) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(
      find.byKey(const ValueKey<String>('import-dialog')),
      findsOneWidget,
      reason: 'Cancel stopped the WAIT, not the window',
    );
    expect(
      tester.widget<ImportFileTable>(find.byType(ImportFileTable)).rows,
      isEmpty,
    );
    final notice = await openImportWarnings(tester);
    expect(
      find.descendant(of: notice, matching: find.text('A1.png')),
      findsOneWidget,
    );
    expect(Directory(File(copiedTo.single).parent.path).existsSync(), isFalse);
    expect(ProviderDocuments.workingCopyOf(uri), isNull);
  });

  group('the window closing while a Drive file is still coming', () {
    /// Closes the window while the copy is held mid-way — [asItCloses]
    /// runs in the same breath as the close, before anything settles.
    Future<void> closeMidCopy(
      WidgetTester tester, {
      void Function()? asItCloses,
    }) async {
      holdCopy = Completer<bool>();
      pickerAnswers(const [FolderGrant.providerDocument(drive)]);
      await openPicked(tester);
      expect(copiedTo, hasLength(1), reason: 'the copy is under way');

      await tester.tap(find.byKey(const ValueKey<String>('app-window-close')));
      asItCloses?.call();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('import-dialog')), findsNothing);
    }

    testWidgets('🚨STOPS the copy — nothing is left to take it, and a big '
        'file must not go on coming down for nobody', (tester) async {
      await closeMidCopy(tester);

      for (var tries = 0; tries < 10; tries += 1) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(stopped, isTrue);
      expect(
        Directory(File(copiedTo.single).parent.path).existsSync(),
        isFalse,
      );
    });

    testWidgets('a copy that lands in the same breath is let go of — no copy '
        'is left in the room', (tester) async {
      documents[uri] = (await tester.runAsync(
        () => writeSolidPng(temp, 'doc.png'),
      ))!;
      // The copy lands as the window closes — not after a settle that may
      // already have carried the stop down (the window's dispose asks for
      // one, and a settle that runs long enough delivers it).
      await closeMidCopy(tester, asItCloses: () => holdCopy!.complete(true));

      for (var tries = 0; tries < 10; tries += 1) {
        await tester.pump();
      }

      expect(stopped, isFalse, reason: 'it landed rather than being stopped');
      expect(
        Directory(File(copiedTo.single).parent.path).existsSync(),
        isFalse,
      );
      expect(ProviderDocuments.workingCopyOf(uri), isNull);
    });
  });

  testWidgets('a Drive file handed in beside a cut folder is named on the '
      'folder\'s left-out row — its copy come after the folder was read too', (
    tester,
  ) async {
    const notes = ProviderDocument(uri: uri, name: 'notes.png');
    final sep = Platform.pathSeparator;
    final (cel, bytes) = (await tester.runAsync(
      () async => (
        await writeSolidPng(temp, 'csm_13_069_lo${sep}A1.png'),
        await writeSolidPng(temp, 'doc.png'),
      ),
    ))!;
    documents[uri] = bytes;
    holdCopy = Completer<bool>();
    // What the door's pick keeps for the steps that have only the URI.
    ProviderDocuments.remember(notes);
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(
            session: s,
            picked: [
              FolderGrant.granted(
                path: File(cel).parent.path,
                kind: GrantKind.folder,
              ),
              const FolderGrant.providerDocument(notes),
            ],
          ),
        ),
      ),
    );
    List<ImportFileRow> rows() =>
        tester.widget<ImportFileTable>(find.byType(ImportFileTable)).rows;

    expect(
      await settleAsync(tester, () => rows().any((r) => r.path == 'folder:A')),
      isTrue,
      reason: 'premise: the folder is read while the copy is held',
    );
    expect(copiedTo, hasLength(1), reason: 'premise: the copy is under way');
    holdCopy!.complete(true);

    expect(
      await settleAsync(
        tester,
        () => rows().last.name.split(' · ').contains('notes.png'),
      ),
      isTrue,
    );
  });

  // 🗣️H71 (유저 2026-11-24): 「안드 파일임포트시 a1만열리고 그 뒤 a2부터
  // a18까지 연결임포트가 안됨. 파일은 구글드라이브에 있는 png파일염」 —
  // each copy is in a folder of its own, so no copy's folder lists the rest.
  group('a numbered run picked from Drive (H71)', () {
    /// The documents A1..A[count] on Drive, the same picture each, picked
    /// together — every one but those [local] names, which are picked as
    /// files on the device, in one folder.
    Future<List<FolderGrant>> picks(
      WidgetTester tester,
      int count, {
      Set<int> local = const {},
    }) async => (await tester.runAsync(() async {
      return [
        for (var at = 1; at <= count; at += 1)
          if (local.contains(at))
            FolderGrant.granted(
              path: await writeSolidPng(
                await Directory('${temp.path}/device').create(),
                'A$at.png',
              ),
              kind: GrantKind.file,
            )
          else
            FolderGrant.providerDocument(
              ProviderDocument(
                uri: 'content://drive/doc/a$at',
                name: 'A$at.png',
              ),
            ),
      ];
    }))!;

    Future<void> drive(WidgetTester tester, List<FolderGrant> grants) async {
      final bytes = await tester.runAsync(() => writeSolidPng(temp, 'a.png'));
      for (final grant in grants) {
        if (grant.document case final document?) {
          documents[document.uri] = bytes!;
        }
      }
      pickerAnswers(grants);
    }

    String pathOf(FolderGrant grant) =>
        grant.path ?? ProviderDocuments.workingCopyOf(grant.document!.uri)!;

    /// What [path]'s row says of its run, once it says A1–A[count] — or
    /// what it says when it never does.
    Future<String?> says(WidgetTester tester, String path, int count) async {
      String? option() {
        final text = find.descendant(
          of: find.byKey(ValueKey<String>('import-cell-option-$path')),
          matching: find.anyText(),
        );
        return text.evaluate().isEmpty
            ? null
            : tester.widget<Text>(text.first).data;
      }

      final span = AppText.strings.imRunSpan('A1', 'A$count', count);
      await settleAsync(
        tester,
        () => option() == span,
        step: const Duration(milliseconds: 50),
      );
      return option();
    }

    /// Whether the first of [grants]' row says the run of them all once
    /// measured, and no other picture of it stands as a row of its own.
    Future<void> oneRow(
      WidgetTester tester,
      List<FolderGrant> grants,
    ) async {
      final paths = [for (final grant in grants) pathOf(grant)];
      expect(
        await says(tester, paths.first, paths.length),
        AppText.strings.imRunSpan('A1', 'A${paths.length}', paths.length),
      );
      for (final brought in paths.skip(1)) {
        expect(
          find.byKey(ValueKey<String>('import-cell-option-$brought')),
          findsNothing,
          reason: '$brought is A1\'s row\'s — no row of its own',
        );
      }
    }

    testWidgets('🚨A1..A4 picked together come as one row of the run', (
      tester,
    ) async {
      final grants = await picks(tester, 4);
      await drive(tester, grants);
      await openPicked(tester, poolOnly: false);

      await oneRow(tester, grants);
    });

    testWidgets('A1 on the device and A2..A3 from Drive, picked together: '
        'the copies that come after A1 is read still run with it', (
      tester,
    ) async {
      final grants = await picks(tester, 3, local: {1});
      await drive(tester, grants);
      await openPicked(tester, poolOnly: false);

      await oneRow(tester, grants);
    });

    testWidgets('A1 and A2 on the device, measured as their run, then A3 '
        'from Drive: the run they were measured as takes it in', (
      tester,
    ) async {
      final grants = await picks(tester, 3, local: {1, 2});
      await drive(tester, grants);
      holdCopy = Completer<bool>();
      await openPicked(tester, poolOnly: false);
      expect(
        await says(tester, grants.first.path!, 2),
        AppText.strings.imRunSpan('A1', 'A2', 2),
        reason: 'premise: the device\'s two are measured as a run',
      );

      holdCopy!.complete(true);
      final copied = await settleAsync(
        tester,
        () =>
            ProviderDocuments.workingCopyOf(grants.last.document!.uri) != null,
      );
      expect(copied, isTrue, reason: 'premise: A3\'s copy came');

      await oneRow(tester, grants);
    });
  });
}
