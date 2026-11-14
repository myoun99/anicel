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

  /// Frees a block as the tile that holds it is collected: the lists' own
  /// free, called on the collector's thread.
  static final NativeFinalizer finalizer = NativeFinalizer(
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
