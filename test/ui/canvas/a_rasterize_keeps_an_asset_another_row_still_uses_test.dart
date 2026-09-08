import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

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

  Future<String> writePng(String name) async {
    const width = 8;
    const height = 8;
    final pixels = Uint8List(width * height * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = 0x33;
      pixels[i + 1] = 0x66;
      pixels[i + 2] = 0xFF;
      pixels[i + 3] = 0xFF;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    return file.path;
  }

  testWidgets('the asset survives while ANOTHER layer still references its '
      'path, and goes with the last referrer', (tester) async {
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
      isEmpty,
      reason: 'the LAST referrer takes the registration with it',
    );
    await tester.pumpAndSettle();
  });
}
