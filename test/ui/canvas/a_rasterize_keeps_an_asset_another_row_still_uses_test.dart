import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/solid_png_fixture.dart';

/// §6-t: rasterizing a reference layer drops the asset registration only
/// when NOTHING ELSE references its path. The last referrer's rasterize
/// unregisters; every earlier one leaves the asset standing.
///
/// The "last one" half was already pinned (media_import_session_test). This
/// is the other half — the scan across every track, cut and layer that
/// decides which of the two it is. Without it the scan could always answer
/// "nobody else" and the suite would stay green while a second layer's
/// picture went missing.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-rasterize-test');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Windows keeps handles briefly; leftovers live in systemTemp.
    }
  });

  Future<String> writePng(String name) => writeSolidPng(tempDir, name);

  testWidgets('the asset survives every rasterize — while ANOTHER layer '
      'still references its path, and after the last one too (유저 '
      '2026-09-11: 「구워도 풀에 남음」; it used to go with the last '
      'referrer)', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    await tester.runAsync(() async {
      final path = await writePng('paper.png');
      for (var i = 0; i < 2; i++) {
        await s.importDoors.importImageFile(
          path: path,
          destination: ImportDestination.activeCutLayer,
          copyIntoProject: false,
        );
      }
    });

    final referring = [
      for (final layer in s.requireActiveCut.layers)
        if (layer.mediaReference != null) layer,
    ];
    expect(
      referring,
      hasLength(2),
      reason: 'the premise: two layers, one asset path',
    );
    expect(s.mediaPool.mediaAssets, hasLength(1));

    s.selectLayer(referring.first.id);
    s.editingCanvas.rasterizeActiveLayer();
    expect(
      s.mediaPool.mediaAssets,
      hasLength(1),
      reason:
          'the other layer still shows this asset — unregistering here is '
          'how its picture would go missing',
    );
    expect(
      s.requireActiveCut.layers
          .firstWhere((l) => l.id == referring.first.id)
          .mediaReference,
      isNull,
      reason: 'the rasterize itself still happened',
    );

    s.selectLayer(referring.last.id);
    s.editingCanvas.rasterizeActiveLayer();
    expect(
      s.mediaPool.mediaAssets,
      hasLength(1),
      reason: 'a baked file is still the pool\'s to offer again',
    );
    await tester.pumpAndSettle();
  });
}
