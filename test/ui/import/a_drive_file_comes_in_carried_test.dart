import 'dart:async';
import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/core/path_names.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/provider_documents.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/menu/opened_files_door.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/import_warnings.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/staged_carry.dart';
import '../../helpers/temp_dir.dart';
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
  Future<EditorSessionManager> openPicked(WidgetTester tester) async {
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
                  builder: (_) =>
                      ImportDialog(session: s, poolOnly: true, picked: picked),
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
  /// every file has landed. It waits out the wait window, so it ends by
  /// stopping [s]'s playback warmer (`pumpPastTheWaitWindow`) — for every
  /// test that imports through it.
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
    s.playbackRig.prerenderScheduler.cancel();
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

    // Both rows selected: a cell press speaks for every selected row.
    for (final row in ['A1.png', 'local.png']) {
      await tester.tap(find.byKey(ValueKey<String>('import-row-$row')));
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
      startsWith(AppText.strings.openWaitingCloudTemplate.split('{sec}').first),
      reason: 'the status line says whose work the wait is',
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
      find.byKey(const ValueKey<String>('import-file-table')),
      findsNothing,
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
}
