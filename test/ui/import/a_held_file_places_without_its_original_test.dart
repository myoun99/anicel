import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';

import '../../helpers/solid_png_fixture.dart';
import '../../helpers/staged_carry.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/wait_window.dart';

/// 🐞F-282 ④ (유저 2026-10-04): 「동영상을 잘라내서 임포트시, 미디어풀에
/// 등록되는데, 그걸 다시 타임라인에 배치하려하면 파일을 읽지 못했다고 뜸」.
///
/// A piece cut on import keeps its bytes in the project and lets its file
/// go (`TrimmedPieces.secure`); a voice take never had one; a carried
/// file's original may have been deleted since. Every place from the pool
/// goes through the placement window, and the window waited for a FILE
/// before it let the doors read — doors that read the project's bytes
/// first.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-held-place');
  });
  tearDown(() => deleteTempQuietly(tempDir));

  testWidgets('a carried picture whose file is gone places again from the '
      'pool: the window waits for no file the doors do not read', (
    tester,
  ) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final path = (await tester.runAsync(
      () => writeSolidPng(tempDir, 'bg.png'),
    ))!;
    await s.mediaPool.importMediaFiles([path], copyIntoProject: true);
    expect(stagedCopyIn(s, path), isNotNull, reason: 'fixture: carried');
    await tester.runAsync(() => File(path).delete());
    expect(
      s.projectFile.projectHoldsMediaBytes(path),
      isTrue,
      reason: 'fixture: its bytes are the project\'s, and no file is there',
    );
    final layersBefore = s.requireActiveCut.layers.length;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [path], placeOnly: true),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    await tester.pumpAndSettle();

    expect(s.requireActiveCut.layers.length, layersBefore + 1);
    s.playbackRig.prerenderScheduler.cancel();
  });
}
