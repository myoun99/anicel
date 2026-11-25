import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/import/import_warning.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/provider_documents.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/model_vocabulary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/import_warnings.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/wait_window.dart';

/// 🗣️H72 (유저 2026-11-24: 「갤탭 psd임포트 경고뜨면서 안됨.
/// 읽을수없다면서」): a file the import window could not read says WHY — the
/// provider's refusal, how far the file came, what kept a document from
/// being read — so a photo of the warning tells which road it took. Five
/// roads said only that it could not be read, or that it had no layers.
void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('anicel-says-why');
  });

  tearDown(() {
    ProviderDocuments.debugReset();
    deleteTempQuietly(temp);
  });

  /// The window handed [picked], as its door hands it — and given its turn
  /// to read what it was handed.
  Future<EditorSessionManager> openOn(
    WidgetTester tester,
    List<FolderGrant> picked,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ImportDialog(session: s, picked: picked)),
      ),
    );
    for (var tries = 0; tries < 20; tries += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return s;
  }

  /// Whether the warnings the status line opens say [line].
  Future<void> expectSaid(WidgetTester tester, WarningLine line) async {
    final notice = await openImportWarnings(tester);
    for (final words in [line.about!, '${line.says} (1)']) {
      expect(
        find.descendant(of: notice, matching: find.text(words)),
        findsOneWidget,
        reason: words,
      );
    }
  }

  testWidgets('🎯a Drive document the provider refuses says what the '
      'provider said', (tester) async {
    ProviderDocuments.debugChannel = (method, arguments) async =>
        switch (method) {
          'copyDocument' => {
            'status': 'unavailable',
            'error': 'SecurityException: Permission Denial',
          },
          _ => null,
        };

    await openOn(tester, const [
      FolderGrant.providerDocument(
        ProviderDocument(uri: 'content://drive/doc/1', name: 'layout.psd'),
      ),
    ]);

    await expectSaid(
      tester,
      ImportWarning.fileUnreadable(
        'layout.psd',
        'SecurityException: Permission Denial',
      ).partsFor(AppText.language),
    );
  });

  testWidgets('🎯a PSD that is no Photoshop document says it could not be '
      'read, and why — not that it has no layers to expand', (tester) async {
    final psd = File('${temp.path}/broken.psd')
      ..writeAsBytesSync(List<int>.generate(64, (i) => i));
    await openOn(tester, [
      FolderGrant.granted(path: psd.path, kind: GrantKind.file),
    ]);

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    await tester.pumpAndSettle();

    final notice = await openImportWarnings(tester);
    final read = ImportWarning.celUnreadable(
      'broken',
      '',
    ).partsFor(AppText.language);
    expect(
      find.descendant(
        of: notice,
        matching: find.textContaining(read.says.split('—').first.trim()),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: notice,
        matching: find.textContaining(
          partsOf(
            AppText.strings.imPsdNoLayers('broken'),
            about: 'broken',
          ).says,
        ),
      ),
      findsNothing,
    );
  });
}
