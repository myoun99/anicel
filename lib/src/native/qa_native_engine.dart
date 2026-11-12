import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'dart:typed_data';

import 'qa_engine_abi.dart';
import 'native_scratch.dart';
import 'native_upload_cache.dart';

/// A block `qa_tile_alloc` answered, or the error it failed with — the one
/// check both ways of reaching the allocator make ([QaNativeEngine.tileAlloc]
/// and [QaTileBlocksAt.alloc]).
Pointer<Uint8> qaTileBlockOrThrow(Pointer<Void> block, int byteLength) {
  if (block == nullptr) {
    throw StateError('qa_tile_alloc failed for $byteLength bytes');
  }
  return block.cast();
}

/// The engine's tile allocator bound from the addresses another isolate
/// read off ITS engine ([QaNativeEngine.tileAllocAddress]) — so the blocks a
/// worker fills here are the ones that isolate's tiles free.
final class QaTileBlocksAt {
  QaTileBlocksAt({required int alloc, required int free})
    : _alloc =
          Pointer<NativeFunction<Pointer<Void> Function(Int64)>>.fromAddress(
            alloc,
          ).asFunction<Pointer<Void> Function(int)>(),
      _free = Pointer<NativeFunction<Void Function(Pointer<Void>)>>.fromAddress(
        free,
      ).asFunction<void Function(Pointer<Void>)>();

  final Pointer<Void> Function(int size) _alloc;
  final void Function(Pointer<Void> pixels) _free;

  Pointer<Uint8> alloc(int byteLength) =>
      qaTileBlockOrThrow(_alloc(byteLength), byteLength);

  void free(Pointer<Uint8> block) => _free(block.cast());
}

/// The native engine core's FFI bindings (R18 A-track).
///
/// LOAD-FALLBACK DISCIPLINE: every native function has a Dart REFERENCE
/// implementation that remains the source of truth for semantics. When
/// the library cannot be loaded (flutter_tester, an unsupported platform,
/// a packaging problem) callers silently use the Dart path — the app
/// never breaks, it just runs at Dart speed. Byte-parity between the two
/// is pinned by tests, so the native path can never silently diverge.
///
/// Tests can point at a locally built binary with the QA_ENGINE_PATH
/// environment variable.
///
/// Which binary, and which ABI generation it must speak, are decided once
/// in `qa_engine_abi.dart` — see [kQaEngineAbiVersion] for the bump
/// checklist.
class QaNativeEngine {
  QaNativeEngine._(
    this._premultiplyRgbaCopy,
    this._premultiplyRgbaRows,
    this._zeroBytes,
    this._tileAlloc,
    this._tileAllocPointer,
    this._tileFree,
    this._tileFreePointer,
    this._tilePoolCachedBytes,
    this._tilePoolTrim,
    this._tilePoolSetByteCap,
  );

  final void Function(Pointer<Uint8> dst, Pointer<Uint8> src, int pixelCount)
  _premultiplyRgbaCopy;

  final void Function(
    Pointer<Uint8> dst,
    int dstStride,
    Pointer<Uint8> src,
    int srcStride,
    int width,
    int rows,
  )
  _premultiplyRgbaRows;

  /// [rows] rows of [width] straight pixels read [from] one place,
  /// premultiplied [into] another, in ONE call (`qa_premultiply_rgba_rows`,
  /// ABI 46) — the kernel of [premultipliedTileScratch] between two strides,
  /// so a tile can be laid into a picture of several where a call a row
  /// would cost more than the row.
  void premultiplyRgbaRows({
    required NativeRows from,
    required NativeRows into,
    required int width,
    required int rows,
  }) => _premultiplyRgbaRows(
    into.start,
    into.stride,
    from.start,
    from.stride,
    width,
    rows,
  );

  final _tilesPictureScratch = NativeScratch<Uint8>((n) => calloc<Uint8>(n));

  /// The engine's buffer for the bytes of ONE picture of several tiles —
  /// at least [byteLength] of them, holding whatever the last picture left
  /// there. Valid until the next ask: the upload that reads it consumes
  /// the bytes inside its own call, so one buffer serves every picture,
  /// and nothing holds it across an await.
  ///
  /// ⛔Not a buffer a picture: a block is a megabyte, and a fresh one each
  /// time is fresh pages for the system to fault in and clear.
  Pointer<Uint8> tilesPictureScratch(int byteLength) =>
      _tilesPictureScratch.ensure(byteLength);

  final void Function(Pointer<Uint8> dst, int length) _zeroBytes;

  /// A native memset — a zeroed tile without the VM's debug-build
  /// `fillRange` loop (`qa_zero_bytes`, ABI 40).
  void zeroBytes(Pointer<Uint8> dst, int length) {
    _zeroBytes(dst, length);
  }

  final Pointer<Void> Function(int size) _tileAlloc;
  final Pointer<NativeFunction<Pointer<Void> Function(Int64)>>
  _tileAllocPointer;
  final void Function(Pointer<Void> pixels) _tileFree;
  final Pointer<NativeFinalizerFunction> _tileFreePointer;
  final int Function() _tilePoolCachedBytes;
  final void Function() _tilePoolTrim;
  final void Function(int) _tilePoolSetByteCap;

  /// Allocates tile pixel bytes from the C free-list allocator (R20-E1).
  /// Freed/finalized tile blocks park in exact-size C-side lists, so a
  /// "fresh" buffer is a recycled block, not a malloc (🔬the measure is
  /// beside `qa_tile_alloc`). Free via [tileFree] or [tileFinalizer].
  Pointer<Uint8> tileAlloc(int byteLength) =>
      qaTileBlockOrThrow(_tileAlloc(byteLength), byteLength);

  /// Returns a [tileAlloc] block to the C free list.
  void tileFree(Pointer<Uint8> pixels) {
    _tileFree(pixels.cast());
  }

  /// Finalizer that frees [tileAlloc] blocks — BitmapTile attaches this
  /// when the engine is loaded (GC threads call qa_tile_free directly).
  late final NativeFinalizer tileFinalizer = NativeFinalizer(_tileFreePointer);

  /// [tileAlloc] and [tileFree] by address, for a worker that fills blocks
  /// THIS isolate's tiles adopt ([QaTileBlocksAt]): the worker's own probe
  /// can load another binary, or none — a test's path override and its
  /// forced fallback are statics, and statics do not cross isolates.
  int get tileAllocAddress => _tileAllocPointer.address;
  int get tileFreeAddress => _tileFreePointer.address;

  /// Bytes of tile blocks parked in the C free lists for reuse — resident,
  /// and nobody's picture. The memory census reads it.
  int get tilePoolParkedBytes => _tilePoolCachedBytes();

  /// Caps what the pool may keep parked. The memory tab's allowance sets it
  /// ([CacheBudgetLine.enginePool], v36); lowering it releases the excess
  /// on the spot.
  void setTilePoolByteCap(int bytes) => _tilePoolSetByteCap(bytes);

  /// The OS says memory is tight: give back what only makes the NEXT call
  /// cheaper — the tile blocks parked for reuse, and every scratch buffer
  /// (each regrows on its next call). Static, and never the call that
  /// loads the engine: a warning before any drawing has nothing to give.
  /// The app hears it with the GPU engine's (`DrawingEngines`).
  static void respondToMemoryPressure() {
    _instance?._tilePoolTrim();
    NativeScratch.releaseAll();
  }

  static QaNativeEngine? _instance;
  static bool _loadAttempted = false;

  /// Test hook: the parity test's reference side, forcing Dart even when
  /// a binary loads. Which binary is [debugQaEngineLibraryPathOverride],
  /// shared by every loader.
  static bool debugForceDartFallback = false;

  static void debugResetForTests() {
    _instance = null;
    _loadAttempted = false;
  }

  /// The loaded engine, or null (Dart fallback). Load happens once.
  static QaNativeEngine? get instance {
    if (debugForceDartFallback) {
      return null;
    }
    if (!_loadAttempted) {
      _loadAttempted = true;
      _instance = _tryLoad();
    }
    return _instance;
  }

  static QaNativeEngine? _tryLoad() {
    final library = openQaEngineLibrary();
    if (library == null) {
      return null;
    }
    try {
      final premultiplyRgbaCopy = library
          .lookupFunction<
            Void Function(Pointer<Uint8>, Pointer<Uint8>, Int32),
            void Function(Pointer<Uint8>, Pointer<Uint8>, int)
          >('qa_premultiply_rgba_copy');
      final premultiplyRgbaRows = library
          .lookupFunction<
            Void Function(
              Pointer<Uint8>,
              Int64,
              Pointer<Uint8>,
              Int64,
              Int32,
              Int32,
            ),
            void Function(Pointer<Uint8>, int, Pointer<Uint8>, int, int, int)
          >('qa_premultiply_rgba_rows');
      final zeroBytes = library
          .lookupFunction<
            Void Function(Pointer<Uint8>, Int64),
            void Function(Pointer<Uint8>, int)
          >('qa_zero_bytes');
      final tileAlloc = library
          .lookupFunction<
            Pointer<Void> Function(Int64),
            Pointer<Void> Function(int)
          >('qa_tile_alloc');
      final tileAllocPointer = library
          .lookup<NativeFunction<Pointer<Void> Function(Int64)>>(
            'qa_tile_alloc',
          );
      final tileFree = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('qa_tile_free');
      final tileFreePointer = library
          .lookup<NativeFunction<Void Function(Pointer<Void>)>>('qa_tile_free');
      final tilePoolCachedBytes = library
          .lookupFunction<Int64 Function(), int Function()>(
            'qa_tile_pool_cached_bytes',
          );
      final tilePoolTrim = library
          .lookupFunction<Void Function(), void Function()>(
            'qa_tile_pool_trim',
          );
      final tilePoolSetByteCap = library
          .lookupFunction<Void Function(Int64), void Function(int)>(
            'qa_tile_pool_set_byte_cap',
          );
      return QaNativeEngine._(
        premultiplyRgbaCopy,
        premultiplyRgbaRows,
        zeroBytes,
        tileAlloc,
        tileAllocPointer,
        tileFree,
        tileFreePointer,
        tilePoolCachedBytes,
        tilePoolTrim,
        tilePoolSetByteCap,
      );
    } on Object {
      return null;
    }
  }

  /// Uploaded stamp RGBA byte buffers keyed by the SOURCE Uint8List's
  /// identity (BrushStampImage.rgba is a final field, so the identity is
  /// stable for the stamp's lifetime). Small LRU: the same picture asked
  /// for again ([premultipliedStampCopy]) is not copied in again. A freshly
  /// uploaded entry is always the most recent, so it can never be evicted
  /// while the call that asked for it still reads it.
  final stampUploads = NativeUploadCache<Uint8List>(
    entryCap: 4,
    byteBudget: stampUploadByteBudget,
  );

  /// Bytes the native upload cache holds — the stamp bytes copied into
  /// native memory. ↩️Till 2026-11-12 the C brush's mask alphas were a
  /// second cache counted here, with half the allowance.
  ///
  /// 🔬Counted so the memory readout can NAME them: byte-budgeted and
  /// reported to no one, their bytes landed in `untrackedBytes` and read as
  /// engine overhead — which is exactly how a cache stops being anybody's
  /// business.
  int get nativeUploadBytes => stampUploads.residentBytes;

  /// What the upload cache may hold — the memory tab's allowance sets it
  /// ([CacheBudgets.nativeUploads]).
  int get nativeUploadByteBudget => stampUploads.byteBudget;

  set nativeUploadByteBudget(int bytes) {
    stampUploads.byteBudget = bytes;
  }

  /// Entry-count AND byte-budgeted (R19-8K): a full-canvas fill stamp at
  /// 8000² is 256MB — four of those resident was a 1GB RSS bomb. The
  /// newest entry always survives even when it alone exceeds the budget.
  static const int stampUploadByteBudget = 320 * 1024 * 1024;

  /// R25: fused premultiplied copy of an already-NATIVE tile buffer
  /// (the live rasterizer's stroke tiles) — one C call replaces the
  /// overlay's per-tile Dart row-copy + premultiply loops. Free the
  /// scratch in the decode callback.
  QaStampScratch premultipliedTileScratch(
    Pointer<Uint8> source,
    int pixelCount,
  ) {
    final buffer = malloc<Uint8>(pixelCount * 4);
    _premultiplyRgbaCopy(buffer, source, pixelCount);
    return QaStampScratch._(buffer.asTypedList(pixelCount * 4), buffer);
  }
}

/// Rows of pixels in native memory: where the first row starts and how many
/// bytes on the next one does. A stride belongs to its rows — handed apart,
/// one plane's stride could walk the other's rows.
typedef NativeRows = ({Pointer<Uint8> start, int stride});

/// A fresh premultiplied stamp buffer (R23 fill overlay): [view] feeds
/// `ui.decodeImageFromPixels`, and [free] releases it.
///
/// ⛔**NOT in the decode callback.** This line used to say that, and it was
/// the bug: `ui.decodeImageFromPixels` does not invoke its callback when it
/// REFUSES, so a failed decode leaked the whole scratch. All four call sites
/// were moved to a `finally` (see [debugLiveCount], and the note beside the
/// one in `straight_rgba_image.dart` — "THE `finally` IS THE FIX") and this
/// sentence outlived them, telling the next reader to put it back.
class QaStampScratch {
  QaStampScratch._(this.view, this._buffer) {
    _live += 1;
  }

  final Uint8List view;
  final Pointer<Uint8> _buffer;

  /// The raw buffer — a kernel writing INTO this scratch needs it.
  Pointer<Uint8> get pointer => _buffer;

  void free() {
    malloc.free(_buffer);
    _live -= 1;
  }

  static int _live = 0;

  /// How many of these are alive right now.
  ///
  /// 🧪★★★**A LEAK HERE IS INVISIBLE TO EVERYTHING ELSE.** This is a bare
  /// `malloc` with no `NativeFinalizer` behind it, so an unfreed scratch is
  /// not reclaimed by the GC, does not show up in Dart heap numbers, and
  /// costs a whole stamp — 256 KB at the production tile size, megabytes at
  /// whole-canvas. Four call sites freed it inside a decode CALLBACK, which
  /// `ui.decodeImageFromPixels` does not invoke when it refuses; every one
  /// of them now frees in a `finally` instead, and without a count the
  /// difference between those two shapes is something no test can see.
  ///
  /// ⛔Read it around an operation, never as an absolute: this is a
  /// process-wide counter and other work holds scratches at the same time.
  @visibleForTesting
  static int get debugLiveCount => _live;
}
