import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/import/import_layer_spot.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/solid_png_fixture.dart';

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

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Windows keeps handles briefly.
    }
  });

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
}
