import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/opened_session.dart';
import '../../helpers/project_scratch_folder.dart';

/// R5: the conte sheet ink rides the .anicel archive as a second cel
/// namespace — the row plane keyed by the storyboard block's own ink id
/// (`ExposureMemo.inkId`), the page plane by page index. Load prunes row
/// entries no block names any more ("ink dies with the block" at the
/// session boundary; saving never prunes, so an undone delete keeps its
/// ink within the session).
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
          size: 8,
          pixels: pixels,
        ),
      },
    );
  }

  test('row + page ink cels round-trip through save/open; a row entry '
      'whose block is gone prunes at LOAD; the main store never sees the '
      'namespace', () async {
    final dir = Directory.systemTemp.createTempSync('anicel-conte-ink');
    deleteAfterSessionEnds(dir);
    final path = '${dir.path}/ink.anicel';

    // Default layers carry no frames until drawn — graft one real block
    // (Frame + timeline exposure) so the load-prune has a live id.
    var project = createDefaultProject();
    final track = project.tracks.first;
    final baseCut = track.cuts.first;
    final grafted = baseCut.layers.first.copyWith(
      frames: [
        Frame(id: const FrameId('sb-f1'), duration: 8, strokes: const []),
      ],
      timeline: {
        0: const TimelineExposure.drawing(
          FrameId('sb-f1'),
          length: 8,
          memo: ExposureMemo(inkId: 'ink-live'),
        ),
      },
    );
    project = project.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            baseCut.copyWith(
              layers: [grafted, ...baseCut.layers.skip(1)],
            ),
          ],
        ),
      ],
    );

    final s = EditorSessionManager(initialProject: project);
    addTearDown(s.dispose);
    final cut = s.requireActiveCut;
    final liveKey = conteInkRowKey(cut.id, 'ink-live');
    final deadKey = conteInkRowKey(cut.id, 'long-dead-block');
    // The drawing's own id names no block's handwriting.
    final drawingKey = conteInkRowKey(cut.id, 'sb-f1');

    s.renderCaches.conteInkRowStore.storeBakedSurface(liveKey, inkSurface(seed: 3));
    s.renderCaches.conteInkRowStore.storeBakedSurface(deadKey, inkSurface(seed: 5));
    s.renderCaches.conteInkRowStore.storeBakedSurface(
      drawingKey,
      inkSurface(seed: 9),
    );
    s.renderCaches.conteInkPageStore.storeBakedSurface(conteInkPageKey(0), inkSurface());
    await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);

    final loaded = await openedSession(path);
    addTearDown(loaded.dispose);

    expect(
      loaded.renderCaches.conteInkRowStore.celHasRenderableContent(liveKey),
      isTrue,
      reason: 'the live block\'s ink reopens with the project',
    );
    expect(
      loaded.renderCaches.conteInkRowStore.celHasRenderableContent(deadKey),
      isFalse,
      reason: 'a dead block\'s ink prunes at the load boundary',
    );
    expect(
      loaded.renderCaches.conteInkRowStore.celHasRenderableContent(drawingKey),
      isFalse,
      reason: 'ink is kept by the BLOCK that wrote it, not by the drawing '
          'the block shows',
    );
    expect(
      loaded.renderCaches.conteInkPageStore.celHasRenderableContent(conteInkPageKey(0)),
      isTrue,
      reason: 'page-plane ink (margins) reopens too',
    );
    expect(
      loaded.renderCaches.brushFrameStore.fileCelKeys.where(isConteInkKey),
      isEmpty,
      reason: 'the ink namespace never leaks into the cel store',
    );

    // A second save from the LOADED session (incremental path over the
    // same file) keeps the ink sound.
    loaded.renderCaches.conteInkPageStore.storeBakedSurface(
      conteInkPageKey(1),
      inkSurface(seed: 7),
    );
    await loaded.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
    final reloaded = await openedSession(path);
    addTearDown(reloaded.dispose);
    expect(reloaded.renderCaches.conteInkRowStore.celHasRenderableContent(liveKey), isTrue);
    expect(
      reloaded.renderCaches.conteInkPageStore.celHasRenderableContent(conteInkPageKey(1)),
      isTrue,
    );
  });
}
