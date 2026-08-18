import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// R7q2 (유저 08-18: 「치유가 가볍게 가능하다면 해도 됨」): opening a file
/// heals cels whose stored canvas size disagrees with their cut — the
/// pre-R7 resize could leave 겸용 or unselected cuts' cels at a stale
/// size, and a save preserved the mismatch (which displays as EMPTY and
/// turns into permanent loss on the first stroke). A healthy file walks
/// one map and pays nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a load crops mismatched cels to their cut size and marks the '
      'session unsaved; a healthy file loads untouched', () async {
    final dir = Directory.systemTemp.createTempSync('anicel-load-heal');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/heal.anicel';

    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cut = s.requireActiveCut;
    final originalSize = cut.canvasSize;
    final key = BrushFrameKey(
      projectId: s.repository.requireProject().id,
      trackId: s.activeTrack.id,
      cutId: cut.id,
      layerId: cut.layers.first.id,
      frameId: const FrameId('cel-1'),
    );
    final pixels = Uint8List(256 * 256 * 4);
    pixels[3] = 255;
    s.brushFrameStore.storeBakedSurface(
      key,
      BitmapSurface(canvasSize: originalSize).putTile(
        BitmapTile(coord: TileCoord(x: 0, y: 0), size: 256, pixels: pixels),
      ),
    );
    // The corruption vector: a DIRECT model-size write (what the pre-R7
    // split effectively did to cuts whose raster half was skipped).
    s.repository.updateCutCanvasSize(
      cutId: cut.id,
      canvasSize: const CanvasSize(width: 640, height: 360),
    );
    await s.saveProjectToFile(path);

    final loaded = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(loaded.dispose);
    await loaded.openProjectFromFile(path);

    final healed = loaded.brushFrameStore.bakedSurfaceOrNull(key)!;
    expect(
      healed.canvasSize,
      const CanvasSize(width: 640, height: 360),
      reason: 'the load applied the resize\'s own cut-scoped crop — the '
          'cel no longer displays as EMPTY and cannot be silently '
          'overwritten by a blank-seeded first stroke',
    );
    expect(
      loaded.hasUnsavedChanges,
      isTrue,
      reason: 'the repaired truth differs from the file — it wants a save',
    );

    // A healthy round-trip stays untouched and clean.
    await loaded.saveProjectToFile(path);
    final clean = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(clean.dispose);
    await clean.openProjectFromFile(path);
    expect(clean.hasUnsavedChanges, isFalse);
  });
}
