@Tags(['gc'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';

import '../helpers/cels_kept_in_a_file.dart';
import '../helpers/collect_garbage.dart';
import '../helpers/shells_with_no_bytes.dart';

/// 🚨WHAT THE ROOM HOLDS ON FOR AN EDITED CEL IS HELD FOR ITS TILES, NOT BY
/// THEM COUNTED (card `cel-originals-are-held-twice-in-ram-and-on-the-gpu`;
/// an_edited_cel_reads_what_it_was_kept_as_test.dart has the law): the store
/// reaches each tile that waits weakly (`_TakenTile`), so one nothing holds
/// any more — the step back that held it dropped, its canvas moved on —
/// waits no more once it is collected, and the rest after lets the file go.
/// A strong hold would keep every edited cel's base in the room till the
/// project closed.
void main() {
  const canvasSize = CanvasSize(
    width: defaultCelTileSize,
    height: defaultCelTileSize,
  );
  final origin = TileCoord(x: 0, y: 0);
  const f = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );

  BitmapSurface ink(int seed) {
    final pixels = Uint8List(defaultCelTileSize * defaultCelTileSize * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = (seed * 20 + i ~/ 4) % 251;
      pixels[i + 3] = 255;
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: defaultCelTileSize,
      tiles: {origin: BitmapTile(size: defaultCelTileSize, pixels: pixels)},
    );
  }

  test('🚨a tile nothing holds waits no more: the room lets go of what was '
      'held for it at the rest after it is collected — and not while one '
      'holds it', () async {
    final engine = ShellsWithNoBytes();
    final store = BrushFrameStore(shells: engine);
    keepInAFile(store, {f: ink(4)});
    expect(store.bakedSurfaceOrNull(f), isNotNull, reason: '⛔premise');
    store.letGoOfBytesTheEngineHolds();
    var shell = store.hotBakedSurfaceOrNull(f);
    expect(shell!.keptTileBytes, 0, reason: '⛔premise: a shell');
    // A picture with no tile of the shell's, shown from as the pen's
    // coordinator donates what it stores — the cel was shown from its
    // shell till then: this test alone holds the shell's tiles.
    store.storeBakedSurface(f, ink(9));
    store.storeRebuiltDisplayCache(
      key: f,
      previewSurface: store.hotBakedSurfaceOrNull(f)!,
    );
    engine.made.clear();

    await collectGarbage();
    store.letGoOfBytesTheEngineHolds();

    expect(store.keptBytesHeldOn, 1, reason: 'held while its tile is');
    expect(shell.tiles[origin]!.hasItsBytesHere, isFalse);
    shell = null;

    await collectGarbageUntil(() {
      store.letGoOfBytesTheEngineHolds();
      return store.keptBytesHeldOn == 0;
    });

    expect(store.keptBytesHeldOn, 0);
    expect(store.coldBakedBytes, 0);
  });
}
