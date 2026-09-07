import 'dart:io';
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
import 'package:anicel/src/services/persistence/session_scratch.dart';

/// 🚨★★★**A COOLED CEL IS UNSAVED WORK, AND IT NOW LIVES ON DISK.**
///
/// The cold tier used to be RAM: an over-budget cel was compressed and the
/// blob kept in a map, so a project big enough to exceed the hot budget
/// simply carried the overflow in memory. It parks in the run's 이사대기
/// room instead — the room whose contents a crash LEAVES STANDING, because
/// these bytes are the only copy of that picture outside the hot tier.
///
/// ⛔That is also the new failure mode, and it is what most of this file
/// is about: a map put cannot fail and a file write can. Every assertion
/// below is about the moment it does.
void main() {
  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  BitmapSurface inked(int seed) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * seed * 31 + seed) & 0xFF;
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

  test('🚨 an over-budget cel leaves RAM for the run\'s room, and comes '
      'back byte-exact', () async {
    final store = BrushFrameStore()..hotCelByteBudget = 0;
    final k1 = key('f1');
    final s1 = inked(3);
    store.storeBakedSurface(k1, s1);
    store.storeBakedSurface(key('f2'), inked(5));
    await store.drainCooling();

    expect(store.isCelCold(k1), isTrue, reason: 'LRU victim cooled');
    expect(
      Directory(SessionScratch.stagedFolder()).existsSync(),
      isTrue,
      reason: '⛔the 이사대기 room, not a cache: a crash leaves this '
          'standing, which is the only reason it is safe to move unsaved '
          'pixels out of RAM at all',
    );

    expect(
      store.bakedSurfaceOrNull(k1)!.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      s1.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      reason: 'hot → parked → hot is byte-exact',
    );
  });


  test('🚨 a park that FAILS leaves the cel HOT rather than dropping it',
      () async {
    // The room is gone — a volume unmounted, a permission revoked. Over
    // budget is a number; a lost drawing is not.
    final store = BrushFrameStore()..hotCelByteBudget = 0;
    final k1 = key('f1');
    final s1 = inked(11);
    store.storeBakedSurface(k1, s1);
    store.storeBakedSurface(key('f2'), inked(13));

    // A FILE where the room's folder has to go: nothing can be created
    // under it, which is the shape of a revoked scope or a full disk.
    final room = Directory(SessionScratch.stagedFolder());
    if (room.existsSync()) {
      room.deleteSync(recursive: true);
    }
    File(SessionScratch.stagedFolder())
      ..createSync(recursive: true)
      ..writeAsBytesSync(const [0]);
    addTearDown(() {
      try {
        File(SessionScratch.stagedFolder()).deleteSync();
      } on Object {
        // Best effort; the room goes with the run.
      }
    });

    await store.drainCooling();

    expect(
      store.celHasRenderableContent(k1),
      isTrue,
      reason: '⛔THE PICTURE IS STILL THERE. A park that could not write '
          'must not end with the cel dropped from the hot tier and no ref '
          'to show for it — that is the one outcome that loses work.',
    );
    expect(
      store.bakedSurfaceOrNull(k1)!.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      s1.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      reason: 'and it is the same picture, still in RAM where it was',
    );
  });
}
