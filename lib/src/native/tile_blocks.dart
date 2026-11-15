// The engine's Rust library carries the tile blocks' lists
// (rust/src/lib.rs), and its names are found in that code asset — no
// library opened, no path named.
@DefaultAsset(gpuEngineAsset)
library;

import 'dart:ffi';

import 'gpu_engine_asset.dart';

@Native<Pointer<Void> Function(Int64)>(symbol: 'qa_tile_alloc')
external Pointer<Void> _alloc(int size);

@Native<Void Function(Pointer<Void>)>(symbol: 'qa_tile_free')
external void _free(Pointer<Void> pixels);

@Native<Int64 Function()>(symbol: 'qa_tile_pool_cached_bytes')
external int _parkedBytes();

@Native<Void Function()>(symbol: 'qa_tile_pool_trim')
external void _trim();

@Native<Void Function(Int64)>(symbol: 'qa_tile_pool_set_byte_cap')
external void _setByteCap(int bytes);

/// A tile's block of pixels, from the engine's lists (native/tile_blocks):
/// a freed block parks by its exact size, and the next ask of that size
/// takes it (R20-E1 — 🔬the measure is beside the lists).
///
/// 🚨ONE ALLOCATOR A PROCESS, WHICHEVER ISOLATE ASKS. `@Native` finds the
/// same library in every isolate, so a worker lays the blocks the main
/// isolate's tiles adopt and free, and no word of where they come from
/// passes between the two. ↩️While the lists were the C engine's a worker
/// was handed their functions' addresses: its own probe could load another
/// binary, or none — a test's path override and its forced fallback were
/// statics, and statics do not cross isolates.
abstract final class TileBlocks {
  /// A block of [byteLength] bytes. ⚠️Its bytes are whatever its last
  /// holder left: whoever asks writes every one.
  static Pointer<Uint8> alloc(int byteLength) {
    final block = _alloc(byteLength);
    if (block == nullptr) {
      throw StateError('qa_tile_alloc failed for $byteLength bytes');
    }
    return block.cast();
  }

  /// Gives [block] back to the lists — one [alloc] answered.
  static void free(Pointer<Uint8> block) => _free(block.cast());

  /// Has [block] — [byteLength] bytes, told to the collector as [holder]'s
  /// real weight — freed as [holder] is collected, the tile that holds it
  /// or the colour whose tiles share it (`BitmapTile`): the lists' own free,
  /// called on the collector's thread.
  ///
  /// ⛔NO DETACH TOKEN, and the finalizer is this file's own so that none
  /// can be passed (card `a-thawed-cel-is-adopted-on-the-ui-thread`). A
  /// block is freed when its tile is collected and never sooner: nothing
  /// ever detached one. A token costs EVERY tile a slot of the finalizer's
  /// Expando and a set of one entry beside it (the VM's
  /// `NativeFinalizer.attach`) — more for the collector to walk, and a table
  /// rebuilt whole each time the tiles that came and went fill it, a weak
  /// reference made anew for every tile alive: on the thread that was
  /// adopting a thawed cel's tiles.
  /// 🔬The app (2026-11-15; Surface Pro 11, profile build, a cut of 78
  /// frames whose onion, turned on, adopts some 80,000 thawed tiles a
  /// round; one quiet run each way, 캔버스 베이스): stops of the UI thread
  /// over 33 ms — one row's onion 8, the longest 76 ms, → 3; every row's
  /// 6 → 0; every row's laid on top 12, the longest 119 ms, → 0. Of the 19
  /// samples inside that 76 ms, 8 stood in `Expando._rehash` under this
  /// attach. The collector's pauses 504–1495 ms a run → 171–283 ms, and
  /// the Dart heap 108–114 MB → 92–95 MB: a set and a weak property a tile.
  /// ⚠️Not settled by it: whether the collector runs less often for the
  /// weight told here — once for every 110 tiles or so (7 MB) with the
  /// token; without it as often in one pair of runs, a third to a half
  /// less often in the other.
  /// ↩️A tile passed itself as the token from R19-Z (2026-07-14) on.
  static void freeWith(
    Finalizable holder,
    Pointer<Uint8> block,
    int byteLength,
  ) => _freesWhenCollected.attach(
    holder,
    block.cast(),
    externalSize: byteLength,
  );

  static final NativeFinalizer _freesWhenCollected = NativeFinalizer(
    Native.addressOf<NativeFinalizerFunction>(_free),
  );

  /// Bytes of the blocks parked for reuse — resident, and nobody's picture.
  /// The memory census reads it.
  static int get parkedBytes => _parkedBytes();

  /// Caps what may park. The memory tab's allowance sets it
  /// (`CacheBudgetLine.enginePool`, memory-allowance-Q2); lowering it frees
  /// the excess on the spot.
  static void setByteCap(int bytes) => _setByteCap(bytes);

  /// Frees every parked block: the OS says memory is tight
  /// (`DrawingEngines.respondToMemoryPressure`).
  static void trim() => _trim();
}
