// The engine's Rust library carries the tile blocks' lists
// (rust/src/lib.rs), and its names are found in that code asset — no
// library opened, no path named.
@DefaultAsset(gpuEngineAsset)
library;

import 'dart:ffi';

import 'package:flutter/foundation.dart' show visibleForTesting;

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

  /// Has [block] — [byteLength] bytes — freed as [holder] is collected, the
  /// tile that holds it or the colour whose tiles share it (`BitmapTile`):
  /// the lists' own free, called on the collector's thread. Its weight is
  /// told to the collector as [holder]'s, or — [weighedBy] — as a part of
  /// the one weight of the tiles made together with it ([TileWeight]).
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
  /// ⚠️What the weight told here costs the collector is [TileWeight]'s to
  /// say: the pauses left after this were made of it.
  /// ↩️A tile passed itself as the token from R19-Z (2026-07-14) on.
  static void freeWith(
    Finalizable holder,
    Pointer<Uint8> block,
    int byteLength, {
    TileWeight? weighedBy,
  }) {
    if (weighedBy == null) {
      _freesWhenCollected.attach(
        holder,
        block.cast(),
        externalSize: byteLength,
      );
      return;
    }
    // Attached first: a weight told already refuses the tile, and its
    // block goes with the tile.
    _freesWhenCollected.attach(holder, block.cast());
    weighedBy._add(byteLength);
  }

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

/// The weight of the blocks of tiles made together — a cel's, made a
/// surface at once (`brush_drawing_binary_codec.dart`'s one assembly) —
/// told to the collector ONCE, by the one object each of those tiles holds:
/// told after the last of them is made, and let go with the last of them
/// collected. Each block is still freed as its own tile is
/// ([TileBlocks.freeWith]).
///
/// 🚨ONE WEIGHT A CEL, NOT ONE A TILE (card
/// `a-thawed-cel-is-adopted-on-the-ui-thread`). A weight told for an object
/// in new space is new space's, and the VM scavenges each time what new
/// space was told passes four times its room — to free that weight, it
/// hopes. A thawed cel's tiles stay (hot), so each such scavenge freed
/// nothing and promoted them.
/// 🔬Surface Pro 11, profile build, a copy of a user's 78-frame cut, the
/// onion turned on (캔버스 베이스's harness, 11-16 13:1x): of 470
/// scavenges in one row's step 457 were the VM's `external` ones, 462 ms
/// in all, and a stop of 54.5 ms was nine of them in a row. The bare VM
/// (`--verbose_gc`, 134 cels of 90 tiles held, 저장 11-16): 395 such
/// scavenges with a weight a tile, 134 with one a cel — one a cel, its
/// weight past new space's room by itself — and the cels made in half the
/// time.
/// 🔬After, the same harness and copy (저장 11-16 17:29–17:44, two runs
/// each way): the `external` scavenges of each step about halved — one
/// row's 456 · 410 → 253 · 252, every row's 439 · 413 → 207 · 207 — the
/// UI thread's stops over 33 ms 4 · 5 a run → 1 · 1, the longest 48.7 →
/// 39.0 ms; and the 858 MB told stayed told while the cels stood. ⚠️One
/// scavenge a cel is left, and a longer one, a cel promoted whole.
/// ⚠️The price: the weight stays told till the LAST of the tiles goes,
/// though a block whose tile went first is freed then — the collector is
/// told more than there is, never less.
final class TileWeight implements Finalizable {
  TileWeight._();

  int _bytes = 0;
  bool _told = false;

  /// Test seam: how many weights have been told, and of how many bytes in
  /// all — a cel made at once is one.
  @visibleForTesting
  static int debugTold = 0;
  @visibleForTesting
  static int debugToldBytes = 0;

  /// [make]'s answer, every tile it makes with the weight it is handed
  /// weighed as one ([TileBlocks.freeWith]'s `weighedBy`).
  static T together<T>(T Function(TileWeight weight) make) {
    final weight = TileWeight._();
    final made = make(weight);
    weight._told = true;
    if (weight._bytes > 0) {
      // The lists' free of no block: this entry is there for the weight.
      TileBlocks._freesWhenCollected.attach(
        weight,
        nullptr,
        externalSize: weight._bytes,
      );
      debugTold += 1;
      debugToldBytes += weight._bytes;
    }
    return made;
  }

  void _add(int bytes) {
    if (_told) {
      throw StateError('a weight is told once, after the last of its tiles');
    }
    _bytes += bytes;
  }
}
