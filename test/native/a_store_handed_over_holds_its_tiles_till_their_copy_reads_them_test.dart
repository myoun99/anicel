@Tags(['gc'])
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_tile.dart';

import '../helpers/collect_garbage.dart';

/// 🚨A STORE HANDED OVER HOLDS ITS TILES TILL THEIR COPY HAS READ THEM
/// (the-ui-thread-never-enters-the-driver B1-b, 2026-11-15): the copy of a
/// store's bytes into its slots is the engine's thread's, and the caller
/// waits for none of it (rust/src/kernels/pool/mod.rs,
/// `gpu_engine_pool_store`). A tile's pixels are a native block its
/// finalizer hands back to the lists for the next tile made
/// (BitmapTile.readPixels has the accident) — so a tile nothing else holds,
/// collected before its copy ran, would land another tile's bytes in its
/// slot. 🗣️관제 10:07: the hold a real one, no assert, and a pin of it
/// under the collector.
void main() {
  BitmapTile tileOf(int value) => BitmapTile.written(
    size: gpuTileSide,
    write: (pixels) => pixels.fillRange(0, gpuTileBytes, value),
  );
  Pointer<Uint8> bytesOf(BitmapTile tile) =>
      tile.readPixels((pointer, _) => pointer);

  /// A tile of [value] stored on [cel] of [pool], and nothing here holding
  /// it: its slot, and a weak word of it.
  (GpuTile, WeakReference<BitmapTile>) storedAlone(
    GpuPool pool,
    int cel,
    int value,
  ) {
    final tile = tileOf(value);
    final [slot] = pool.store(cel, [tile], bytesOf);
    return (slot, WeakReference(tile));
  }

  test('🚨what a store hands over is held while the engine\'s thread has '
      'not read it, whatever the collector meets, and not once it has',
      () async {
    final engine = GpuEngine.onFirstAdapter();
    addTearDown(engine.close);
    final pool = GpuPool(engine, 1 << 30);
    addTearDown(pool.free);
    final cel = pool.cel();
    // ⛔premise: a page with room, so the books below make none — a page
    // is made on the engine's thread, which stands still there.
    pool.store(cel, [tileOf(1)], bytesOf);
    await engine.done();

    engine.debugStandStill(const Duration(seconds: 3));
    final (slot, stored) = storedAlone(pool, cel, 7);
    final canary = WeakReference(tileOf(9));
    await collectGarbageUntil(() => canary.target == null);
    expect(canary.target, isNull, reason: '⛔premise: the collector came');
    expect(stored.target, isNotNull, reason: 'its copy has not read it');
    // Blocks a collected tile handed back go to the next tiles made.
    final churned = [for (var made = 0; made < 64; made++) tileOf(0xEE)];

    await engine.done();
    final into = calloc<Uint8>(gpuTileBytes);
    addTearDown(() => calloc.free(into));
    pool.read([slot], into);
    expect(
      into.asTypedList(gpuTileBytes).every((byte) => byte == 7),
      isTrue,
      reason: 'its slot holds its own bytes',
    );
    expect(churned, hasLength(64));
    await collectGarbageUntil(() => stored.target == null);
    expect(stored.target, isNull, reason: 'let go once its copy read it');
  });
}
