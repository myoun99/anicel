import 'dart:ffi';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'dart:typed_data';

import '../core/rgb_tolerance.dart';
import 'qa_engine_abi.dart';
import 'native_scratch.dart';
import 'native_upload_cache.dart';

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
    this._premultiplyRgba,
    this._fillPaperRect,
    this._fillComposeTile,
    this._fillFinishMask,
    this._dabBlendBatch,
    this._stampBlendTiles,
    this._strokeBlendTiles,
    this._alphaBoundsTiles,
    this._preBlendTiles,
    this._premultiplyRgbaCopy,
    this._copyBytes,
    this._tileAlloc,
    this._tileFree,
    this._tileFreePointer,
    this._tilePoolCachedBytes,
    this._tilePoolTrim,
    this._tilePoolSetByteCap,
    this._physicalMemoryBytes,
    this._processFootprintBytes,
    this._availableMemoryBytes,
    this._appMemoryLimitBytes,
    this._fillGapCloseRun,
    this._floodFillWave,
    this._fillComposeBatch,
    this._gridRasterTile,
    this._resampleRgba,
    this._celPixelPassTile,
  ) : _celSpec = calloc<QaCelPixelSpecStruct>(),
      _celCounts = calloc<Int32>(2);

  /// R25-③ batched fill compose: packs compose-tile items + their
  /// ordered layer blends into grow-only native arrays and fans the
  /// tiles across the worker pool in ONE call (the per-tile serial FFI
  /// compose was the fill's largest remaining serial slice).
  final _composeItems = NativeScratch<QaComposeTileItemStruct>(
    (n) => calloc<QaComposeTileItemStruct>(n),
    bytesPerElement: sizeOf<QaComposeTileItemStruct>(),
  );
  final _composeBlends = NativeScratch<QaComposeBlendStruct>(
    (n) => calloc<QaComposeBlendStruct>(n),
    bytesPerElement: sizeOf<QaComposeBlendStruct>(),
  );

  void fillComposeBatch({
    required int rasterWidth,
    required int paperR,
    required int paperG,
    required int paperB,
    required List<
      ({
        int left,
        int top,
        int rightExclusive,
        int bottomExclusive,
        int firstBlend,
        int blendCount,
      })
    >
    tiles,
    required List<
      ({
        Pointer<Uint8> pixels,
        int tileSize,
        int baseX,
        int baseY,
        int clipLeft,
        int clipTop,
        int clipRightExclusive,
        int clipBottomExclusive,
        int opacityInt,
      })
    >
    blends,
  }) {
    if (tiles.isEmpty) {
      return;
    }
    _composeItems.ensure(tiles.length);
    if (blends.isNotEmpty) {
      _composeBlends.ensure(blends.length);
    }
    for (var i = 0; i < tiles.length; i += 1) {
      final tile = tiles[i];
      final item = _composeItems.pointer + i;
      item.ref.tileLeft = tile.left;
      item.ref.tileTop = tile.top;
      item.ref.tileRightExclusive = tile.rightExclusive;
      item.ref.tileBottomExclusive = tile.bottomExclusive;
      item.ref.firstBlend = tile.firstBlend;
      item.ref.blendCount = tile.blendCount;
    }
    for (var i = 0; i < blends.length; i += 1) {
      final blend = blends[i];
      final entry = _composeBlends.pointer + i;
      entry.ref.tilePixels = blend.pixels;
      entry.ref.tileSize = blend.tileSize;
      entry.ref.baseX = blend.baseX;
      entry.ref.baseY = blend.baseY;
      entry.ref.clipLeft = blend.clipLeft;
      entry.ref.clipTop = blend.clipTop;
      entry.ref.clipRightExclusive = blend.clipRightExclusive;
      entry.ref.clipBottomExclusive = blend.clipBottomExclusive;
      entry.ref.opacityInt = blend.opacityInt;
      entry.ref.reserved = 0;
    }
    _fillComposeBatch(
      _floodRgb.pointer,
      rasterWidth,
      paperR,
      paperG,
      paperB,
      _composeItems.pointer,
      tiles.length,
      _composeBlends.pointer,
    );
  }

  final void Function(Pointer<Uint8> pixels, int pixelCount) _premultiplyRgba;

  final void Function(Pointer<Uint8> dst, Pointer<Uint8> src, int pixelCount)
  _premultiplyRgbaCopy;

  final void Function(Pointer<Uint8> dst, Pointer<Uint8> src, int length)
  _copyBytes;

  /// Native-to-native memcpy at full speed (R19-Z tile staging — the
  /// VM's typed-data setRange ran several times slower in debug).
  void copyBytes(Pointer<Uint8> dst, Pointer<Uint8> src, int length) {
    _copyBytes(dst, src, length);
  }

  final Pointer<Void> Function(int size) _tileAlloc;
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
  Pointer<Uint8> tileAlloc(int byteLength) {
    final pointer = _tileAlloc(byteLength);
    if (pointer == nullptr) {
      throw StateError('qa_tile_alloc failed for $byteLength bytes');
    }
    return pointer.cast();
  }

  /// Returns a [tileAlloc] block to the C free list.
  void tileFree(Pointer<Uint8> pixels) {
    _tileFree(pixels.cast());
  }

  /// Finalizer that frees [tileAlloc] blocks — BitmapTile attaches this
  /// when the engine is loaded (GC threads call qa_tile_free directly).
  late final NativeFinalizer tileFinalizer = NativeFinalizer(_tileFreePointer);

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
  static void respondToMemoryPressure() {
    _instance?._tilePoolTrim();
    NativeScratch.releaseAll();
  }

  final int Function() _physicalMemoryBytes;

  /// The device's physical RAM, or null when the platform refused to
  /// answer — callers keep their desktop-class default then. This is what
  /// lets the hot cel budget scale to the machine (v28).
  int? get physicalMemoryBytes {
    final bytes = _physicalMemoryBytes();
    return bytes <= 0 ? null : bytes;
  }

  final int Function() _processFootprintBytes;
  final int Function() _availableMemoryBytes;
  final int Function() _appMemoryLimitBytes;

  /// What THIS PROCESS is holding, or null where the platform will not
  /// say (v29).
  ///
  /// The number a jetsam report calls `rpages × pageSize` — the one that
  /// decides whether the app is about to be killed. [physicalMemoryBytes]
  /// answers a different question and has been standing in for it.
  int? get processFootprintBytes {
    final bytes = _processFootprintBytes();
    return bytes <= 0 ? null : bytes;
  }

  /// How much more this process may take before the OS stops it, or null
  /// where the platform will not say (v29).
  ///
  /// 🚨On iOS this is the REAL ceiling — an app's allowance is neither the
  /// device's free RAM nor a fraction of its total, so a budget scaled
  /// from the machine can be double what the process is allowed to have.
  int? get availableMemoryBytes {
    final bytes = _availableMemoryBytes();
    return bytes <= 0 ? null : bytes;
  }

  /// What the OS lets THIS APP hold all in — held plus still available —
  /// or null where the OS gives an app no limit of its own (v36).
  ///
  /// ⛔Not [availableMemoryBytes] doubled up: on a desktop that one is the
  /// MACHINE's free memory, which is not a limit on this app at all. Only
  /// iOS answers here, and there it is the ceiling a jetsam decision is
  /// made against — the number the automatic allowance halves.
  int? get appMemoryLimitBytes {
    final bytes = _appMemoryLimitBytes();
    return bytes <= 0 ? null : bytes;
  }

  final int Function(
    Pointer<Uint8> rgb,
    int width,
    int height,
    int seedX,
    int seedY,
    int seedR,
    int seedG,
    int seedB,
    int tolerance,
    int gapPx,
    Pointer<Uint8> fillable,
    Pointer<Uint16> dist,
    Pointer<Uint8> filled,
    Pointer<Int32> stack,
    int stackCapacity,
    Pointer<Int32> bounds,
  )
  _fillGapCloseRun;

  // Grow-only work buffers for the close-gap fill (R20-C1).
  final _gapFillable = NativeScratch<Uint8>((n) => calloc<Uint8>(n));
  final _gapDist = NativeScratch<Uint16>(
    (n) => calloc<Uint16>(n),
    bytesPerElement: sizeOf<Uint16>(),
  );
  Pointer<Int32> _gapStack = nullptr;
  static const int _gapStackCapacity = 4 * 1024 * 1024;

  /// Runs the whole close-gap fill in C over the composed native raster
  /// (the caller composed EVERY tile first). Returns the filled bounds,
  /// `empty: true` when nothing fills, or null on kernel stack overflow —
  /// the caller then falls back to the Dart reference. The filled mask
  /// lands in the SAME engine buffer [finishFillMask] reads.
  ({int minX, int maxX, int minY, int maxY, bool empty})? gapCloseFillRun({
    required QaFloodNativeHandles handles,
    required int seedX,
    required int seedY,
    required int seedR,
    required int seedG,
    required int seedB,
    required int tolerance,
    required int gapClosePx,
  }) {
    final width = handles.width;
    final height = handles.height;
    final pixelCount = width * height;
    _floodFilled.ensure(pixelCount);
    _gapFillable.ensure(pixelCount);
    _gapDist.ensure(pixelCount);
    if (_gapStack == nullptr) {
      _gapStack = calloc<Int32>(_gapStackCapacity);
    }
    if (_floodStackSize == nullptr) {
      _floodStackSize = calloc<Int32>(1);
      _floodBounds = calloc<Int32>(4);
    }
    final gap = _fillGapCloseRun(
      _floodRgb.pointer,
      width,
      height,
      seedX,
      seedY,
      seedR,
      seedG,
      seedB,
      tolerance,
      gapClosePx,
      _gapFillable.pointer,
      _gapDist.pointer,
      _floodFilled.pointer,
      _gapStack,
      _gapStackCapacity,
      _floodBounds,
    );
    if (gap == -1) {
      return null;
    }
    if (gap == -2) {
      return (minX: 0, maxX: -1, minY: 0, maxY: -1, empty: true);
    }
    final bounds = _floodBounds.asTypedList(4);
    return (
      minX: bounds[0],
      maxX: bounds[1],
      minY: bounds[2],
      maxY: bounds[3],
      empty: false,
    );
  }

  /// Wave-parallel flood (R22-E3): same lazy-compose candidate protocol
  /// as the stepper, but the composed frontier floods per compose-tile
  /// across the worker pool. Returns -1 on an internal allocation/bound
  /// failure — the caller redoes the fill on the sequential Dart path
  /// from clean state.
  final int Function(
    Pointer<Uint8> rgb,
    Pointer<Uint8> filled,
    Pointer<Uint8> composed,
    int width,
    int height,
    int composeTileShift,
    int tilesX,
    int seedR,
    int seedG,
    int seedB,
    int tolerance,
    Pointer<Int32> stack,
    Pointer<Int32> stackSize,
    Pointer<Int32> candidates,
    int candidatesCapacity,
    Pointer<Int32> bounds,
  )
  _floodFillWave;

  final void Function(
    Pointer<Uint8> rgb,
    int rasterWidth,
    int paperR,
    int paperG,
    int paperB,
    Pointer<QaComposeTileItemStruct> items,
    int itemCount,
    Pointer<QaComposeBlendStruct> blends,
  )
  _fillComposeBatch;

  final void Function(
    Pointer<Uint8> rgb,
    int rasterWidth,
    int left,
    int top,
    int rightExclusive,
    int bottomExclusive,
    int paperR,
    int paperG,
    int paperB,
  )
  _fillPaperRect;

  final void Function(
    Pointer<Uint8> rgb,
    int rasterWidth,
    Pointer<Uint8> tilePixels,
    int tileSize,
    int baseX,
    int baseY,
    int clipLeft,
    int clipTop,
    int clipRightExclusive,
    int clipBottomExclusive,
    int opacityInt,
  )
  _fillComposeTile;

  final void Function(
    Pointer<Uint8> filled,
    int canvasWidth,
    int cropLeft,
    int cropTop,
    int regionWidth,
    int regionHeight,
    int expandPx,
    int antiAlias,
    Pointer<Uint8> mask,
    Pointer<Uint8> scratch,
  )
  _fillFinishMask;

  final void Function(
    Pointer<QaTileSpanStruct> tiles,
    int tileCount,
    int tileSize,
    Pointer<QaDabSpecStruct> specs,
    Pointer<Int32> clips,
    int dabCount,
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

  /// BB-N1 (ABI 22): whole-tile alpha bounds scan, 4 int32 per tile.
  /// Reference = the `bitmapSurfaceContentBounds` word loop.
  final void Function(
    Pointer<QaTileSpanStruct> tiles,
    int tileCount,
    int tileSize,
    Pointer<Int32> boundsOut,
  )
  _alphaBoundsTiles;

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

  final int Function(
    Pointer<Uint8> pixels,
    int tileWidth,
    int tileHeight,
    int backgroundRgba,
    Pointer<Int32> ops,
    int opWordCount,
    Pointer<Uint8> atlas,
    int atlasWidth,
    int atlasHeight,
  )
  _gridRasterTile;

  /// Grid tile raster (UI-R18 O7 T1): rasterizes one op stream into the
  /// native RGBA tile. Semantics = `timelineGridRasterTileReference`
  /// (byte parity pinned). Returns 0 ok / negative on a malformed
  /// stream.
  int gridRasterTile({
    required Pointer<Uint8> pixels,
    required int tileWidth,
    required int tileHeight,
    required int backgroundRgba,
    required Pointer<Int32> ops,
    required int opWordCount,
    Pointer<Uint8>? atlas,
    int atlasWidth = 0,
    int atlasHeight = 0,
  }) {
    return _gridRasterTile(
      pixels,
      tileWidth,
      tileHeight,
      backgroundRgba,
      ops,
      opWordCount,
      atlas ?? nullptr,
      atlasWidth,
      atlasHeight,
    );
  }

  final int Function(
    Pointer<Uint8> src,
    int srcWidth,
    int srcHeight,
    Pointer<Uint8> dst,
    int dstWidth,
    int dstHeight,
    Pointer<Double> inverse,
    double radiusFloor,
    int mode,
    int clipX,
    int clipY,
  )
  _resampleRgba;

  /// The shared image resampler (ABI 26). Semantics =
  /// `resampleRgbaReference` in
  /// `lib/src/services/resample/resample_kernel.dart`, byte parity pinned
  /// by `resample_parity_test.dart`.
  ///
  /// [inverse] is nine doubles, row-major, destination-to-source, with the
  /// homogeneous row last. [mode] is 0 for the tent mean and 1 for the
  /// coverage argmax. Returns 0, or negative on bad arguments.
  ///
  /// [clipX]/[clipY] say where this destination buffer sits inside the
  /// FULL output rect [inverse] was built for; 0/0 means it IS the rect.
  /// A window keeps the whole rect's pixel grid, which is what makes it
  /// bit-identical to that window of the whole.
  int resampleRgba({
    required Pointer<Uint8> src,
    required int srcWidth,
    required int srcHeight,
    required Pointer<Uint8> dst,
    required int dstWidth,
    required int dstHeight,
    required Pointer<Double> inverse,
    required double radiusFloor,
    required int mode,
    int clipX = 0,
    int clipY = 0,
  }) {
    return _resampleRgba(
      src,
      srcWidth,
      srcHeight,
      dst,
      dstWidth,
      dstHeight,
      inverse,
      radiusFloor,
      mode,
      clipX,
      clipY,
    );
  }

  /// [resampleRgba] for a caller that owns Dart buffers and runs on a hot
  /// path — the transform tool resamples on every drag frame, and its mesh
  /// mode calls this once per triangle.
  ///
  /// Nothing is allocated per call. The SOURCE goes through the
  /// identity-keyed [stampUploads] cache, which is exactly what it was
  /// built for: a transform session hands the same lift stamp in on every
  /// frame, so only the first one copies. The DESTINATION is a grow-only
  /// engine scratch — never the upload cache, because each resample mints a
  /// fresh result buffer and uploading those would evict the source it just
  /// read.
  ///
  /// Returns false when the kernel refuses the arguments, and the caller
  /// must then run the Dart reference: the scratch is not cleared on that
  /// path, so returning true after a non-zero status would ship whatever
  /// the previous resample left behind as pixels.
  bool resampleRgbaInto({
    required Uint8List src,
    required int srcWidth,
    required int srcHeight,
    required Uint8List dst,
    required int dstWidth,
    required int dstHeight,
    required Float64List inverse,
    required double radiusFloor,
    required int mode,
    int clipX = 0,
    int clipY = 0,
  }) {
    // Nine doubles or nothing. `setAll` under-fills in silence — it only
    // throws when the source is LONGER — so a short list would hand the
    // kernel whatever malloc last held as the homogeneous row.
    if (inverse.length != 9) {
      return false;
    }
    final byteLength = dstWidth * dstHeight * 4;
    if (byteLength <= 0 || dst.length < byteLength) {
      return false;
    }
    final source = stampUploads.upload(src);
    _resampleDst.ensure(byteLength);
    if (_resampleInverse == nullptr) {
      _resampleInverse = malloc<Double>(9);
    }
    _resampleInverse.asTypedList(9).setAll(0, inverse);
    final status = resampleRgba(
      src: source,
      srcWidth: srcWidth,
      srcHeight: srcHeight,
      dst: _resampleDst.pointer,
      dstWidth: dstWidth,
      dstHeight: dstHeight,
      inverse: _resampleInverse,
      radiusFloor: radiusFloor,
      mode: mode,
      clipX: clipX,
      clipY: clipY,
    );
    if (status != 0) {
      return false;
    }
    dst.setRange(0, byteLength, _resampleDst.pointer.asTypedList(byteLength));
    return true;
  }

  final _resampleDst = NativeScratch<Uint8>((n) => calloc<Uint8>(n));
  Pointer<Double> _resampleInverse = nullptr;

  /// Copy-in/copy-out convenience over [gridRasterTile] for callers (and
  /// the parity suite) that live in Dart lists.
  int gridRasterTileBytes({
    required Uint8List pixels,
    required int tileWidth,
    required int tileHeight,
    required int backgroundRgba,
    Int32List? ops,
    Uint8List? atlas,
    int atlasWidth = 0,
    int atlasHeight = 0,
  }) {
    final pixelsNative = malloc<Uint8>(pixels.length);
    final opsNative = ops == null || ops.isEmpty
        ? nullptr
        : malloc<Int32>(ops.length);
    final atlasNative = atlas == null || atlas.isEmpty
        ? nullptr
        : malloc<Uint8>(atlas.length);
    try {
      if (opsNative != nullptr) {
        opsNative.asTypedList(ops!.length).setAll(0, ops);
      }
      if (atlasNative != nullptr) {
        atlasNative.asTypedList(atlas!.length).setAll(0, atlas);
      }
      final result = gridRasterTile(
        pixels: pixelsNative,
        tileWidth: tileWidth,
        tileHeight: tileHeight,
        backgroundRgba: backgroundRgba,
        ops: opsNative,
        opWordCount: ops?.length ?? 0,
        atlas: atlasNative == nullptr ? null : atlasNative,
        atlasWidth: atlasWidth,
        atlasHeight: atlasHeight,
      );
      if (result == 0) {
        pixels.setAll(0, pixelsNative.asTypedList(pixels.length));
      }
      return result;
    } finally {
      malloc.free(pixelsNative);
      if (opsNative != nullptr) {
        malloc.free(opsNative);
      }
      if (atlasNative != nullptr) {
        malloc.free(atlasNative);
      }
    }
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
      final specSize = library
          .lookupFunction<Int32 Function(), int Function()>(
            'qa_dab_spec_sizeof',
          )
          .call();
      if (specSize != sizeOf<QaDabSpecStruct>()) {
        return null;
      }
      final spanSize = library
          .lookupFunction<Int32 Function(), int Function()>(
            'qa_tile_span_sizeof',
          )
          .call();
      if (spanSize != sizeOf<QaTileSpanStruct>()) {
        return null;
      }
      final celSpecSize = library
          .lookupFunction<Int32 Function(), int Function()>(
            'qa_cel_pixel_spec_sizeof',
          )
          .call();
      if (celSpecSize != sizeOf<QaCelPixelSpecStruct>()) {
        return null;
      }
      final premultiplyRgba = library
          .lookupFunction<
            Void Function(Pointer<Uint8>, Int32),
            void Function(Pointer<Uint8>, int)
          >('qa_premultiply_rgba');
      final fillPaperRect = library
          .lookupFunction<
            Void Function(
              Pointer<Uint8>,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
            ),
            void Function(
              Pointer<Uint8>,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
            )
          >('qa_fill_paper_rect');
      final fillComposeTile = library
          .lookupFunction<
            Void Function(
              Pointer<Uint8>,
              Int32,
              Pointer<Uint8>,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
            ),
            void Function(
              Pointer<Uint8>,
              int,
              Pointer<Uint8>,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
            )
          >('qa_fill_compose_tile');
      final fillFinishMask = library
          .lookupFunction<
            Void Function(
              Pointer<Uint8>,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Pointer<Uint8>,
              Pointer<Uint8>,
            ),
            void Function(
              Pointer<Uint8>,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
              Pointer<Uint8>,
              Pointer<Uint8>,
            )
          >('qa_fill_finish_mask');
      final dabBlendBatch = library
          .lookupFunction<
            Void Function(
              Pointer<QaTileSpanStruct>,
              Int32,
              Int32,
              Pointer<QaDabSpecStruct>,
              Pointer<Int32>,
              Int32,
              Pointer<Uint8>,
            ),
            void Function(
              Pointer<QaTileSpanStruct>,
              int,
              int,
              Pointer<QaDabSpecStruct>,
              Pointer<Int32>,
              int,
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
      final alphaBoundsTiles = library
          .lookupFunction<
            Void Function(
              Pointer<QaTileSpanStruct>,
              Int32,
              Int32,
              Pointer<Int32>,
            ),
            void Function(Pointer<QaTileSpanStruct>, int, int, Pointer<Int32>)
          >('qa_alpha_bounds_tiles');
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
      final copyBytes = library
          .lookupFunction<
            Void Function(Pointer<Uint8>, Pointer<Uint8>, Int64),
            void Function(Pointer<Uint8>, Pointer<Uint8>, int)
          >('qa_copy_bytes');
      final tileAlloc = library
          .lookupFunction<
            Pointer<Void> Function(Int64),
            Pointer<Void> Function(int)
          >('qa_tile_alloc');
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
      final physicalMemoryBytes = library
          .lookupFunction<Int64 Function(), int Function()>(
            'qa_physical_memory_bytes',
          );
      final processFootprintBytes = library
          .lookupFunction<Int64 Function(), int Function()>(
            'qa_process_footprint_bytes',
          );
      final availableMemoryBytes = library
          .lookupFunction<Int64 Function(), int Function()>(
            'qa_available_memory_bytes',
          );
      final appMemoryLimitBytes = library
          .lookupFunction<Int64 Function(), int Function()>(
            'qa_app_memory_limit_bytes',
          );
      final fillGapCloseRun = library
          .lookupFunction<
            Int32 Function(
              Pointer<Uint8>,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Pointer<Uint8>,
              Pointer<Uint16>,
              Pointer<Uint8>,
              Pointer<Int32>,
              Int32,
              Pointer<Int32>,
            ),
            int Function(
              Pointer<Uint8>,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
              Pointer<Uint8>,
              Pointer<Uint16>,
              Pointer<Uint8>,
              Pointer<Int32>,
              int,
              Pointer<Int32>,
            )
          >('qa_fill_gap_close_run');
      final floodFillWave = library
          .lookupFunction<
            Int32 Function(
              Pointer<Uint8>,
              Pointer<Uint8>,
              Pointer<Uint8>,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Int32,
              Pointer<Int32>,
              Pointer<Int32>,
              Pointer<Int32>,
              Int32,
              Pointer<Int32>,
            ),
            int Function(
              Pointer<Uint8>,
              Pointer<Uint8>,
              Pointer<Uint8>,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
              int,
              Pointer<Int32>,
              Pointer<Int32>,
              Pointer<Int32>,
              int,
              Pointer<Int32>,
            )
          >('qa_flood_fill_wave');
      final composeBlendSize = library
          .lookupFunction<Int32 Function(), int Function()>(
            'qa_compose_blend_sizeof',
          )
          .call();
      if (composeBlendSize != sizeOf<QaComposeBlendStruct>()) {
        return null;
      }
      final composeItemSize = library
          .lookupFunction<Int32 Function(), int Function()>(
            'qa_compose_tile_item_sizeof',
          )
          .call();
      if (composeItemSize != sizeOf<QaComposeTileItemStruct>()) {
        return null;
      }
      final fillComposeBatch = library
          .lookupFunction<
            Void Function(
              Pointer<Uint8>,
              Int32,
              Int32,
              Int32,
              Int32,
              Pointer<QaComposeTileItemStruct>,
              Int32,
              Pointer<QaComposeBlendStruct>,
            ),
            void Function(
              Pointer<Uint8>,
              int,
              int,
              int,
              int,
              Pointer<QaComposeTileItemStruct>,
              int,
              Pointer<QaComposeBlendStruct>,
            )
          >('qa_fill_compose_batch');
      final gridRasterTile = library
          .lookupFunction<
            Int32 Function(
              Pointer<Uint8>,
              Int32,
              Int32,
              Uint32,
              Pointer<Int32>,
              Int32,
              Pointer<Uint8>,
              Int32,
              Int32,
            ),
            int Function(
              Pointer<Uint8>,
              int,
              int,
              int,
              Pointer<Int32>,
              int,
              Pointer<Uint8>,
              int,
              int,
            )
          >('qa_grid_raster_tile');
      final resampleRgba = library
          .lookupFunction<
            Int32 Function(
              Pointer<Uint8>,
              Int32,
              Int32,
              Pointer<Uint8>,
              Int32,
              Int32,
              Pointer<Double>,
              Double,
              Int32,
              Int32,
              Int32,
            ),
            int Function(
              Pointer<Uint8>,
              int,
              int,
              Pointer<Uint8>,
              int,
              int,
              Pointer<Double>,
              double,
              int,
              int,
              int,
            )
          >('qa_resample_rgba');
      final celPixelPassTile = library
          .lookupFunction<
            Int32 Function(
              Pointer<Uint8>,
              Pointer<Uint8>,
              Pointer<Uint8>,
              Pointer<QaCelPixelSpecStruct>,
              Pointer<Uint8>,
              Int64,
              Pointer<Uint8>,
              Pointer<Int32>,
              Pointer<Int32>,
            ),
            int Function(
              Pointer<Uint8>,
              Pointer<Uint8>,
              Pointer<Uint8>,
              Pointer<QaCelPixelSpecStruct>,
              Pointer<Uint8>,
              int,
              Pointer<Uint8>,
              Pointer<Int32>,
              Pointer<Int32>,
            )
          >('qa_cel_pixel_pass_tile');
      return QaNativeEngine._(
        premultiplyRgba,
        fillPaperRect,
        fillComposeTile,
        fillFinishMask,
        dabBlendBatch,
        stampBlendTiles,
        strokeBlendTiles,
        alphaBoundsTiles,
        preBlendTiles,
        premultiplyRgbaCopy,
        copyBytes,
        tileAlloc,
        tileFree,
        tileFreePointer,
        tilePoolCachedBytes,
        tilePoolTrim,
        tilePoolSetByteCap,
        physicalMemoryBytes,
        processFootprintBytes,
        availableMemoryBytes,
        appMemoryLimitBytes,
        fillGapCloseRun,
        floodFillWave,
        fillComposeBatch,
        gridRasterTile,
        resampleRgba,
        celPixelPassTile,
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

  /// R23: straight-alpha stamp RGBA → PREMULTIPLIED bytes for the fill
  /// overlay image, through the fused C kernel (a 64MP Dart premultiply
  /// loop was seconds). The upload is the identity-cached stamp upload,
  /// so the commit's stamp blend right after reuses it for free. The
  /// returned scratch is FRESH (never aliased by a later call); free it
  /// once the image decode has consumed the view.
  QaStampScratch premultipliedStampCopy(Uint8List rgba) {
    final source = stampUploads.upload(rgba);
    final buffer = malloc<Uint8>(rgba.length);
    _premultiplyRgbaCopy(buffer, source, rgba.length ~/ 4);
    return QaStampScratch._(buffer.asTypedList(rgba.length), buffer);
  }

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

  // -------------------------------------------------------------------
  // Flood fill (R18 A-2b): engine-persistent, grow-only buffers. ONE
  // fill runs at a time (a fill tap is synchronous and single-shot), so
  // the lazy raster and the stepper share these across calls.

  final _floodRgb = NativeScratch<Uint8>((n) => calloc<Uint8>(n));
  final _floodComposed = NativeScratch<Uint8>((n) => calloc<Uint8>(n));
  final _floodFilled = NativeScratch<Uint8>((n) => calloc<Uint8>(n));
  final _floodStack = NativeScratch<Int32>(
    (n) => calloc<Int32>(n),
    bytesPerElement: sizeOf<Int32>(),
  );
  final _floodCandidates = NativeScratch<Int32>(
    (n) => calloc<Int32>(n),
    bytesPerElement: sizeOf<Int32>(),
  );
  Pointer<Int32> _floodStackSize = nullptr;
  Pointer<Int32> _floodBounds = nullptr;

  /// Acquires the shared lazy-raster buffers for one fill:
  /// [QaFloodNativeHandles.rgbView] (`width*height*4` RGBX — R22-D; the
  /// X byte is 0 in every composed pixel, and only composed tiles are
  /// ever read) and [QaFloodNativeHandles.composedView] (one byte per
  /// compose tile, zeroed here). [composeTileSize] must be a power of
  /// two.
  QaFloodNativeHandles acquireFloodRaster({
    required int width,
    required int height,
    required int composeTileSize,
  }) {
    assert(
      composeTileSize > 0 && (composeTileSize & (composeTileSize - 1)) == 0,
      'composeTileSize must be a power of two',
    );
    final shift = composeTileSize.bitLength - 1;
    final tilesX = (width + composeTileSize - 1) ~/ composeTileSize;
    final tilesY = (height + composeTileSize - 1) ~/ composeTileSize;

    final rgbLength = width * height * 4;
    _floodRgb.ensure(rgbLength);
    final composedLength = tilesX * tilesY;
    _floodComposed.ensure(composedLength);
    final composedView = _floodComposed.pointer.asTypedList(composedLength);
    composedView.fillRange(0, composedLength, 0);

    return QaFloodNativeHandles._(
      rgbView: _floodRgb.pointer.asTypedList(rgbLength),
      composedView: composedView,
      width: width,
      height: height,
      tilesX: tilesX,
      composeTileShift: shift,
    );
  }

  /// Frees the fill arenas when the rgb arena exceeds [keepBytes] — an
  /// extended (pasteboard) fill grows them ~9× and they are high-water
  /// pinned otherwise; the next canvas fill re-allocs at canvas size.
  void trimFloodRasterArena({required int keepBytes}) {
    if (_floodRgb.length <= keepBytes) {
      return;
    }
    _floodRgb.release();
    _floodFilled.release();
    _gapFillable.release();
    _floodComposed.release();
  }

  /// Fills a rect of the native fill raster with the paper color
  /// (A-2c) — identical to the Dart paper loop.
  void fillPaperRect({
    required QaFloodNativeHandles handles,
    required int left,
    required int top,
    required int rightExclusive,
    required int bottomExclusive,
    required int paperR,
    required int paperG,
    required int paperB,
  }) {
    _fillPaperRect(
      _floodRgb.pointer,
      handles.width,
      left,
      top,
      rightExclusive,
      bottomExclusive,
      paperR,
      paperG,
      paperB,
    );
  }

  /// Integer source-over of one surface-tile clip onto the native fill
  /// raster (A-2c) — byte-identical to the Dart compose loop. Reads the
  /// tile's NATIVE pixels directly (R20-E1: tiles are native-backed since
  /// R19-Z, so the old per-tile staging copy was pure waste).
  void fillComposeTile({
    required QaFloodNativeHandles handles,
    required Pointer<Uint8> tilePixels,
    required int tileSize,
    required int baseX,
    required int baseY,
    required int clipLeft,
    required int clipTop,
    required int clipRightExclusive,
    required int clipBottomExclusive,
    required int opacityInt,
  }) {
    _fillComposeTile(
      _floodRgb.pointer,
      handles.width,
      tilePixels,
      tileSize,
      baseX,
      baseY,
      clipLeft,
      clipTop,
      clipRightExclusive,
      clipBottomExclusive,
      opacityInt,
    );
  }

  /// Runs the whole native flood from the (already composed, already
  /// filled-marked) seed: the wave-parallel engine (R22-E3) floods the
  /// composed frontier per compose-tile across the worker pool, the
  /// driver composes candidate tiles through [ensureComposed], re-tests
  /// candidates (filled dedupes) and re-enters until nothing is
  /// pending. Returns the filled mask as a view over engine memory
  /// (valid until the next fill) plus the bounds — result set identical
  /// to the Dart reference by construction (parity-pinned). Null on an
  /// internal wave failure (allocation/bound belt): the caller redoes
  /// the fill on the Dart path from clean state.
  ({Uint8List filled, int minX, int maxX, int minY, int maxY})? floodFillRun({
    required QaFloodNativeHandles handles,
    required int seedX,
    required int seedY,
    required int seedR,
    required int seedG,
    required int seedB,
    required int tolerance,
    required void Function(int index) ensureComposed,
    void Function(Int32List pixelIndices)? ensureComposedBatch,
  }) {
    final width = handles.width;
    final height = handles.height;
    final pixelCount = width * height;

    _floodFilled.ensure(pixelCount);
    final filledView = _floodFilled.pointer.asTypedList(pixelCount);
    filledView.fillRange(0, pixelCount, 0);

    // ⚠️The stack grows in JUMPS, not to the ask: a fill that needs one
    // more row would otherwise re-allocate on every call.
    if (_floodStack.length < width + 4096) {
      _floodStack.ensure(width * 4 + 65536);
    }

    // The wave engine can surface a whole composed-region perimeter of
    // crossings in ONE call — capacity is the total tile-edge pixel
    // count, which caps per-call emissions by construction (a pixel
    // fills once; only edge pixels emit).
    final tileSize = 1 << handles.composeTileShift;
    final tilesY = (height + tileSize - 1) >> handles.composeTileShift;
    var candidatesCapacity = 8 * width + 2048;
    final waveCapacity = handles.tilesX * tilesY * 4 * tileSize;
    if (waveCapacity > candidatesCapacity) {
      candidatesCapacity = waveCapacity;
    }
    _floodCandidates.ensure(candidatesCapacity);
    if (_floodStackSize == nullptr) {
      _floodStackSize = calloc<Int32>(1);
      _floodBounds = calloc<Int32>(4);
    }

    final seedIndex = seedY * width + seedX;
    filledView[seedIndex] = 255;
    _floodStack.pointer.value = seedIndex;
    _floodStackSize.value = 1;
    final bounds = _floodBounds.asTypedList(4);
    bounds[0] = seedX;
    bounds[1] = seedX;
    bounds[2] = seedY;
    bounds[3] = seedY;

    final rgbView = handles.rgbView;
    final composedView = handles.composedView;
    while (true) {
      final candidateCount = _floodFillWave(
        _floodRgb.pointer,
        _floodFilled.pointer,
        _floodComposed.pointer,
        width,
        height,
        handles.composeTileShift,
        handles.tilesX,
        seedR,
        seedG,
        seedB,
        tolerance,
        _floodStack.pointer,
        _floodStackSize,
        _floodCandidates.pointer,
        _floodCandidates.length,
        _floodBounds,
      );
      if (candidateCount < 0) {
        // Wave arena failure (belt; the bounds make it unreachable in
        // practice) — the caller redoes the fill on the Dart path.
        return null;
      }
      if (candidateCount > 0) {
        final candidates = _floodCandidates.pointer.asTypedList(candidateCount);
        // R25-③: one pooled compose for the whole candidate round
        // (per-candidate serial FFI compose was the fill's largest
        // remaining serial slice).
        if (ensureComposedBatch != null) {
          ensureComposedBatch(candidates);
        } else {
          for (var i = 0; i < candidateCount; i += 1) {
            ensureComposed(candidates[i]);
          }
        }
        var stackSize = _floodStackSize.value;
        for (var i = 0; i < candidateCount; i += 1) {
          final index = candidates[i];
          if (filledView[index] != 0) {
            continue;
          }
          final tile =
              ((index ~/ width) >> handles.composeTileShift) * handles.tilesX +
              ((index % width) >> handles.composeTileShift);
          if (composedView[tile] == 0) {
            // The callback failed its contract; a silent retry would spin
            // forever, so fail loudly.
            throw StateError(
              'floodFillRun: ensureComposed left tile $tile uncomposed',
            );
          }
          if (rgbWithinTolerance(
            rgbView,
            index * 4,
            seedR,
            seedG,
            seedB,
            tolerance,
          )) {
            filledView[index] = 255;
            if (stackSize >= _floodStack.length) {
              _growFloodStack(stackSize);
            }
            _floodStack.pointer.asTypedList(_floodStack.length)[stackSize] =
                index;
            stackSize += 1;
          }
        }
        _floodStackSize.value = stackSize;
        continue;
      }
      if (_floodStackSize.value == 0) {
        break;
      }
      // No candidates but work remains: the stack headroom guard tripped.
      _growFloodStack(_floodStackSize.value);
    }

    return (
      filled: filledView,
      minX: bounds[0],
      maxX: bounds[1],
      minY: bounds[2],
      maxY: bounds[3],
    );
  }

  /// Grow-only region scratches for [finishFillMask]'s double buffer.
  final _maskScratchA = NativeScratch<Uint8>((n) => calloc<Uint8>(n));
  final _maskScratchB = NativeScratch<Uint8>((n) => calloc<Uint8>(n));

  /// Crop + expand + anti-alias over the native flood mask (A-2d) —
  /// byte-identical to the Dart tail. Returns a fresh heap mask the
  /// caller owns.
  Uint8List finishFillMask({
    required int canvasWidth,
    required int cropLeft,
    required int cropTop,
    required int regionWidth,
    required int regionHeight,
    required int expandPx,
    required bool antiAlias,
  }) {
    final regionLength = regionWidth * regionHeight;
    _maskScratchA.ensure(regionLength);
    _maskScratchB.ensure(regionLength);
    _fillFinishMask(
      _floodFilled.pointer,
      canvasWidth,
      cropLeft,
      cropTop,
      regionWidth,
      regionHeight,
      expandPx,
      antiAlias ? 1 : 0,
      _maskScratchA.pointer,
      _maskScratchB.pointer,
    );
    return Uint8List.fromList(_maskScratchA.pointer.asTypedList(regionLength));
  }

  void _growFloodStack(int liveEntries) {
    _floodStack.grow(
      _floodStack.length * 2,
      keep: liveEntries,
      copy: (from, to, elements) => to
          .asTypedList(elements)
          .setRange(0, elements, from.asTypedList(elements)),
    );
  }

  /// Persistent grow-only scratch for [premultiplyRgba]'s round trip.
  final _premultiplyScratch = NativeScratch<Uint8>((n) => calloc<Uint8>(n));

  /// Premultiplies [pixels] (straight-alpha RGBA) IN PLACE through the
  /// native kernel — byte-identical to the Dart reference (Skia
  /// mul-div-255 rounding). Two memcpys through a persistent scratch
  /// replace the 65k-iteration Dart loop per tile (A-2a).
  void premultiplyRgba(Uint8List pixels) {
    _ensurePremultiplyScratch(pixels.length);
    final view = _premultiplyScratch.pointer.asTypedList(pixels.length);
    view.setAll(0, pixels);
    _premultiplyRgba(_premultiplyScratch.pointer, pixels.length ~/ 4);
    pixels.setAll(0, view);
  }

  void _ensurePremultiplyScratch(int length) {
    _premultiplyScratch.ensure(length);
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
  /// a time. Returns the per-tile changed flags (valid until the next
  /// batch).
  Uint8List dabBlendBatch({
    required int tileCount,
    required int dabCount,
    required int tileSize,
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

  /// Grow-only out buffer for [alphaBoundsTiles] (4 int32 per tile).
  Pointer<Int32> _alphaBoundsOut = nullptr;
  int _alphaBoundsCapacity = 0;

  /// BB-N1: scans every staged tile's ink bounds in ONE pooled call.
  /// Returns 4 int32 per tile — minX, minY, maxX, maxY in TILE-LOCAL
  /// pixels (empty tile: minX=0x7fffffff / maxX=-0x7fffffff). Only the
  /// span's tilePixels is consumed; the scan is whole-tile. The view is
  /// valid until the next call.
  Int32List alphaBoundsTiles({required int count, required int tileSize}) {
    if (_alphaBoundsCapacity < count * 4) {
      if (_alphaBoundsOut != nullptr) {
        calloc.free(_alphaBoundsOut);
      }
      _alphaBoundsOut = calloc<Int32>(count * 4);
      _alphaBoundsCapacity = count * 4;
    }
    _alphaBoundsTiles(_tileSpans.pointer, count, tileSize, _alphaBoundsOut);
    return _alphaBoundsOut.asTypedList(count * 4);
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
      view.fillRange(0, byteLength, 0);
    }
    return QaNativeTileBuffer._(pointer, view);
  }

  void releaseTileBuffer(QaNativeTileBuffer buffer) {
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

  // ABI 34 — the cel pixel pass (색 변환 / 픽셀 비우기), one tile per call.
  final int Function(
    Pointer<Uint8> inPixels,
    Pointer<Uint8> outPixels,
    Pointer<Uint8> mask,
    Pointer<QaCelPixelSpecStruct> spec,
    Pointer<Uint8> incoming,
    int startIndex,
    Pointer<Uint8> runValuesOut,
    Pointer<Int32> runLengthsOut,
    Pointer<Int32> countsOut,
  )
  _celPixelPassTile;
  final Pointer<QaCelPixelSpecStruct> _celSpec;
  final Pointer<Int32> _celCounts;
  final _celIncoming = NativeScratch<Uint8>((n) => calloc<Uint8>(n));
  final _celMask = NativeScratch<Uint8>((n) => calloc<Uint8>(n));
  final _celRunValues = NativeScratch<Uint8>((n) => calloc<Uint8>(n));
  final _celRunLengths = NativeScratch<Int32>(
    (n) => calloc<Int32>(n),
    bytesPerElement: sizeOf<Int32>(),
  );

  /// Stages the per-PASS constants of a cel pixel pass — see
  /// [CelPixelStage].
  ///
  /// ⛔Called once per pass, never per tile: everything here is the same
  /// for every tile, and the tile call is the one in the loop.
  void stageCelPixelPass(CelPixelStage stage) {
    final selector = stage.selector;
    _celSpec.ref
      ..byteCount = stage.byteCount
      ..byteOffsetBase = stage.byteOffsetBase
      ..byteOffsetStride = stage.byteOffsetStride
      ..takesEmptyPixels = stage.takesEmptyPixels ? 1 : 0
      ..hasSelector = selector == null ? 0 : 1
      ..selectorRed = selector?.red ?? 0
      ..selectorGreen = selector?.green ?? 0
      ..selectorBlue = selector?.blue ?? 0
      ..selectorTolerance = selector?.tolerance ?? 0
      ..selectorKeepsMatches = (selector?.keepsMatches ?? false) ? 1 : 0
      ..isUndo = stage.isUndo ? 1 : 0
      ..tileSize = stage.tileSize
      ..incomingCount = stage.incomingCount
      ..incomingStep = stage.incomingStep;
    final incoming = stage.incoming;
    final staged = _celIncoming.ensure(incoming.isEmpty ? 1 : incoming.length);
    staged.asTypedList(incoming.length).setAll(0, incoming);
  }

  /// Hands the staged stream back once a pass is over.
  ///
  /// ⚠️An undo can stage its whole recipe laid flat — megabytes on a
  /// full-canvas pass — and a grow-only scratch would hold that for the rest
  /// of the session. Forward stages one value; releasing that too costs one
  /// tiny allocation next pass and keeps the rule unconditional.
  void finishCelPixelPass() => _celIncoming.release();

  /// Runs the staged pass over ONE tile.
  ///
  /// [inPixels] is the tile's own bytes (from `BitmapTile.readPixels`) and
  /// is never written. The result's `pixels` is a [tileAlloc] block holding
  /// the rewritten tile when anything changed — ready for
  /// `BitmapTile.adoptNative`, no copy — and null when nothing did, in which
  /// case the block has already gone back to the pool. With [wantRuns] the
  /// tile's originals come back as runs (views into scratch, valid until
  /// the next call); an undo builds no recipe and wants none.
  ({
    Pointer<Uint8>? pixels,
    int count,
    Uint8List? runValues,
    Int32List? runLengths,
  })
  celPixelPassTile({
    required Pointer<Uint8> inPixels,
    required Uint8List? mask,
    required int startIndex,
    required bool wantRuns,
  }) {
    final spec = _celSpec.ref;
    final pixelCount = spec.tileSize * spec.tileSize;
    final out = tileAlloc(pixelCount * 4);
    Pointer<Uint8> maskPointer = nullptr;
    if (mask != null) {
      maskPointer = _celMask.ensure(pixelCount);
      maskPointer.asTypedList(pixelCount).setAll(0, mask);
    }
    final runValues = wantRuns
        ? _celRunValues.ensure(pixelCount * spec.byteCount)
        : nullptr;
    final runLengths = wantRuns ? _celRunLengths.ensure(pixelCount) : nullptr;
    final changed = _celPixelPassTile(
      inPixels,
      out,
      maskPointer,
      _celSpec,
      _celIncoming.pointer,
      startIndex,
      runValues,
      runLengths,
      _celCounts,
    );
    final count = _celCounts[0];
    final runs = _celCounts[1];
    if (changed != 1) {
      tileFree(out);
    }
    if (changed < 0) {
      throw StateError(
        'the recipe holds ${spec.incomingCount} pixels and the walk it '
        'replays goes past them — it was built over some other surface',
      );
    }
    return (
      pixels: changed == 0 ? null : out,
      count: count,
      runValues: wantRuns ? runValues.asTypedList(runs * spec.byteCount) : null,
      runLengths: wantRuns ? runLengths.asTypedList(runs) : null,
    );
  }

  /// Uploaded mask alphas keyed by the SOURCE Float64List's identity
  /// (BrushTipMask.alphaNormalized is `late final`, so the identity is
  /// stable for a mask's lifetime). Small LRU — one stroke reuses the
  /// same two or three masks for every dab.
  final _maskUploads = NativeUploadCache<Float64List>(
    entryCap: 8,
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
  void beginDabBatch(int dabCount) {
    _dabSpecs.ensure(dabCount);
    _dabClips.ensure(dabCount * 4);
    _arenaChunk = 0;
    _arenaOffset = 0;
  }

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
    required double hardRadius,
    required double edgeSpan,
    required double minorRadius,
    required double tipCos,
    required double tipSin,
    required double inverseRoundness,
    required double dabOpacity,
    required double dabFlow,
    required double sourceAlphaNorm,
    required double radiusSqSkip,
    required double dualDensity,
    required double dualOneMinusDensity,
    required int dualCompositeMode,
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
    Float64List? dualAlpha,
    int dualSize = 0,
    Int32List? dualUTexel0,
    Int32List? dualUTexel1,
    Float64List? dualUFraction,
    Float64List? dualUOneMinus,
    Int32List? dualVTexel0,
    Int32List? dualVTexel1,
    Float64List? dualVFraction,
    Float64List? dualVOneMinus,
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
    spec.hardRadius = hardRadius;
    spec.edgeSpan = edgeSpan;
    spec.minorRadius = minorRadius;
    spec.tipCos = tipCos;
    spec.tipSin = tipSin;
    spec.inverseRoundness = inverseRoundness;
    spec.dabOpacity = dabOpacity;
    spec.dabFlow = dabFlow;
    spec.sourceAlphaNorm = sourceAlphaNorm;
    spec.radiusSqSkip = radiusSqSkip;
    spec.dualDensity = dualDensity;
    spec.dualOneMinusDensity = dualOneMinusDensity;
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
    spec.dualSize = dualSize;
    spec.texSize = texSize;
    spec.dualCompositeMode = dualCompositeMode;
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
    spec.dualAlpha = dualAlpha == null
        ? nullptr
        : _maskUploads.upload(dualAlpha).cast<Double>();
    spec.dualUTexel0 = dualUTexel0 == null ? nullptr : _arenaInt32(dualUTexel0);
    spec.dualUTexel1 = dualUTexel1 == null ? nullptr : _arenaInt32(dualUTexel1);
    spec.dualUFraction = dualUFraction == null
        ? nullptr
        : _arenaFloat64(dualUFraction);
    spec.dualUOneMinus = dualUOneMinus == null
        ? nullptr
        : _arenaFloat64(dualUOneMinus);
    spec.dualVTexel0 = dualVTexel0 == null ? nullptr : _arenaInt32(dualVTexel0);
    spec.dualVTexel1 = dualVTexel1 == null ? nullptr : _arenaInt32(dualVTexel1);
    spec.dualVFraction = dualVFraction == null
        ? nullptr
        : _arenaFloat64(dualVFraction);
    spec.dualVOneMinus = dualVOneMinus == null
        ? nullptr
        : _arenaFloat64(dualVOneMinus);
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
  }
}

/// A pooled native tile buffer: the raw pointer for the kernel and a
/// typed-data view over the SAME memory for Dart-side reads/writes.
class QaNativeTileBuffer {
  QaNativeTileBuffer._(this.pointer, this.view);

  final Pointer<Uint8> pointer;
  final Uint8List view;
}

/// Mirror of the C `qa_compose_blend` (R25-③) — field order/types must
/// match EXACTLY (sizeof cross-checked before the native path enables).
final class QaComposeBlendStruct extends Struct {
  external Pointer<Uint8> tilePixels;
  @Int32()
  external int tileSize;
  @Int32()
  external int baseX;
  @Int32()
  external int baseY;
  @Int32()
  external int clipLeft;
  @Int32()
  external int clipTop;
  @Int32()
  external int clipRightExclusive;
  @Int32()
  external int clipBottomExclusive;
  @Int32()
  external int opacityInt;
  @Int32()
  external int reserved;
}

/// Mirror of the C `qa_compose_tile_item` (R25-③).
final class QaComposeTileItemStruct extends Struct {
  @Int32()
  external int tileLeft;
  @Int32()
  external int tileTop;
  @Int32()
  external int tileRightExclusive;
  @Int32()
  external int tileBottomExclusive;
  @Int32()
  external int firstBlend;
  @Int32()
  external int blendCount;
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

/// The lazy fill raster's shared native buffers (R18 A-2b): the raster
/// composes pixels into [rgbView] and marks compose tiles in
/// [composedView]; the C flood stepper reads both through the SAME
/// memory. Valid for one fill (the engine reuses the buffers on the next
/// [QaNativeEngine.acquireFloodRaster]).
class QaFloodNativeHandles {
  QaFloodNativeHandles._({
    required this.rgbView,
    required this.composedView,
    required this.width,
    required this.height,
    required this.tilesX,
    required this.composeTileShift,
  });

  /// `width*height*3` straight-RGB bytes; only composed tiles are ever
  /// read, so uncomposed regions may hold stale bytes.
  final Uint8List rgbView;

  /// One byte per compose tile (row-major, `tilesX` wide): nonzero once
  /// the raster composed that tile. Zeroed at acquire.
  final Uint8List composedView;

  final int width;
  final int height;
  final int tilesX;
  final int composeTileShift;
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
  external double hardRadius;
  @Double()
  external double edgeSpan;
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

  /// v32: how hard the DUAL mask bites, after [aaContrast] and still last of
  /// the doubles. ⚠️THE ORDER OF THIS BLOCK IS THE ABI — `qa_dab_spec_sizeof`
  /// is what catches a slip.
  @Double()
  external double dualDensity;
  @Double()
  external double dualOneMinusDensity;
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
  external int dualSize;
  @Int32()
  external int texSize;

  /// How the DUAL mask combines with the coverage under it — a
  /// `QA_STROKE_BLEND_*` id, the same contract `strokeBlendModeNativeId`
  /// speaks. Took the `reserved` slot in v33, so the layout did not move.
  @Int32()
  external int dualCompositeMode;
  external Pointer<Double> tipAlpha;
  external Pointer<Int32> tipUTexel0;
  external Pointer<Double> tipUFraction;
  external Pointer<Double> tipUOneMinus;
  external Pointer<Uint8> tipUInRange;
  external Pointer<Int32> tipVTexel0;
  external Pointer<Double> tipVFraction;
  external Pointer<Double> tipVOneMinus;
  external Pointer<Uint8> tipVInRange;
  external Pointer<Double> dualAlpha;
  external Pointer<Int32> dualUTexel0;
  external Pointer<Int32> dualUTexel1;
  external Pointer<Double> dualUFraction;
  external Pointer<Double> dualUOneMinus;
  external Pointer<Int32> dualVTexel0;
  external Pointer<Int32> dualVTexel1;
  external Pointer<Double> dualVFraction;
  external Pointer<Double> dualVOneMinus;
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
}

/// Mirror of the C `qa_cel_pixel_spec` (ABI 34) — field order/types must
/// match EXACTLY; the loader cross-checks `qa_cel_pixel_spec_sizeof`.
///
/// Eleven int32s and nothing else, so there is no padding to get wrong:
/// the whole struct is the cel pixel pass's per-PASS constants, staged once
/// and read by every tile.
final class QaCelPixelSpecStruct extends Struct {
  /// 3 for colour, 1 for alpha — `CelPixelChannel.byteCount`.
  @Int32()
  external int byteCount;

  /// Channel byte i sits at `base + i * stride` in the RGBA quad —
  /// `CelPixelChannel.byteOffset` asked twice, so the C never has to know
  /// what a channel IS.
  @Int32()
  external int byteOffsetBase;
  @Int32()
  external int byteOffsetStride;

  /// 1 = every masked pixel takes part — `CelPixelChannel.takesEmptyPixels`.
  @Int32()
  external int takesEmptyPixels;

  /// The `CelColorKey`, or `hasSelector == 0`.
  @Int32()
  external int hasSelector;
  @Int32()
  external int selectorRed;
  @Int32()
  external int selectorGreen;
  @Int32()
  external int selectorBlue;
  @Int32()
  external int selectorTolerance;
  @Int32()
  external int selectorKeepsMatches;

  /// 1 = undo: the incoming stream is the recipe, indexed by walk position.
  @Int32()
  external int isUndo;

  /// Pixels per tile side — one number for every tile of a pass.
  @Int32()
  external int tileSize;

  /// Undo only: how many entries the stream holds, and how far apart they
  /// sit — `byteCount` for a recipe laid flat, 0 for a uniform one, which is
  /// never laid out at all.
  @Int32()
  external int incomingCount;
  @Int32()
  external int incomingStep;
}

/// The per-PASS constants of a cel pixel pass (ABI 34), handed to
/// [QaNativeEngine.stageCelPixelPass] once before the tile calls.
///
/// Plain numbers rather than `CelPixelChannel` and `CelColorKey`: the
/// service owns those laws and reads them into these, so neither this
/// adapter nor the C ever has to know what a channel or a key IS.
final class CelPixelStage {
  const CelPixelStage({
    required this.byteCount,
    required this.byteOffsetBase,
    required this.byteOffsetStride,
    required this.takesEmptyPixels,
    required this.tileSize,
    required this.isUndo,
    required this.incoming,
    required this.incomingCount,
    required this.incomingStep,
    this.selector,
  });

  final int byteCount;
  final int byteOffsetBase;
  final int byteOffsetStride;
  final bool takesEmptyPixels;
  final int tileSize;

  /// Undo: [incoming] is the recipe, [incomingCount] entries read
  /// [incomingStep] bytes apart — 0 for a uniform recipe, one value for
  /// every pixel. Forward: [incoming] is the new value and the two counts
  /// are not read.
  final bool isUndo;
  final Uint8List incoming;
  final int incomingCount;
  final int incomingStep;

  /// The colour key, or null for the verbs that take every pixel.
  final ({int red, int green, int blue, int tolerance, bool keepsMatches})?
  selector;
}
