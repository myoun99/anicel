import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The envelope's handwriting rides the .anicel archive as its own cel
/// namespace, like the conte's. What it is keyed to is the OWNER CUT — so
/// load prunes a sheet whose cut is gone, and never prunes by BOX: swapping
/// the form preset and swapping it back has to bring the writing back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BitmapSurface inkSurface({int seed = 1}) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * seed * 13 + seed) & 0xFF;
    }
    return BitmapSurface(
      canvasSize: const CanvasSize(width: 16, height: 16),
      tileSize: 8,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(
          coord: TileCoord(x: 0, y: 0),
          size: 8,
          pixels: pixels,
        ),
      },
    );
  }

  test(
    'envelope ink round-trips through save/open; a sheet whose CUT is '
    'gone prunes at LOAD; the main cel store never sees the namespace',
    () async {
      final dir = Directory.systemTemp.createTempSync('anicel-envelope-ink');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/envelope.anicel';

      final Project project = createDefaultProject();
      final session = EditorSessionManager(initialProject: project);
      addTearDown(session.dispose);
      final cut = session.requireActiveCut;

      final liveKey = envelopeInkBoxKey(cut.id, 'cel-row-3');
      final otherBoxKey = envelopeInkBoxKey(cut.id, 'memo');
      final deadKey = envelopeInkBoxKey(
        const CutId('deleted-cut'),
        'cel-row-3',
      );
      session.envelopeInkStore.storeBakedSurface(liveKey, inkSurface(seed: 3));
      session.envelopeInkStore.storeBakedSurface(
        otherBoxKey,
        inkSurface(seed: 4),
      );
      session.envelopeInkStore.storeBakedSurface(deadKey, inkSurface(seed: 5));
      await session.saveProjectToFile(path);

      final loaded = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(loaded.dispose);
      await loaded.openProjectFromFile(path);

      expect(
        loaded.envelopeInkStore.celHasRenderableContent(liveKey),
        isTrue,
        reason: 'what was written on the sheet reopens with the project',
      );
      expect(
        loaded.envelopeInkStore.celHasRenderableContent(otherBoxKey),
        isTrue,
        reason: 'every box of the sheet, not just the first',
      );
      expect(
        loaded.envelopeInkStore.celHasRenderableContent(deadKey),
        isFalse,
        reason: 'a deleted cut takes its envelope with it',
      );
      expect(
        loaded.brushFrameStore.fileCelKeys.where(isEnvelopeInkKey),
        isEmpty,
        reason: 'sheet ink can never leak into a cel',
      );
    },
  );
}
