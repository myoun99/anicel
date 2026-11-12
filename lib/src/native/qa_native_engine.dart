import 'dart:ffi';
import 'dart:math' as math;

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
    this._dabBlendBatch,
    this._stampBlendTiles,
    this._strokeBlendTiles,
    this._preBlendTiles,
    this._premultiplyRgbaCopy,
    this._premultiplyRgbaRows,
    this._copyBytes,
    this._zeroBytes,
    this._widenBytes,
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

  final void Function(Pointer<Uint8> dst, Pointer<Uint8> src, int length)
  _copyBytes;

  /// Native-to-native memcpy at full speed (R19-Z tile staging — the
  /// VM's typed-data setRange ran several times slower in debug).
  void copyBytes(Pointer<Uint8> dst, Pointer<Uint8> src, int length) {
    _copyBytes(dst, src, length);
  }

  final void Function(Pointer<Uint8> dst, int length) _zeroBytes;

  /// A native memset — a zeroed tile without the VM's debug-build
  /// `fillRange` loop (`qa_zero_bytes`, ABI 40).
  void zeroBytes(Pointer<Uint8> dst, int length) {
    _zeroBytes(dst, length);
  }

  final void Function(Pointer<Uint8> bytes, Pointer<Uint16> wide, int count)
  _widenBytes;

  /// A stroke tile's 16-bit plane widened from its bytes, natively
  /// (`qa_widen_bytes`, ABI 40).
  void widenBytes(Pointer<Uint8> bytes, Pointer<Uint16> wide, int count) {
    _widenBytes(bytes, wide, count);
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
  /// commit's "fresh" buffers are recycled blocks, not mallocs — adoption
  /// (R19-Z) had drained the old Dart pool, costing ~1024 fresh mallocs
  /// per full-canvas 8K fill. Free via [tileFree] or [tileFinalizer].
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

  final void Function(
    Pointer<QaTileSpanStruct> tiles,
    int tileCount,
    int tileSize,
    Pointer<QaDabSpecStruct> specs,
    Pointer<Int32> clips,
    int dabCount,
    int dualMode,
    double dualDensity,
    Pointer<Uint8> changedOut,
  )
  _dabBlendBatch;

  final void Function(
    Pointer<QaTileSpanStruct> tiles,
    int tileCount,
    int tileSize,
    Pointer<Uint8> stamp,
    int stampWidth,
    int stampLeft,
    int stampTop,
    double opacity,
    int erase,
    Pointer<Uint8> changedOut,
  )
  _stampBlendTiles;

  /// BB-N1 (ABI 22): the once-per-stroke brush blend — the staged tiles
  /// ARE the destination; C blends the stroke buffer in and reports
  /// per-tile changed flags. Reference = `blendStrokeRegionPixels`.
  final void Function(
    Pointer<QaTileSpanStruct> tiles,
    int tileCount,
    int tileSize,
    Pointer<Uint8> stroke,
    int strokeWidth,
    int strokeLeft,
    int strokeTop,
    int mode,
    Pointer<Uint8> changedOut,
  )
  _strokeBlendTiles;

  /// ABI 24: the fused pre-blend (stage + blend + premultiply, masked).
  /// Reference = `preBlendStrokeOverlayPixels`.
  final void Function(
    Pointer<QaTileSpanStruct> tiles,
    int tileCount,
    int tileSize,
    int kind,
    int mode,
    Pointer<Uint8> changedOut,
  )
  _preBlendTiles;

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

  /// Calls [dabBlendBatch] has made, counted in debug builds only — the
  /// pin that a batch of dabs is ONE call.
  @visibleForTesting
  static int debugDabBatchCalls = 0;

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
      // Struct-layout paranoia: both sides must agree on the spec's exact
      // byte layout, or every field read is garbage. Any mismatch means
      // Dart fallback, never a corrupt blend.
      if (!qaStructSizeMatches(
            library,
            'qa_dab_spec_sizeof',
            sizeOf<QaDabSpecStruct>(),
          ) ||
          !qaStructSizeMatches(
            library,
            'qa_tile_span_sizeof',
            sizeOf<QaTileSpanStruct>(),
          )) {
        return null;
      }
      final dabBlendBatch = library
          .lookupFunction<
            Void Function(
              Pointer<QaTileSpanStruct>,
              Int32,
              Int32,
              Pointer<QaDabSpecStruct>,
              Pointer<Int32>,
              Int32,
              Int32,
              Double,
              Pointer<Uint8>,
            ),
            void Function(
              Pointer<QaTileSpanStruct>,
              int,
              int,
              Pointer<QaDabSpecStruct>,
              Pointer<Int32>,
              int,
              int,
              double,
              Pointer<Uint8>,
            )
          >('qa_dab_blend_batch');
      final stampBlendTiles = library
          .lookupFunction<
            Void Function(
              Pointer<QaTileSpanStruct>,
              Int32,
              Int32,
              Pointer<Uint8>,
              Int32,
              Int32,
              Int32,
              Double,
              Int32,
              Pointer<Uint8>,
            ),
            void Function(
              Pointer<QaTileSpanStruct>,
              int,
              int,
              Pointer<Uint8>,
              int,
              int,
              int,
              double,
              int,
              Pointer<Uint8>,
            )
          >('qa_stamp_blend_tiles');
      final strokeBlendTiles = library
          .lookupFunction<
            Void Function(
              Pointer<QaTileSpanStruct>,
              Int32,
              Int32,
              Pointer<Uint8>,
              Int32,
              Int32,
              Int32,
              Int32,
              Pointer<Uint8>,
            ),
            void Function(
              Pointer<QaTileSpanStruct>,
              int,
              int,
              Pointer<Uint8>,
              int,
              int,
              int,
              int,
              Pointer<Uint8>,
            )
          >('qa_stroke_blend_tiles');
      final preBlendTiles = library
          .lookupFunction<
            Void Function(
              Pointer<QaTileSpanStruct>,
              Int32,
              Int32,
              Int32,
              Int32,
              Pointer<Uint8>,
            ),
            void Function(
              Pointer<QaTileSpanStruct>,
              int,
              int,
              int,
              int,
              Pointer<Uint8>,
            )
          >('qa_pre_blend_tiles');
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
      final copyBytes = library
          .lookupFunction<
            Void Function(Pointer<Uint8>, Pointer<Uint8>, Int64),
            void Function(Pointer<Uint8>, Pointer<Uint8>, int)
          >('qa_copy_bytes');
      final zeroBytes = library
          .lookupFunction<
            Void Function(Pointer<Uint8>, Int64),
            void Function(Pointer<Uint8>, int)
          >('qa_zero_bytes');
      final widenBytes = library
          .lookupFunction<
            Void Function(Pointer<Uint8>, Pointer<Uint16>, Int64),
            void Function(Pointer<Uint8>, Pointer<Uint16>, int)
          >('qa_widen_bytes');
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
        dabBlendBatch,
        stampBlendTiles,
        strokeBlendTiles,
        preBlendTiles,
        premultiplyRgbaCopy,
        premultiplyRgbaRows,
        copyBytes,
        zeroBytes,
        widenBytes,
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
  /// stable for the stamp's lifetime). Small LRU — a move session
  /// re-commits the SAME lift stamp on every drag move, so after the
  /// first upload the whole stamp blend is zero-copy (A-1.5). A freshly
  /// uploaded entry is always the most recent, so it can never be
  /// evicted while its dab is still blending.
  final stampUploads = NativeUploadCache<Uint8List>(
    entryCap: 4,
    byteBudget: stampUploadByteBudget,
  );

  /// Bytes the two native upload caches hold between them — the stamp
  /// bytes and the mask alphas copied into native memory.
  ///
  /// 🔬Counted so the memory readout can NAME them. Both are
  /// byte-budgeted and neither reported to anyone, so their bytes landed
  /// in `untrackedBytes` and read as engine overhead — which is exactly
  /// how a cache stops being anybody's business.
  int get nativeUploadBytes =>
      stampUploads.residentBytes + _maskUploads.residentBytes;

  /// What the two upload caches may hold between them, split evenly — the
  /// memory tab's allowance sets it ([CacheBudgets.nativeUploads]).
  int get nativeUploadByteBudget =>
      stampUploads.byteBudget + _maskUploads.byteBudget;

  set nativeUploadByteBudget(int bytes) {
    stampUploads.byteBudget = bytes ~/ 2;
    _maskUploads.byteBudget = bytes ~/ 2;
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

  /// An EMPTY upload buffer for a kernel to fill (ABI 24: the fused
  /// pre-blend writes the premultiplied result straight into it). Free it
  /// once the decode has consumed the view.
  QaStampScratch acquireScratch(int byteLength) {
    final buffer = malloc<Uint8>(byteLength);
    return QaStampScratch._(buffer.asTypedList(byteLength), buffer);
  }

  /// Grow-only batch buffers (R18 A-3a): the tile spans of one dab and
  /// the per-tile changed flags, staged once per dab and fanned across
  /// the C worker pool.
  final _tileSpans = NativeScratch<QaTileSpanStruct>(
    (n) => calloc<QaTileSpanStruct>(n),
    bytesPerElement: sizeOf<QaTileSpanStruct>(),
  );
  final _batchChanged = NativeScratch<Uint8>((n) => calloc<Uint8>(n));

  /// Makes room for [count] spans in the current batch.
  void ensureTileSpanBatch(int count) {
    _tileSpans.ensure(count);
    _batchChanged.ensure(count);
  }

  /// Stages the [index]-th span of the batch ([ensureTileSpanBatch] first).
  void setTileSpan(
    int index, {
    required Pointer<Uint8> tilePixels,
    required int tileLeft,
    required int tileTop,
    required int spanLeft,
    required int spanRightExclusive,
    required int spanTop,
    required int spanBottomExclusive,
    // ABI 24 — only the fused pre-blend reads these; every other kernel
    // ignores them, so they default to "absent".
    Pointer<Uint8>? basePixels,
    Pointer<Uint8>? strokePixels,
    Pointer<Uint8>? maskPixels,
    Pointer<Uint8>? premulOut,
    // ABI 40 — only the dab batch reads it.
    Pointer<Uint16>? tileWide,
    // ABI 60 — the second plane of a stroke with a second tip; only the dab
    // batch reads it.
    Pointer<Uint16>? tileSecond,
  }) {
    final span = _tileSpans.pointer[index];
    span.tilePixels = tilePixels;
    span.tileLeft = tileLeft;
    span.tileTop = tileTop;
    span.spanLeft = spanLeft;
    span.spanRightExclusive = spanRightExclusive;
    span.spanTop = spanTop;
    span.spanBottomExclusive = spanBottomExclusive;
    span.reserved = 0;
    span.basePixels = basePixels ?? nullptr;
    span.strokePixels = strokePixels ?? nullptr;
    span.maskPixels = maskPixels ?? nullptr;
    span.premulOut = premulOut ?? nullptr;
    span.tileWide = tileWide ?? nullptr;
    span.tileSecond = tileSecond ?? nullptr;
  }

  /// ABI 24: stages, blends and premultiplies every staged span in ONE
  /// pooled call — the live overlay's whole frame of tiles.
  ///
  /// [kind] picks the composite the stroke lands with
  /// ([preBlendKindSrcOver] / [preBlendKindErase] / [preBlendKindStroke]),
  /// and [mode] carries the `QA_STROKE_BLEND_*` id when the kind is
  /// STROKE. Returns per-tile changed flags (valid until the next batch);
  /// a tile reports unchanged when the stroke moved no byte of the base,
  /// which is what keeps untouched coordinates out of the commit.
  Uint8List preBlendTiles({
    required int count,
    required int tileSize,
    required int kind,
    int mode = 0,
  }) {
    _preBlendTiles(
      _tileSpans.pointer,
      count,
      tileSize,
      kind,
      mode,
      _batchChanged.pointer,
    );
    return _batchChanged.pointer.asTypedList(count);
  }

  static const int preBlendKindSrcOver = 0;
  static const int preBlendKindErase = 1;
  static const int preBlendKindStroke = 2;

  /// Blends the [dabCount] dabs of the batch ([beginDabBatch],
  /// [prepareDabAt]), in order, into the [tileCount] staged spans in ONE
  /// call — each span the rect the batch's dabs cover in that tile. The C
  /// cuts the tiles into row bands and each band applies every dab that
  /// reaches it, so the bytes are the ones the dabs would have made one at
  /// a time. [view] is what a span carrying a second plane is rebuilt
  /// through (`qa_dual_view_rows`) — its composite mode, a
  /// `QA_STROKE_BLEND_*` id, and its density; null for a stroke with no
  /// second tip. Returns the per-tile changed flags (valid until the next
  /// batch).
  Uint8List dabBlendBatch({
    required int tileCount,
    required int dabCount,
    required int tileSize,
    ({int mode, double density})? view,
  }) {
    assert(() {
      debugDabBatchCalls += 1;
      return true;
    }());
    _dabBlendBatch(
      _tileSpans.pointer,
      tileCount,
      tileSize,
      _dabSpecs.pointer,
      _dabClips.pointer,
      dabCount,
      view?.mode ?? 0,
      view?.density ?? 0.0,
      _batchChanged.pointer,
    );
    return _batchChanged.pointer.asTypedList(tileCount);
  }

  /// The stamp counterpart of [dabBlendBatch], one stamp a call.
  Uint8List stampBlendTiles({
    required int count,
    required int tileSize,
    required Pointer<Uint8> stampBytes,
    required int stampWidth,
    required int stampLeft,
    required int stampTop,
    required double opacity,
    required bool erase,
  }) {
    _stampBlendTiles(
      _tileSpans.pointer,
      count,
      tileSize,
      stampBytes,
      stampWidth,
      stampLeft,
      stampTop,
      opacity,
      erase ? 1 : 0,
      _batchChanged.pointer,
    );
    return _batchChanged.pointer.asTypedList(count);
  }

  /// BB-N1: blends the stroke buffer into every staged span in ONE call,
  /// fanned across the worker pool (per-pixel math is independent, so
  /// worker count never changes a byte). [mode] is the C-side
  /// `QA_STROKE_BLEND_*` id (`strokeBlendModeNativeId`). Returns per-tile
  /// changed flags (valid until the next batch).
  Uint8List strokeBlendTiles({
    required int count,
    required int tileSize,
    required Pointer<Uint8> strokeBytes,
    required int strokeWidth,
    required int strokeLeft,
    required int strokeTop,
    required int mode,
  }) {
    _strokeBlendTiles(
      _tileSpans.pointer,
      count,
      tileSize,
      strokeBytes,
      strokeWidth,
      strokeLeft,
      strokeTop,
      mode,
      _batchChanged.pointer,
    );
    return _batchChanged.pointer.asTypedList(count);
  }

  // -------------------------------------------------------------------
  // Native-backed tile scratch buffers (R18 A-1 / R20-E1).
  //
  // The materializer's per-tile scratch lives in native memory: the Dart
  // side works on an asTypedList VIEW (so the Dart fallback loops and the
  // stamp path run unchanged), while the native kernel gets the raw
  // pointer — zero tile copies per dab. Buffers come from the C free-list
  // allocator: commits ADOPT them as finished tiles (R19-Z), and the tile
  // finalizers return the blocks to the same C lists — the old Dart-side
  // pool could never see adopted buffers again, so every fill paid ~1024
  // fresh mallocs. One cache layer, C-side, byte-capped.

  /// [zeroed] skips the memset when the caller overwrites every byte
  /// anyway (existing-tile copy-in).
  QaNativeTileBuffer acquireTileBuffer(int byteLength, {required bool zeroed}) {
    final pointer = tileAlloc(byteLength);
    final view = pointer.asTypedList(byteLength);
    if (zeroed) {
      _zeroBytes(pointer, byteLength);
    }
    return QaNativeTileBuffer._(pointer, view);
  }

  /// Buffers handed back through [releaseTileBuffer], counted in debug
  /// builds only — the pin that a result the budget lets go of gives its
  /// block back.
  @visibleForTesting
  static int debugReleasedTileBuffers = 0;

  void releaseTileBuffer(QaNativeTileBuffer buffer) {
    assert(() {
      debugReleasedTileBuffers += 1;
      return true;
    }());
    tileFree(buffer.pointer);
  }

  // -------------------------------------------------------------------
  // Generic dab blend (R18 A-1; one call a batch since ABI 38).

  /// The batch's dab specs, one per [prepareDabAt] index.
  final _dabSpecs = NativeScratch<QaDabSpecStruct>(
    (n) => calloc<QaDabSpecStruct>(n),
    bytesPerElement: sizeOf<QaDabSpecStruct>(),
  );

  /// Four ints a dab — its clip's left, top, right and bottom (exclusive).
  final _dabClips = NativeScratch<Int32>(
    (n) => calloc<Int32>(n),
    bytesPerElement: 4,
  );

  /// Uploaded mask alphas keyed by the SOURCE Float64List's identity
  /// (BrushTipMask.alphaNormalized is `late final`, so the identity is
  /// stable for a mask's lifetime).
  ///
  /// 🚨ROOM FOR A WHOLE TIP LIST: a brush takes its tips in turn (F-176-Q3)
  /// — Clip Studio's 遠くの雲 carries thirteen — and a stroke reuses every
  /// one of them, its dual and its texture, dab after dab. ↩️Eight stood
  /// here for "the same two or three masks", which a thirteen-tip stroke
  /// would have evicted and uploaded again every few dabs, a batch cut at
  /// each ([batchMaskAllowance]). The bytes stay the real bound.
  final _maskUploads = NativeUploadCache<Float64List>(
    entryCap: 64,
    byteBudget: stampUploadByteBudget,
  );

  /// How many distinct masks, and how many of their bytes, one dab batch
  /// may upload with every one of them still resident when the kernel
  /// reads it. The cache frees from its least recent end, and a batch's
  /// masks are its most recent entries, so a batch inside both limits
  /// evicts only masks from before it.
  ({int count, int bytes}) get batchMaskAllowance =>
      (count: _maskUploads.entryCap, bytes: _maskUploads.byteBudget);

  /// The grow-only arena the batch's lattice arrays are copied into
  /// ([prepareDabAt]) and the kernel reads.
  ///
  /// ⛔IT GROWS BY OPENING A CHUNK, NEVER BY MOVING ONE: the specs already
  /// staged in the batch point into the chunks before, so a chunk lives
  /// until the process does and is reused from the next [beginDabBatch].
  final List<({Pointer<Uint8> base, int capacity})> _arenaChunks = [];
  int _arenaChunk = 0;
  int _arenaOffset = 0;

  static const int _arenaChunkBytes = 64 * 1024;

  /// Opens a batch of [dabCount] dabs: room for their specs and clips, and
  /// the arena back to its start.
  /// The specs [prepareDabAt] staged — what a kernel other than the dab
  /// blend reads a dab through (the blur's coverage, I-75).
  Pointer<QaDabSpecStruct> get stagedDabSpecs => _dabSpecs.pointer;

  void beginDabBatch(int dabCount) {
    _dabSpecs.ensure(dabCount);
    _dabClips.ensure(dabCount * 4);
    _arenaChunk = 0;
    _arenaOffset = 0;
    _batchTables.clear();
  }

  /// Each table the batch has staged, by identity — a share's evening
  /// table, a round tip's profile: a stroke's dabs lay a few shares at a
  /// few sizes (`eveningTableFor` keeps one table a share,
  /// `RoundTipProfile.of` one profile a tip), so a table is copied into the
  /// arena once a batch rather than once a dab.
  final Map<Float64List, Pointer<Double>> _batchTables =
      Map<Float64List, Pointer<Double>>.identity();

  Pointer<Double> _batchTable(Float64List table) =>
      _batchTables.putIfAbsent(table, () => _arenaFloat64(table));

  Pointer<Uint8> _arenaAlloc(int bytes) {
    // Keep every array 8-byte aligned (doubles).
    var aligned = (_arenaOffset + 7) & ~7;
    while (_arenaChunk < _arenaChunks.length &&
        aligned + bytes > _arenaChunks[_arenaChunk].capacity) {
      _arenaChunk += 1;
      aligned = 0;
    }
    if (_arenaChunk == _arenaChunks.length) {
      final capacity = math.max(bytes, _arenaChunkBytes);
      _arenaChunks.add((base: calloc<Uint8>(capacity), capacity: capacity));
      aligned = 0;
    }
    _arenaOffset = aligned + bytes;
    return Pointer<Uint8>.fromAddress(
      _arenaChunks[_arenaChunk].base.address + aligned,
    );
  }

  Pointer<Double> _arenaFloat64(Float64List data) {
    final pointer = _arenaAlloc(data.length * 8).cast<Double>();
    pointer.asTypedList(data.length).setAll(0, data);
    return pointer;
  }

  Pointer<Int32> _arenaInt32(Int32List data) {
    final pointer = _arenaAlloc(data.length * 4).cast<Int32>();
    pointer.asTypedList(data.length).setAll(0, data);
    return pointer;
  }

  Pointer<Uint8> _arenaUint8(Uint8List data) {
    final pointer = _arenaAlloc(data.length);
    pointer.asTypedList(data.length).setAll(0, data);
    return pointer;
  }

  static const int dabFlagErase = 1;
  static const int dabFlagRound = 2;
  static const int dabFlagEllipse = 4;
  static const int dabFlagTipUnrotated = 16;

  /// 없음 — the edge is a hard cut at half coverage. Set INSTEAD of an
  /// [aaContrast]; the two never both apply (see `BrushAntiAlias`).
  static const int dabFlagAaThreshold = 32;

  /// 高さ — the paper texture's height cuts the coverage
  /// (`BrushTextureMode.height`) instead of multiplying it. v53.
  static const int dabFlagTextureHeight = 64;

  /// The tip holds an edge that does not pile (`tipHoldsAnEdge`). v56.
  static const int dabFlagEdgeHeld = 128;

  /// The dab is the second tip's: it piles on the tile's second plane and
  /// moves no byte — the batch's view does (`qa_dual_view_rows`). v60.
  static const int dabFlagSecond = 256;

  /// Stages dab [index] of the batch ([beginDabBatch]) for
  /// [dabBlendBatch]: fills its spec and its clip, and uploads masks
  /// (identity-cached) and lattices (arena). All values mirror the Dart
  /// materializer's per-dab hoists exactly; the kernel is a pure consumer.
  ///
  /// ⚠️A batch uploads no more masks than [batchMaskAllowance] — the
  /// callers cut it there. The mask cache keeps only its newest entry for
  /// sure, so a batch past the allowance could free a mask an earlier spec
  /// still points at.
  void prepareDabAt(
    int index, {
    required int clipLeft,
    required int clipTop,
    required int clipRightExclusive,
    required int clipBottomExclusive,
    required double centerX,
    required double centerY,
    required double radius,
    required double roundScale,
    required double roundReach,
    required double roundInner,
    required double roundRowLength,
    required double minorRadius,
    required double tipCos,
    required double tipSin,
    required double inverseRoundness,
    required double dabOpacity,
    required double dabFlow,
    required double sourceAlphaNorm,
    required double radiusSqSkip,
    required double textureDensity,
    required double textureOneMinusDensity,
    required double aaContrast,
    required int sourceR,
    required int sourceG,
    required int sourceB,
    required int flags,
    required int regionLeft,
    required int regionTop,
    Float64List? tipAlpha,
    int tipSize = 0,
    Int32List? tipUTexel0,
    Float64List? tipUFraction,
    Float64List? tipUOneMinus,
    Uint8List? tipUInRange,
    Int32List? tipVTexel0,
    Float64List? tipVFraction,
    Float64List? tipVOneMinus,
    Uint8List? tipVInRange,
    Float64List? texAlpha,
    int texSize = 0,
    Int32List? texUTexel0,
    Int32List? texUTexel1,
    Float64List? texUFraction,
    Float64List? texUOneMinus,
    Int32List? texVTexel0,
    Int32List? texVTexel1,
    Float64List? texVFraction,
    Float64List? texVOneMinus,
    Int32List? tipRowInk,
    Float64List? evening,
    Float64List? roundCoverage,
    Float64List? roundPile,
  }) {
    final clip = _dabClips.pointer + index * 4;
    clip[0] = clipLeft;
    clip[1] = clipTop;
    clip[2] = clipRightExclusive;
    clip[3] = clipBottomExclusive;
    final spec = _dabSpecs.pointer[index];
    spec.centerX = centerX;
    spec.centerY = centerY;
    spec.radius = radius;
    spec.roundScale = roundScale;
    spec.roundReach = roundReach;
    spec.roundInner = roundInner;
    spec.roundRowLength = roundRowLength;
    spec.minorRadius = minorRadius;
    spec.tipCos = tipCos;
    spec.tipSin = tipSin;
    spec.inverseRoundness = inverseRoundness;
    spec.dabOpacity = dabOpacity;
    spec.dabFlow = dabFlow;
    spec.sourceAlphaNorm = sourceAlphaNorm;
    spec.radiusSqSkip = radiusSqSkip;
    spec.textureDensity = textureDensity;
    spec.textureOneMinusDensity = textureOneMinusDensity;
    spec.aaContrast = aaContrast;
    spec.sourceR = sourceR;
    spec.sourceG = sourceG;
    spec.sourceB = sourceB;
    spec.flags = flags;
    spec.regionLeft = regionLeft;
    spec.regionTop = regionTop;
    spec.tipSize = tipSize;
    spec.texSize = texSize;
    spec.tipAlpha = tipAlpha == null
        ? nullptr
        : _maskUploads.upload(tipAlpha).cast<Double>();
    spec.tipUTexel0 = tipUTexel0 == null ? nullptr : _arenaInt32(tipUTexel0);
    spec.tipUFraction = tipUFraction == null
        ? nullptr
        : _arenaFloat64(tipUFraction);
    spec.tipUOneMinus = tipUOneMinus == null
        ? nullptr
        : _arenaFloat64(tipUOneMinus);
    spec.tipUInRange = tipUInRange == null ? nullptr : _arenaUint8(tipUInRange);
    spec.tipVTexel0 = tipVTexel0 == null ? nullptr : _arenaInt32(tipVTexel0);
    spec.tipVFraction = tipVFraction == null
        ? nullptr
        : _arenaFloat64(tipVFraction);
    spec.tipVOneMinus = tipVOneMinus == null
        ? nullptr
        : _arenaFloat64(tipVOneMinus);
    spec.tipVInRange = tipVInRange == null ? nullptr : _arenaUint8(tipVInRange);
    spec.texAlpha = texAlpha == null
        ? nullptr
        : _maskUploads.upload(texAlpha).cast<Double>();
    spec.texUTexel0 = texUTexel0 == null ? nullptr : _arenaInt32(texUTexel0);
    spec.texUTexel1 = texUTexel1 == null ? nullptr : _arenaInt32(texUTexel1);
    spec.texUFraction = texUFraction == null
        ? nullptr
        : _arenaFloat64(texUFraction);
    spec.texUOneMinus = texUOneMinus == null
        ? nullptr
        : _arenaFloat64(texUOneMinus);
    spec.texVTexel0 = texVTexel0 == null ? nullptr : _arenaInt32(texVTexel0);
    spec.texVTexel1 = texVTexel1 == null ? nullptr : _arenaInt32(texVTexel1);
    spec.texVFraction = texVFraction == null
        ? nullptr
        : _arenaFloat64(texVFraction);
    spec.texVOneMinus = texVOneMinus == null
        ? nullptr
        : _arenaFloat64(texVOneMinus);
    spec.tipRowInk = tipRowInk == null ? nullptr : _arenaInt32(tipRowInk);
    spec.evening = evening == null ? nullptr : _batchTable(evening);
    spec.roundCoverage = roundCoverage == null
        ? nullptr
        : _batchTable(roundCoverage);
    spec.roundPile = roundPile == null ? nullptr : _batchTable(roundPile);
  }
}

/// Rows of pixels in native memory: where the first row starts and how many
/// bytes on the next one does. A stride belongs to its rows — handed apart,
/// one plane's stride could walk the other's rows.
typedef NativeRows = ({Pointer<Uint8> start, int stride});

/// A pooled native tile buffer: the raw pointer for the kernel and a
/// typed-data view over the SAME memory for Dart-side reads/writes.
class QaNativeTileBuffer {
  QaNativeTileBuffer._(this.pointer, this.view);

  final Pointer<Uint8> pointer;
  final Uint8List view;
}

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

/// Mirror of the C `qa_tile_span` — field order/types must match EXACTLY
/// (the loader cross-checks sizeof on both sides before enabling the
/// native path).
final class QaTileSpanStruct extends Struct {
  external Pointer<Uint8> tilePixels;
  @Int32()
  external int tileLeft;
  @Int32()
  external int tileTop;
  @Int32()
  external int spanLeft;
  @Int32()
  external int spanRightExclusive;
  @Int32()
  external int spanTop;
  @Int32()
  external int spanBottomExclusive;
  @Int32()
  external int reserved;

  /// ABI 24 — the fused pre-blend's per-tile buffers, all tile-local on
  /// the same grid as [tilePixels]. The older kernels ignore them.
  external Pointer<Uint8> basePixels;
  external Pointer<Uint8> strokePixels;
  external Pointer<Uint8> maskPixels;
  external Pointer<Uint8> premulOut;

  /// ABI 40 — the stroke tile's 16-bit plane on the same grid as
  /// [tilePixels], what the dab batch piles up in (`qa_dab_store`). Every
  /// other kernel's spans leave it null.
  external Pointer<Uint16> tileWide;

  /// ABI 60 — the second plane of a stroke with a second tip, alpha * 65535
  /// a pixel on the same grid, where its second stroke piles
  /// (`qa_dual_view_rows`). Every other span leaves it null.
  external Pointer<Uint16> tileSecond;
}

/// Mirror of the C `qa_dab_spec` — field order/types must match EXACTLY
/// (the loader cross-checks sizeof on both sides before enabling the
/// native path).
final class QaDabSpecStruct extends Struct {
  @Double()
  external double centerX;
  @Double()
  external double centerY;
  @Double()
  external double radius;
  @Double()
  external double roundScale;
  @Double()
  external double roundReach;
  @Double()
  external double roundInner;

  /// ABI 57: entries a row of the round tables holds where they are square
  /// (`RoundTipProfile.rowLength` — a small circle's), or 0 where they run
  /// along the radius.
  @Double()
  external double roundRowLength;
  @Double()
  external double minorRadius;
  @Double()
  external double tipCos;
  @Double()
  external double tipSin;
  @Double()
  external double inverseRoundness;
  @Double()
  external double dabOpacity;
  @Double()
  external double dabFlow;
  @Double()
  external double sourceAlphaNorm;
  @Double()
  external double radiusSqSkip;
  @Double()
  external double textureDensity;
  @Double()
  external double textureOneMinusDensity;

  /// v31: the resolved brush-edge step (1.0 = leave the ramp alone).
  ///
  /// ⚠️THE ORDER OF THIS BLOCK IS THE ABI. It sits exactly where
  /// `aa_contrast` sits in `qa_dab_spec` — after `texture_one_minus_density`,
  /// last of the doubles — and `qa_dab_spec_sizeof` is what catches a slip.
  @Double()
  external double aaContrast;
  @Int32()
  external int sourceR;
  @Int32()
  external int sourceG;
  @Int32()
  external int sourceB;
  @Int32()
  external int flags;
  @Int32()
  external int regionLeft;
  @Int32()
  external int regionTop;
  @Int32()
  external int tipSize;
  @Int32()
  external int texSize;
  external Pointer<Double> tipAlpha;
  external Pointer<Int32> tipUTexel0;
  external Pointer<Double> tipUFraction;
  external Pointer<Double> tipUOneMinus;
  external Pointer<Uint8> tipUInRange;
  external Pointer<Int32> tipVTexel0;
  external Pointer<Double> tipVFraction;
  external Pointer<Double> tipVOneMinus;
  external Pointer<Uint8> tipVInRange;
  external Pointer<Double> texAlpha;
  external Pointer<Int32> texUTexel0;
  external Pointer<Int32> texUTexel1;
  external Pointer<Double> texUFraction;
  external Pointer<Double> texUOneMinus;
  external Pointer<Int32> texVTexel0;
  external Pointer<Int32> texVTexel1;
  external Pointer<Double> texVFraction;
  external Pointer<Double> texVOneMinus;

  /// ABI 39: each tip mask row's first and last inked column, or null.
  external Pointer<Int32> tipRowInk;

  /// ABI 41: the table the dab lays its share through (`qa_dab_even`), or
  /// null where it lays whole.
  external Pointer<Double> evening;

  /// ABI 56: an analytic round tip's two tables (`RoundTipProfile`), or
  /// null for any other tip.
  external Pointer<Double> roundCoverage;
  external Pointer<Double> roundPile;
}
