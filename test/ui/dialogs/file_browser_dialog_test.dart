import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_documents.dart';
import 'package:anicel/src/ui/dialogs/file_browser_dialog.dart';

/// SAVE-1c: the in-app file browser — the mobile open/save surface of
/// the real-path model.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('anicel-browser');
    AppStorage.debugAllFilesAccessOverride = true;
  });
  tearDown(() {
    AppStorage.debugAllFilesAccessOverride = null;
    root.deleteSync(recursive: true);
  });

  Future<String? Function()> open(
    WidgetTester tester, {
    required FileBrowserMode mode,
    String? suggestedName,
  }) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showAnicelFileBrowser(
                  context,
                  mode: mode,
                  suggestedName: suggestedName,
                  initialDirectory: root.path,
                ).then((value) => picked = value);
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return () => picked;
  }

  testWidgets('open mode: lists folders and .anicel files, navigates, and '
      'returns the tapped file', (tester) async {
    Directory('${root.path}/shots').createSync();
    File('${root.path}/shots/cut01.anicel').writeAsStringSync('x');
    File('${root.path}/notes.txt').writeAsStringSync('x');
    File('${root.path}/top.anicel').writeAsStringSync('x');

    final picked = await open(tester, mode: FileBrowserMode.open);
    expect(
      find.byKey(const ValueKey<String>('file-browser-entry-top.anicel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('file-browser-entry-notes.txt')),
      findsNothing,
      reason: 'open mode shows .anicel only',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('file-browser-entry-shots')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('file-browser-entry-cut01.anicel')),
    );
    await tester.pumpAndSettle();
    expect(picked()?.replaceAll('\\', '/'), endsWith('/shots/cut01.anicel'));
  });

  testWidgets('saveAs mode: name + Save returns the path (.anicel appended); '
      'New Folder creates and enters', (tester) async {
    final picked = await open(
      tester,
      mode: FileBrowserMode.saveAs,
      suggestedName: 'scene.anicel',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('file-browser-new-folder')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('file-browser-new-folder-name')),
      'ep01',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('file-browser-new-folder-create')),
    );
    await tester.pumpAndSettle();
    expect(Directory('${root.path}/ep01').existsSync(), isTrue);

    await tester.enterText(
      find.byKey(const ValueKey<String>('file-browser-name')),
      'cut05',
    );
    await tester.tap(find.byKey(const ValueKey<String>('file-browser-save')));
    await tester.pumpAndSettle();
    expect(picked()?.replaceAll('\\', '/'), endsWith('/ep01/cut05.anicel'));
  });

  testWidgets('the missing-permission notice shows with grant/recheck '
      'actions; Cancel closes empty-handed', (tester) async {
    AppStorage.debugAllFilesAccessOverride = false;
    final picked = await open(tester, mode: FileBrowserMode.open);
    expect(
      find.byKey(const ValueKey<String>('file-browser-grant')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('file-browser-recheck')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('file-browser-cancel')));
    await tester.pumpAndSettle();
    expect(picked(), isNull);
    expect(
      find.byKey(const ValueKey<String>('file-browser-dialog')),
      findsNothing,
    );
  });
}
