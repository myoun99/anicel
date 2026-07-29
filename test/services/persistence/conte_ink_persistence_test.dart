import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte/conte_ink_keys.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// R5: the conte sheet ink rides the .anicel archive as a second cel
/// namespace — the row plane keyed by the storyboard block's [FrameId]
/// (the memo's identity), the page plane by page index. Load prunes row
/// entries whose block no longer exists ("ink dies with the drawing" at
/// the session boundary; saving never prunes, so an undone delete keeps
/// its ink within the session).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BitmapSurface inkSurface({int seed = 1}) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * seed * 13 + seed) & 0xFF;
    }
    return BitmapSurface(
      canvasSize: CanvasSize(width: 16, height: 16),
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

  test('row + page ink cels round-trip through save/open; a row entry '
      'whose block is gone prunes at LOAD; the main store never sees the '
      'namespace', () async {
    final dir = Directory.systemTemp.createTempSync('anicel-conte-ink');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ink.anicel';

    // Default layers carry no frames until drawn — graft one real block
    // (Frame + timeline exposure) so the load-prune has a live id.
    Project project = createDefaultProject();
    final track = project.tracks.first;
    final baseCut = track.cuts.first;
    final grafted = baseCut.layers.first.copyWith(
      frames: [
        Frame(id: const FrameId('sb-f1'), duration: 8, strokes: const []),
      ],
      timeline: {
        0: const TimelineExposure.drawing(FrameId('sb-f1'), length: 8),
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
    final liveKey = conteInkRowKey(cut.id, const FrameId('sb-f1'));
    final deadKey = conteInkRowKey(cut.id, const FrameId('long-dead-block'));

    s.conteInkRowStore.storeBakedSurface(liveKey, inkSurface(seed: 3));
    s.conteInkRowStore.storeBakedSurface(deadKey, inkSurface(seed: 5));
    s.conteInkPageStore.storeBakedSurface(conteInkPageKey(0), inkSurface());
    await s.saveProjectToFile(path);

    final loaded = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(loaded.dispose);
    await loaded.openProjectFromFile(path);

    expect(
      loaded.conteInkRowStore.celHasRenderableContent(liveKey),
      isTrue,
      reason: 'the live block\'s ink reopens with the project',
    );
    expect(
      loaded.conteInkRowStore.celHasRenderableContent(deadKey),
      isFalse,
      reason: 'a dead block\'s ink prunes at the load boundary',
    );
    expect(
      loaded.conteInkPageStore.celHasRenderableContent(conteInkPageKey(0)),
      isTrue,
      reason: 'page-plane ink (margins) reopens too',
    );
    expect(
      loaded.brushFrameStore.fileCelKeys.where(isConteInkKey),
      isEmpty,
      reason: 'the ink namespace never leaks into the cel store',
    );

    // A second save from the LOADED session (incremental path over the
    // same file) keeps the ink sound.
    loaded.conteInkPageStore.storeBakedSurface(
      conteInkPageKey(1),
      inkSurface(seed: 7),
    );
    await loaded.saveProjectToFile(path);
    final reloaded = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(reloaded.dispose);
    await reloaded.openProjectFromFile(path);
    expect(reloaded.conteInkRowStore.celHasRenderableContent(liveKey), isTrue);
    expect(
      reloaded.conteInkPageStore.celHasRenderableContent(conteInkPageKey(1)),
      isTrue,
    );
  });
}
