import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/playback/frame_demand.dart'
    show FrameGhosts;
import 'package:anicel/src/ui/diagnostics/memory_census.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/draw_on_current_frame.dart';

/// 🚨Card `one-cut-of-fnk02-holds-nine-gigabytes` (저장 11-15 19:25: 「그
/// 동안의 무게를 누가 세는가」): a frame made ahead of a screen looks at its
/// cels — thawed beside the store, kept hot by no one — so what it holds
/// while it is made is in no budget's counter. Uncounted, the drawings row
/// fell and the process held that much more than every row said.
void main() {
  // The census reads the image cache, and that needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('🚨the cels a frame made ahead looks at are counted with the '
      'drawings while it holds them, and no more once the walk rests', () async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    drawOnCurrentFrame(session);
    final selection = session.editingCanvas.activeBrushEditorSelection!;
    final cut = session.requireActiveCut;
    final drawn = session.brushFrameKeyForCut(
      cut,
      selection.layerId,
      selection.frameId,
    );
    final store = session.renderCaches.brushFrameStore;
    // Kept as an opened project keeps it: in its file, nothing hot — a tile
    // of more than one colour, which weighs its block whatever a tile of one
    // colour comes to weigh.
    final pixels = Uint8List(defaultCelTileSize * defaultCelTileSize * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * 7 + 1) & 0xFF;
    }
    keepInAFile(store, {
      drawn: BitmapSurface(
        canvasSize: cut.canvasSize,
        tileSize: defaultCelTileSize,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile(
            size: defaultCelTileSize,
            pixels: pixels,
          ),
        },
      ),
    });
    // The walk the session began makes what it will and rests.
    await pumpEventQueue();
    session.playbackRig.prerenderScheduler.cancel();
    final pictures = session.playbackRig.framePictures..rest();
    expect(store.hotBakedBytes, 0, reason: '⛔premise');

    int drawingsRow() => collectMemoryCensus([
      session,
    ]).items.firstWhere((item) => item.id == 'drawings').bytes;
    final before = drawingsRow();
    final frame = (
      cut: cut,
      frameIndex: session.currentFrameIndex,
      paintPaper: true,
      ghosts: FrameGhosts.none,
    );

    await pictures.readIn(frame);

    final looked = pictures.celsLookedAtAhead.toList();
    expect(looked, hasLength(1), reason: '⛔premise: the frame draws the cel');
    expect(store.hotBakedBytes, 0, reason: 'a look keeps nothing hot');
    expect(
      ownBytesOf(looked.single.tiles.values),
      greaterThan(0),
      reason: '⛔premise: the cel owns its tiles — none of one colour',
    );
    expect(
      drawingsRow(),
      before + ownBytesOf(looked.single.tiles.values),
    );

    pictures.rest();
    expect(drawingsRow(), before);
  });
}
