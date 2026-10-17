import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/import_warnings.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/wait_window.dart';

/// 🚨★★★A PLACEMENT NAMES WHAT IT MAKES BY THE POOL'S NAME
/// (pool-name-without-extension).
///
/// 유저 2026-09-12: 「풀에서 이름이랑 확장자 나누고 이름변경시 이름만 변경 …
/// 해당 이름 대로 레이어 이름이나 이름/대사 만들어진다」. The landing rebuilt
/// the name from the PATH, so a file renamed in the pool was still placed
/// under its file name — extension and all.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-pool-name');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  Future<List<String>> placedRowNames(
    WidgetTester tester,
    EditorSessionManager s,
    String path,
  ) async {
    final before = {for (final layer in s.requireActiveCut.layers) layer.id};
    final landed = await tester.runAsync(
      () => s.importDoors.importImageFile(
        path: path,
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: false,
        spot: const AboveActiveLayerSpot(),
      ),
    );
    expect(landed, isTrue);
    return [
      for (final layer in s.requireActiveCut.layers)
        if (!before.contains(layer.id)) layer.name,
    ];
  }

  testWidgets('🚨a file renamed in the pool is placed under the POOL\'s '
      'name', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final written = await tester.runAsync(
      () => writeSolidPng(tempDir, 'bg_street.png', rgba: 0xAAAAAAAA),
    );
    // Registered the way the import window registers: the one spelling.
    final path = normalizedMediaPath(written!);
    await tester.runAsync(() => s.mediaPool.addMediaAssets([path]));
    s.mediaPool.renameMediaAsset(path, '거리');

    expect(await placedRowNames(tester, s, path), ['거리']);
    await tester.pumpAndSettle();
  });

  testWidgets('a file the pool has not seen is placed under its name '
      'WITHOUT the extension', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final written = await tester.runAsync(
      () => writeSolidPng(tempDir, 'bg_street.png', rgba: 0xAAAAAAAA),
    );

    expect(await placedRowNames(tester, s, written!), ['bg_street']);
    await tester.pumpAndSettle();
  });

  // 🗣️F-376 (유저 2026-10-17): 「미디어풀에서 이름바꾸고, 파일 타임라인등에
  // 배치할때 파일이름 표시되는게 다 바꾸기 전 이름임 … 법 통일하면서 해결」 —
  // the landing above took the pool's name, and the window placing it still
  // named the file from its path.
  group('the window placing it', () {
    Future<void> openPlacing(
      WidgetTester tester,
      EditorSessionManager s,
      String path,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(
              session: s,
              initialPaths: [path],
              placeOnly: true,
            ),
          ),
        ),
      );
      await settleLoadedPages(tester);
    }

    testWidgets('🚨names a file renamed in the pool as the pool does — in '
        'its title, its row and its preview', (tester) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final written = await tester.runAsync(
        () => writeSolidPng(tempDir, 'bg_street.png', rgba: 0xAAAAAAAA),
      );
      final path = normalizedMediaPath(written!);
      await tester.runAsync(() => s.mediaPool.addMediaAssets([path]));
      s.mediaPool.renameMediaAsset(path, '거리');

      await openPlacing(tester, s, path);

      expect(find.text(AppText.strings.imPlaceTitle('거리')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(ValueKey<String>('import-name-$path')))
            .data,
        '거리',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('canvas-document-name')),
          matching: find.text('거리'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('🚨and its warnings name it so', (tester) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final written = await tester.runAsync(() async {
        // A .png that is not a PNG: the file reads, and the decode is what
        // fails.
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}bg_street.png',
        );
        await file.writeAsBytes(const [1, 2, 3, 4, 5, 6, 7, 8]);
        return file.path;
      });
      final path = normalizedMediaPath(written!);
      s.cutCommandCoordinator.updateMediaAssets([
        MediaAsset(path: path, name: 'bg_street', kind: MediaAssetKind.image),
      ]);
      s.mediaPool.renameMediaAsset(path, '거리');
      await openPlacing(tester, s, path);

      await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
      await pumpPastTheWaitWindow(tester);
      for (
        var tries = 0;
        tries < 100 && importWarningsButton.evaluate().isEmpty;
        tries += 1
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      s.playbackRig.prerenderScheduler.cancel();
      final notice = await openImportWarnings(tester);

      expect(
        find.descendant(of: notice, matching: find.text('거리')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: notice,
          matching: find.textContaining('bg_street'),
        ),
        findsNothing,
      );
    });
  });
}
