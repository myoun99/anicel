import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_documents.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/dialogs/folder_pick_flow.dart';

import '../../helpers/temp_dir.dart';

/// [handOverFilesForUser] on each road (drive-folder-windows-Q1): what the
/// window answered becomes placed, offered or declined — and the answer
/// is what decides whether the caller keeps the outputs for another app to
/// read. Every road is reached from the Windows workstation through the OS
/// seam.
void main() {
  late Directory temp;
  late String file;
  late String folder;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('qa-hand-over-roads');
    file = (File('${temp.path}/frame_0001.png')..writeAsStringSync('a')).path;
    folder = (Directory('${temp.path}/CUT001')..createSync()).path;
    File('$folder/0001.png').writeAsStringSync('b');
  });

  tearDown(() {
    debugOperatingSystemOverride = null;
    AppStorage.debugAllFilesAccessOverride = null;
    FolderPicker.debugFolderPicker = null;
    FolderPicker.debugFileExporter = null;
    FolderPicker.debugFilesExporter = null;
    FolderPicker.debugFileSharer = null;
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

  testWidgets('iOS: backing out of the export picker declines', (
    tester,
  ) async {
    debugOperatingSystemOverride = 'ios';
    FolderPicker.debugFilesExporter = (sourcePaths) async =>
        const FolderGrant.cancelled();

    expect(await handOver(tester, [file, folder]), HandOver.declined);
  });

  testWidgets('Android: backing out of the save window declines', (
    tester,
  ) async {
    debugOperatingSystemOverride = 'android';
    AppStorage.debugAllFilesAccessOverride = true;
    FolderPicker.debugFileExporter = ({
      required String sourcePath,
      String? suggestedName,
    }) async => const FolderGrant.cancelled();

    expect(await handOver(tester, [file]), HandOver.declined);
  });

  testWidgets('Android: a share sheet that never came up declines, one that '
      'did offers', (tester) async {
    debugOperatingSystemOverride = 'android';
    var shows = false;
    final offered = <List<String>>[];
    FolderPicker.debugFileSharer = (paths) async {
      offered.add(paths);
      return shows;
    };

    expect(await handOver(tester, [file, folder]), HandOver.declined);
    shows = true;
    expect(await handOver(tester, [file, folder]), HandOver.offered);
    expect(offered.last, [file, folder]);
  });

  testWidgets('Android: ONE folder is not one file — it is shared, not put '
      'through the save window', (tester) async {
    debugOperatingSystemOverride = 'android';
    AppStorage.debugAllFilesAccessOverride = true;
    var saved = 0;
    FolderPicker.debugFileExporter = ({
      required String sourcePath,
      String? suggestedName,
    }) async {
      saved += 1;
      return FolderGrant.granted(path: sourcePath);
    };
    FolderPicker.debugFileSharer = (paths) async => true;

    expect(await handOver(tester, [folder]), HandOver.offered);
    expect(saved, 0);
  });

  testWidgets('the desktops: backing out of the folder window declines and '
      'moves nothing', (tester) async {
    debugOperatingSystemOverride = 'windows';
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async =>
        const FolderGrant.cancelled();

    expect(await handOver(tester, [file]), HandOver.declined);
    expect(File(file).existsSync(), isTrue);
  });
}
