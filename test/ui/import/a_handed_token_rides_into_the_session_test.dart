import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/wait_window.dart';

/// 🚨PICK-5: on Apple a referenced file is refused after a relaunch unless
/// the app kept the security-scoped token the pick granted — and the
/// import window is the only place that ever holds the pick's answer. Since
/// F-282 the window no longer picks: the one door hands it the grants
/// (`ImportDialog.picked`), and the token has to ride in with them.
void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('qa_token_'));
  tearDown(() => deleteTempQuietly(folder));

  testWidgets('a file handed over with its token is imported with the token '
      'held by the session — and a handed path with none adds nothing', (
    tester,
  ) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final picked = (await tester.runAsync(
      () => writeSolidPng(folder, 'ref.png'),
    ))!;
    final dropped = (await tester.runAsync(
      () => writeSolidPng(folder, 'loose.png'),
    ))!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(
            session: s,
            poolOnly: true,
            picked: [
              FolderGrant.granted(
                path: picked,
                bookmark: 'BOOK==',
                kind: GrantKind.file,
              ),
              FolderGrant.granted(path: dropped, kind: GrantKind.file),
            ],
          ),
        ),
      ),
    );
    await settleLoadedPages(tester);

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);

    expect([
      for (final grant in s.mediaGrants.debugMediaGrants) grant.bookmark,
    ], ['BOOK==']);
    expect(s.mediaGrants.debugMediaGrants.single.path, picked);
    expect(
      s.mediaPool.mediaAssets,
      hasLength(2),
      reason: 'CONTROL: both came in',
    );
    s.playbackRig.prerenderScheduler.cancel();
  });
}
