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
import 'package:anicel/src/services/persistence/scratch_file.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuReadFailed;

import '../helpers/tiles_on_the_engine.dart';

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

  /// A picture of one tile of [side] — the engine's unless asked — inked
  /// by [seed].
  BitmapSurface inked(int seed, {int side = defaultCelTileSize}) {
    final pixels = Uint8List(side * side * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * seed * 31 + seed) & 0xFF;
    }
    return BitmapSurface(
      canvasSize: CanvasSize(width: 2 * side, height: 2 * side),
      tileSize: side,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(
          size: side,
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

  // 🗣️Card a-pasteboard-undo-runs-on-the-ui-thread: what a cel lets go is
  // removed off the UI thread ([ScratchFile.letGo]), whenever the machine
  // gets to it — so no park may wear a name an earlier one wore, or that
  // removal could land on the later park's bytes.
  test('🚨 a cel parked, thawed and parked again wears a new name each '
      'time, and the second park outlives the first one\'s removal', () async {
    final store = BrushFrameStore()..hotCelByteBudget = 0;
    final k1 = key('f1');
    final k2 = key('f2');
    final s1 = inked(3);
    store.storeBakedSurface(k1, s1);
    store.storeBakedSurface(k2, inked(5));
    await store.drainCooling();
    final first = store.bakedSnapshotForSave().cold[k1]!.filePath;
    // Thawed, which lets the first park go; then the least recent again.
    store.bakedSurfaceOrNull(k1);
    store.storeBakedSurface(k2, inked(7));
    await store.drainCooling();
    expect(store.isCelCold(k1), isTrue, reason: 'premise: parked again');
    final second = store.bakedSnapshotForSave().cold[k1]!.filePath;

    expect(second, isNot(first));
    await ScratchFile.lettingGo;
    expect(File(first).existsSync(), isFalse, reason: 'the first went');
    expect(
      store.bakedSurfaceOrNull(k1)!.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      s1.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      reason: 'and the second is still the picture',
    );
  });

  test('🚨 two stores park the SAME key in two files — one open project\'s '
      'cooling never lands on another\'s parked cel (I-7)', () async {
    // Two untitled projects share a project id, so their cels share keys;
    // the ink stores' keys are constants in every project.
    final a = BrushFrameStore()..hotCelByteBudget = 0;
    final b = BrushFrameStore()..hotCelByteBudget = 0;
    final k1 = key('f1');
    final inA = inked(3);
    final inB = inked(7);
    a.storeBakedSurface(k1, inA);
    a.storeBakedSurface(key('f2'), inked(5));
    await a.drainCooling();
    b.storeBakedSurface(k1, inB);
    b.storeBakedSurface(key('f2'), inked(9));
    await b.drainCooling();
    expect(a.isCelCold(k1), isTrue, reason: 'premise: parked');
    expect(b.isCelCold(k1), isTrue, reason: 'premise: parked');

    expect(
      a.bakedSurfaceOrNull(k1)!.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      inA.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      reason: 'a shared file name let the second store\'s park overwrite '
          'the first one\'s — a picture from another project',
    );
    expect(
      b.bakedSurfaceOrNull(k1)!.tiles[TileCoord(x: 0, y: 0)]!.pixels,
      inB.tiles[TileCoord(x: 0, y: 0)]!.pixels,
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

  test('🚨 a pass that THROWS stands down as a failed park does — the cel '
      'stays HOT, the error is the waiter\'s, and no pass runs again on '
      'its own', () async {
    final store = BrushFrameStore()..hotCelByteBudget = 0;
    final k1 = key('f1');
    // A tile of a side the engine does not store: its read back throws
    // before the pass's first wait.
    store.storeBakedSurface(k1, inked(11, side: defaultCelTileSize ~/ 2));
    store.storeBakedSurface(key('f2'), inked(13));

    await expectLater(store.drainCooling(), throwsStateError);
    // Asked again, as a read or a budget's fall asks — nothing an edit or a
    // swap would change: a pass begun would throw again, here.
    store.coolToBudget();
    await store.drainCooling();

    expect(store.isCelCold(k1), isFalse);
    expect(store.celHasRenderableContent(k1), isTrue);
  });

  test('🚨 a cel whose bytes are here parks from them: none of it goes to '
      'the engine and back, which is what a park was to save', () async {
    final store = BrushFrameStore()..hotCelByteBudget = 0;
    final k1 = key('f1');
    final surface = inked(11);
    store.storeBakedSurface(k1, surface);
    store.storeBakedSurface(key('f2'), inked(13));

    await store.drainCooling();

    expect(store.isCelCold(k1), isTrue, reason: 'LIVENESS: it did park');
    expect(
      EngineTileLedger.instance.slotOf(surface.tiles.values.single),
      isNull,
    );
  });

  test('🚨 a read the engine refuses is a park refused — no one waits on the '
      'pass to be told, the cel stays HOT, and no pass runs again', () async {
    addTearDown(() => EngineTileLedger.debugBeforeRead = null);
    var reads = 0;
    EngineTileLedger.debugBeforeRead = (_) {
      reads += 1;
      throw GpuReadFailed('lost');
    };
    final store = BrushFrameStore()..hotCelByteBudget = 0;
    final k1 = key('f1');
    store.storeBakedSurface(k1, surfaceOnEngine(inked(11)));
    store.storeBakedSurface(key('f2'), surfaceOnEngine(inked(13)));

    await store.drainCooling();

    expect(reads, 1, reason: 'the pass ended at the first refusal');
    expect(store.isCelCold(k1), isFalse);
    expect(store.celHasRenderableContent(k1), isTrue);

    store.coolToBudget();
    await store.drainCooling();
    expect(reads, 1, reason: 'stood down, as after a refused park');
  });
}
