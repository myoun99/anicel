import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_documents.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/dialogs/folder_pick_flow.dart';

import '../../helpers/temp_dir.dart';

/// [handOverFilesForUser] on each road (drive-folder-windows-Q1 · F-221):
/// what the window answered becomes placed or declined, and what was placed
/// stands where the window said. Every road is reached from the Windows
/// workstation through the OS seam.
///
/// A desktop has no road — it is asked before anything is made — and that
/// is pinned where the roads are named (`folder_pick_flow_test.dart`).
void main() {
  late Directory temp;
  late Directory picked;
  late String file;
  late String folder;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('qa-hand-over-roads');
    picked = Directory('${temp.path}/picked')..createSync();
    file = (File('${temp.path}/frame_0001.png')..writeAsStringSync('a')).path;
    folder = (Directory('${temp.path}/CUT001')..createSync()).path;
    File('$folder/0001.png').writeAsStringSync('b');
  });

  tearDown(() {
    debugOperatingSystemOverride = null;
    debugDriveNoticeShown = false;
    AppStorage.debugAllFilesAccessOverride = null;
    FolderPicker.debugFolderPicker = null;
    FolderPicker.debugFileExporter = null;
    FolderPicker.debugFilesExporter = null;
    deleteTempQuietly(temp);
  });

  /// Hands [paths] over from a mounted context and answers what came of it.
  Future<HandOver?> handOver(WidgetTester tester, List<String> paths) async {
    HandOver? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await handOverFilesForUser(context, paths: paths);
            },
            child: const Text('hand over'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('hand over'));
    await tester.pumpAndSettle();
    return result;
  }

  /// Android's windows, counted: the save window that takes one file, and
  /// the folder window answering [picked] — or backed out of.
  ({List<String> saved, List<String?> askedFolder}) androidWindows({
    bool folderBackedOut = false,
  }) {
    debugOperatingSystemOverride = 'android';
    AppStorage.debugAllFilesAccessOverride = true;
    final saved = <String>[];
    final askedFolder = <String?>[];
    FolderPicker.debugFileExporter = ({
      required String sourcePath,
      String? suggestedName,
    }) async {
      saved.add(sourcePath);
      return FolderGrant.granted(path: sourcePath, kind: GrantKind.file);
    };
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
      askedFolder.add(initialDirectory);
      return folderBackedOut
          ? const FolderGrant.cancelled()
          : FolderGrant.granted(path: picked.path);
    };
    return (saved: saved, askedFolder: askedFolder);
  }

  testWidgets('iOS: backing out of the export picker declines', (
    tester,
  ) async {
    debugOperatingSystemOverride = 'ios';
    FolderPicker.debugFilesExporter = (sourcePaths) async =>
        const FolderGrant.cancelled();

    expect(await handOver(tester, [file, folder]), HandOver.declined);
  });

  testWidgets('Android: ONE file goes through the save window, and backing '
      'out of it declines', (tester) async {
    final windows = androidWindows();

    expect(await handOver(tester, [file]), HandOver.placed);
    expect(windows.saved, [file]);
    expect(windows.askedFolder, isEmpty, reason: 'one file asks no folder');

    FolderPicker.debugFileExporter = ({
      required String sourcePath,
      String? suggestedName,
    }) async => const FolderGrant.cancelled();
    expect(await handOver(tester, [file]), HandOver.declined);
  });

  testWidgets('🎯Android: ONE file is handed over with NO All-Files grant — '
      'it is poured where the save window says and never written again, so '
      'nothing of it needs a real path', (tester) async {
    final windows = androidWindows();
    AppStorage.debugAllFilesAccessOverride = false;

    expect(await handOver(tester, [file]), HandOver.placed);

    expect(windows.saved, [file]);
    expect(
      find.byKey(const ValueKey<String>('storage-grant-dialog')),
      findsNothing,
    );
  });

  testWidgets('Android: SEVERAL outputs still need it — a folder is written '
      'into through its real path — and are told so, not moved', (
    tester,
  ) async {
    final windows = androidWindows();
    AppStorage.debugAllFilesAccessOverride = false;
    HandOver? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await handOverFilesForUser(
                context,
                paths: [file, folder],
              );
            },
            child: const Text('hand over'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('hand over'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('storage-grant-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('storage-grant-cancel')));
    await tester.pumpAndSettle();

    expect(result, HandOver.declined);
    expect(windows.askedFolder, isEmpty, reason: 'the window never opened');
    expect(File(file).existsSync(), isTrue);
  });

  testWidgets('🎯Android: SEVERAL outputs are asked ONE folder window and '
      'moved into the folder it answers — a folder among them whole', (
    tester,
  ) async {
    final windows = androidWindows();

    expect(await handOver(tester, [file, folder]), HandOver.placed);

    expect(windows.askedFolder, hasLength(1));
    expect(windows.saved, isEmpty, reason: 'the save window takes one file');
    expect(File('${picked.path}/frame_0001.png').readAsStringSync(), 'a');
    expect(File('${picked.path}/CUT001/0001.png').readAsStringSync(), 'b');
    expect(File(file).existsSync(), isFalse, reason: 'moved, not copied');
    expect(Directory(folder).existsSync(), isFalse);
  });

  testWidgets('Android: backing out of the folder window declines and moves '
      'nothing', (tester) async {
    androidWindows(folderBackedOut: true);
    // What a backed-out folder window says about Google Drive is said once
    // a session, and is its own law's (`folder_pick_drive_notice_test`).
    debugDriveNoticeShown = true;

    expect(await handOver(tester, [file, folder]), HandOver.declined);

    expect(File(file).existsSync(), isTrue);
    expect(File('$folder/0001.png').existsSync(), isTrue);
    expect(picked.listSync(), isEmpty);
  });

  testWidgets('Android: ONE folder is not one file — it is asked the folder '
      'window, not put through the save window', (tester) async {
    final windows = androidWindows();

    expect(await handOver(tester, [folder]), HandOver.placed);

    expect(windows.saved, isEmpty);
    expect(windows.askedFolder, hasLength(1));
    expect(File('${picked.path}/CUT001/0001.png').readAsStringSync(), 'b');
  });
}
