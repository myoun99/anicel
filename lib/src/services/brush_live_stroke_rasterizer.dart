import 'dart:ffi' show Pointer, Uint8;
import 'dart:collection';

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../core/floor_math.dart';
import '../core/rgba_premultiply.dart';
import '../core/sync_image_upload.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/brush_blend_mode.dart';
import '../models/brush_dab.dart';
import '../models/canvas_size.dart';
import '../models/dirty_region.dart';
import '../models/pasteboard_bounds.dart';
import '../models/tile_coord.dart';
import '../native/qa_native_engine.dart';
import 'brush_dab_kernel.dart';
import 'canvas_selection_region.dart';
import 'brush_stroke_blend.dart'
    show
        bitmapSurfaceRegionPixels,
        preBlendStrokeOverlayPixels,
        strokeBlendModeNativeId,
        strokeCoverageMask,
        strokeOpacityCoverage;

/// The premultiplied form of a pre-blended tile made on demand, with the
/// release that goes with it (a native scratch, or nothing).
typedef _PremultipliedTile = ({Uint8List view, void Function() free});

/// A pre-blended overlay tile — the bytes the door ([pictureOf]) turns
/// into the coordinate's picture — and the stroke [revision] they were
/// blended at (pen-up hands the picture of a matching revision straight to
/// the adopted tile — a stale one would pin wrong pixels forever, so the
/// number travels with it).
///
/// Reads STRAIGHT from the resident result as it stands (the door's Skia
/// road), and PREMULTIPLIED from the scratch the batch kernel already
/// wrote — fused into the blend, no extra pass — or, on the routes that
/// have no such scratch, from a premultiply made only when asked (the
/// door's Impeller road). Either way the engine's form is made once and
/// the other never.
class PreBlendedOverlayTile implements PictureBytes {
  PreBlendedOverlayTile._fused(
    this._straight,
    this.size,
    this.revision,
    QaStampScratch scratch,
  ) : _scratch = scratch,
      _premultiplyNow = null;

  PreBlendedOverlayTile._lazy(
    this._straight,
    this.size,
    this.revision,
    _PremultipliedTile Function() premultiplyNow,
  ) : _scratch = null,
      _premultiplyNow = premultiplyNow;

  /// The resident straight result — a view onto the rasterizer's own
  /// buffer, valid until the next blend at this coordinate.
  final Uint8List _straight;
  final int size;
  final int revision;
  final QaStampScratch? _scratch;
  final _PremultipliedTile Function()? _premultiplyNow;

  @override
  int get width => size;

  @override
  int get height => size;

  @override
  T readStraight<T>(T Function(Uint8List straight) use) => use(_straight);

  @override
  T readPremultiplied<T>(T Function(Uint8List premultiplied) use) {
    final fused = _scratch;
    if (fused != null) {
      return use(fused.view);
    }
    final made = _premultiplyNow!();
    try {
      return use(made.view);
    } finally {
      made.free();
    }
  }

  /// Releases the fused native scratch, read or not (the door reads it on
  /// Impeller only); a no-op on the routes that premultiply on demand.
  void free() => _scratch?.free();
}

/// A finished stroke tile handed to the cel surface, with the stroke
/// [revision] its pixels represent.
class PromotedStrokeTile {
  PromotedStrokeTile(this.coord, this.tile, this.revision);

  /// WHERE this tile goes. It is the map key the commit will store it
  /// under, carried beside the tile instead of read back off it — the
  /// coordinate is a fact about the SURFACE, not about the pixels.
  final TileCoord coord;

  final BitmapTile tile;
  final int revision;
}

/// One tile's selection coverage (R28): 1 byte per pixel on the stroke
/// grid, built once per stroke.
///
/// [allInside] / [allOutside] are the two cases worth special-casing —
/// a tile deep inside the selection needs no mask at all (and takes the
/// kernel's byte-identical null path), and one entirely outside needs no
/// blend at all.
class _MaskTile {
  _MaskTile({
    required this.buffer,
    required this.bytes,
    required this.allInside,
    required this.allOutside,
  });

  final QaNativeTileBuffer? buffer;
  final Uint8List bytes;
  final bool allInside;
  final bool allOutside;
}

/// One resident pre-blended result: straight-alpha bytes (native-backed
/// when the engine is loaded), the stroke revision they cover, and
/// whether they differ from the base at all.
class _ResultTile {
  _ResultTile({
    required this.native,
    required this.bytes,
    required this.revision,
    required this.changed,
  });

  final QaNativeTileBuffer? native;
  final Uint8List bytes;
  final int revision;
  final bool changed;
}

/// Read access to the in-progress stroke's straight-alpha pixels — what
/// the live overlay snapshots its tile images from.
abstract interface class ActiveStrokePixelSource {
  int get canvasWidth;
  int get canvasHeight;

  /// Copies [count] straight-alpha RGBA pixels starting at canvas (x, y)
  /// into [target] at [targetOffset]. Unpainted pixels read as transparent
  /// zeros.
  void copyRow(int x, int y, int count, Uint8List target, int targetOffset);
}

/// Rasterizes the in-progress stroke incrementally into SPARSE
/// straight-alpha RGBA tiles allocated on demand.
///
/// Storage is tile-sparse so the cost of a stroke scales with the region
/// it actually paints, never with the canvas: the old canvas-sized buffer
/// made big logical surfaces (the timesheet ink planes at high resolution)
/// pay tens/hundreds of MB per stroke.
///
/// This runs the exact blend math of the commit rasterizer
/// (`materializeBrushDabSequenceOnBitmapSurface`) — same coverage sampling of
/// pixel centers against the true fractional dab center, same floating-point
/// grouping, same rounding — so the pixels painted while drawing are
/// byte-identical to the committed result. The live display and the commit
/// fast-path both consume these pixels, which is what unifies the on-screen
/// stroke with the committed artwork. Equivalence with the commit rasterizer
/// is locked by `active_stroke_overlay_parity_test.dart` (byte-exact).
class BrushLiveStrokeRasterizer implements ActiveStrokePixelSource {
  BrushLiveStrokeRasterizer({
    required this.canvasSize,
    this.tileSize = defaultTileSize,
  });

  /// Edge length of a sparse stroke tile in canvas pixels when the caller
  /// states none — the committed surface's own default.
  static const int defaultTileSize = defaultCelTileSize;

  /// Edge length of a sparse stroke tile in canvas pixels.
  ///
  /// PROMOTION round: the interactive view sets this to the CEL surface's
  /// tile size, so a stroke tile, its pre-blended result tile and the
  /// committed tile at the same coordinate are ONE grid — the display
  /// replaces per coordinate (no clips, no isolation layer) and pen-up
  /// ADOPTS the result buffers as the committed tiles outright. (The old
  /// fixed 128 bounded the per-move upload a little tighter, but forced
  /// quadrant bookkeeping everywhere the two grids met.)
  final int tileSize;

  final CanvasSize canvasSize;

  @override
  int get canvasWidth => canvasSize.width;

  @override
  int get canvasHeight => canvasSize.height;

  /// Straight-alpha RGBA tile buffers keyed by `tileY * tilesPerRow +
  /// tileX`, allocated (zeroed) the first time a dab touches the tile.
  ///
  /// R21: with the engine loaded the buffers are NATIVE-backed (the map
  /// holds asTypedList views; [_nativeBuffers] the raw pointers) and the
  /// per-dab blend fans through the SAME C kernel as the commit — a
  /// 1000px dab is ~1M pixels, and the pure-Dart loop below was the
  /// reported big-brush stall on the UI thread. Dart stays the reference
  /// and the fallback; the kernel is parity-pinned byte-for-byte.
  final Map<int, Uint8List> _tiles = <int, Uint8List>{};
  final Map<int, QaNativeTileBuffer> _nativeBuffers =
      <int, QaNativeTileBuffer>{};
  final QaNativeEngine? _native = QaNativeEngine.instance;

  /// Tile coordinate per linear key — the promotion pass walks the
  /// touched tiles and needs their coordinates back.
  final Map<int, TileCoord> _tileCoords = <int, TileCoord>{};

  /// R28 selection: strokes land only inside this region. Set before the
  /// first dab and never changed mid-stroke — the selection layer is not
  /// even mounted while a painting tool is active, which is what makes
  /// the per-tile mask cache below valid for the stroke's whole life.
  ///
  /// The mask reaches the KERNEL (it scales the accumulated stroke's
  /// alpha), so the pre-blended result equals the base wherever the
  /// selection excludes it — which is what lets the overlay keep
  /// replacing whole coordinates instead of falling back to a clip.
  CanvasSelectionRegion? selectionRegion;

  /// 🚨★F-12 — the stroke's opacity CEILING, in the same channel and by the
  /// same route as the selection above, because it is the same kind of
  /// thing: **a mask with no shape.**
  ///
  /// Opacity cannot ride the dabs. Dabs accumulate source-over, so a
  /// per-dab factor is not a ceiling — overlap it enough and any factor
  /// below 1 still converges on opaque, which is the report (「불투명도
  /// 낮춰도 dab 겹치면 100%까지 진해진다」). It has to scale the ACCUMULATED
  /// stroke, once, which is precisely what this mask already does.
  ///
  /// Folding it in here rather than adding a scalar to the kernel is what
  /// keeps the native and Dart routes parity-pinned for free: neither one
  /// learns a new input. Like the region it is set before the first dab and
  /// never changes mid-stroke, which is what keeps the per-tile cache valid
  /// for the stroke's whole life.
  double strokeOpacity = 1;

  /// Lazily built stroke coverage per tile (see [_maskTileFor]).
  final Map<int, _MaskTile> _maskTiles = <int, _MaskTile>{};

  /// The ceiling's own mask when there is no selection to fold it into.
  ///
  /// ONE tile for the whole stroke rather than one per coordinate: with no
  /// selection every tile's coverage is the same constant, so a per-tile
  /// copy would cost 64KB (+ a native buffer) per touched tile to hold
  /// identical bytes. Read-only for the kernel's whole life, which is what
  /// makes sharing it safe.
  _MaskTile? _uniformMask;

  /// How many times a dab has touched each tile. A RESULT tile
  /// ([_results]) blended at revision R is current only while the stroke
  /// tile still reads R; anything else must re-blend before it can be
  /// displayed or promoted. (Conservative: a dab that writes no pixel
  /// still bumps, costing at most one redundant re-blend.)
  final Map<int, int> _tileRevisions = <int, int>{};

  /// Resident PRE-BLENDED result tiles (base ⊕ stroke, straight alpha) in
  /// insertion/refresh order — the exact bytes the commit holds at that
  /// coordinate, kept alive so pen-up can ADOPT them instead of blending
  /// the whole stroke a second time.
  final LinkedHashMap<int, _ResultTile> _results =
      LinkedHashMap<int, _ResultTile>();
  int _resultBytes = 0;

  /// Resident-result byte budget (the round's one real cost: while a
  /// stroke runs, a touched coordinate holds its stroke tile AND its
  /// result tile). Past it the LEAST RECENTLY blended results drop —
  /// they are behind the brush, and pen-up re-blends exactly those. The
  /// frontier (what the user is watching) always stays resident.
  ///
  /// 96MB ≈ 384 tiles at 256px: a full-screen scribble keeps its whole
  /// visible neighbourhood, an 8K canvas-covering stroke degrades to
  /// "re-blend the part you left behind" instead of holding 512MB.
  ///
  /// The memory tab's allowance scales it ([CacheBudgets.liveStroke]) —
  /// a production knob now, no longer one for tests alone.
  static int residentResultByteBudget = defaultResidentResultByteBudget;

  /// [residentResultByteBudget] at the automatic allowance — the memory
  /// tab scales it ([CacheBudgets.liveStroke]).
  static const int defaultResidentResultByteBudget = 96 * 1024 * 1024;

  // The linear key grid spans the PASTEBOARD (strokes reach one canvas
  // size past every edge), offset so keys stay non-negative.
  late final int _tileXMin = canvasSize.pasteboardTileXMin(tileSize);
  late final int _tileYMin = canvasSize.pasteboardTileYMin(tileSize);
  late final int _tilesPerRow =
      canvasSize.pasteboardTileXEndExclusive(tileSize) - _tileXMin;

  int _tileKey(int tileX, int tileY) =>
      (tileY - _tileYMin) * _tilesPerRow + (tileX - _tileXMin);

  DirtyRegion? _strokeBounds;
  int _blendedDabCount = 0;

  /// Union of every blended dab's dirty region, or `null` when nothing has
  /// been painted yet.
  DirtyRegion? get strokeBounds => _strokeBounds;

  /// Number of dabs blended so far.
  int get blendedDabCount => _blendedDabCount;

  /// Number of allocated stroke tiles (test/debug oracle for sparseness).
  int get allocatedTileCount => _tiles.length;

  /// Drops the stroke's tiles so the rasterizer can host the next stroke
  /// (native buffers return to the engine's free list).
  void clear() {
    final native = _native;
    if (native != null) {
      for (final buffer in _nativeBuffers.values) {
        native.releaseTileBuffer(buffer);
      }
      for (final result in _results.values) {
        final buffer = result.native;
        if (buffer != null) {
          native.releaseTileBuffer(buffer);
        }
      }
      for (final mask in _maskTiles.values) {
        final buffer = mask.buffer;
        if (buffer != null) {
          native.releaseTileBuffer(buffer);
        }
      }
      final uniform = _uniformMask?.buffer;
      if (uniform != null) {
        native.releaseTileBuffer(uniform);
      }
    }
    _nativeBuffers.clear();
    _tiles.clear();
    _tileCoords.clear();
    _tileRevisions.clear();
    _maskTiles.clear();
    _uniformMask = null;
    _results.clear();
    _resultBytes = 0;
    _strokeBounds = null;
    _blendedDabCount = 0;
  }

  /// Resident result tiles (test/debug oracle for the memory budget).
  @visibleForTesting
  int get residentResultTileCount => _results.length;

  /// R25: the overlay's FUSED display path. Overlay tiles are the same
  /// 128px grid as the stroke tiles, so a full tile's snapshot +
  /// premultiply collapses into ONE C call over the native buffer (the
  /// per-move Dart row-copy + pixel loop across ~256 tiles was the
  /// 2000px-brush stall and the visible pre-stroke tiles). Null when
  /// the tile is untouched (transparent — caller's copyRow path reads
  /// zeros) or the engine/native backing is absent.
  QaStampScratch? premultipliedOverlayTile(int tileX, int tileY) {
    final native = _native;
    if (native == null) {
      return null;
    }
    final buffer = _nativeBuffers[_tileKey(tileX, tileY)];
    if (buffer == null) {
      return null;
    }
    return native.premultipliedTileScratch(buffer.pointer, tileSize * tileSize);
  }

  /// Pre-blends the stroke tile at ([tileX], [tileY]) against [base]
  /// through the COMMIT'S OWN KERNELS and returns the premultiplied
  /// upload for display — while the STRAIGHT result stays resident, so
  /// pen-up promotes it into the surface instead of blending the whole
  /// stroke a second time.
  ///
  /// Native route: stage the base rect, blend in place (stamp srcOver /
  /// stamp erase / stroke-blend — exactly the calls the commit makes),
  /// premultiply in C; the stroke tile is already a native pointer, so
  /// nothing uploads. Dart route (no engine, or a Dart-buffer stroke
  /// tile): the same math through [preBlendStrokeOverlayPixels]. Both
  /// are parity-pinned to each other and to the commit.
  ///
  /// Null when the tile is untouched (nothing to show there: the base
  /// tile the painter already draws IS the result).
  PreBlendedOverlayTile? preBlendedOverlayTile({
    required int tileX,
    required int tileY,
    required BitmapSurface base,
    required BrushBlendMode mode,
    required bool erase,
  }) {
    return preBlendedOverlayTiles(
      coords: [TileCoord(x: tileX, y: tileY)],
      base: base,
      mode: mode,
      erase: erase,
    )[0];
  }

  /// The BATCH pre-blend (ABI 24): every [coords] tile staged, blended
  /// and premultiplied in ONE pooled call.
  ///
  /// This is the frame's shape — a pointer move touches a whole
  /// neighbourhood of tiles at once — and it is why the batch exists.
  /// The per-tile sequence it replaces made two count=1 kernel calls per
  /// tile, and a one-item batch runs INLINE (the worker pool never
  /// engages), on top of a base row-copy in the VM. Measured on a debug
  /// build at 256px tiles: ~2ms per tile, so a 1000px brush spent 34ms of
  /// every frame here and an 1800px brush 122ms.
  ///
  /// Entries are null where the tile has nothing to show: untouched by
  /// the stroke, or entirely outside the selection.
  List<PreBlendedOverlayTile?> preBlendedOverlayTiles({
    required List<TileCoord> coords,
    required BitmapSurface base,
    required BrushBlendMode mode,
    required bool erase,
  }) {
    final results = List<PreBlendedOverlayTile?>.filled(coords.length, null);
    final native = _native;
    // Tiles this batch will actually blend, paired with their slot.
    final staged = <({int slot, int key, TileCoord coord, _MaskTile? mask})>[];
    for (var slot = 0; slot < coords.length; slot += 1) {
      final coord = coords[slot];
      final key = _tileKey(coord.x, coord.y);
      if (!_tiles.containsKey(key)) {
        continue;
      }
      final mask = _maskTileFor(key, coord);
      if (mask != null && mask.allOutside) {
        // The selection excludes this coordinate completely: the result
        // would equal the base, so there is nothing to show or promote.
        continue;
      }
      staged.add((slot: slot, key: key, coord: coord, mask: mask));
    }
    if (staged.isEmpty) {
      return results;
    }

    // The kernel stages the base from ONE tile pointer per span, so it
    // needs the grids to agree — which they always do in the app. A host
    // with its own overlay grid falls to the Dart route below, where
    // staging walks whatever base tiles overlap the rect.
    if (native != null &&
        _nativeBuffers.isNotEmpty &&
        base.tileSize == tileSize) {
      final byteLength = tileSize * tileSize * 4;
      final blends =
          <
            ({
              int slot,
              int key,
              QaNativeTileBuffer buffer,
              int revision,
              bool isNew,
              QaStampScratch scratch,
            })
          >[];
      native.ensureTileSpanBatch(staged.length);
      var spanCount = 0;
      for (final entry in staged) {
        final strokeNative = _nativeBuffers[entry.key];
        final revision = _tileRevisions[entry.key] ?? 0;
        final existing = _results[entry.key];
        if (strokeNative == null) {
          // A Dart-buffer tile inside a native rasterizer: cannot happen
          // in practice, but fall back rather than mis-stage a span.
          results[entry.slot] = _preBlendTileInDart(
            key: entry.key,
            coord: entry.coord,
            base: base,
            mode: mode,
            erase: erase,
            mask: entry.mask,
          );
          continue;
        }
        if (existing != null && existing.revision == revision) {
          // Already current: the resident result stands, and its
          // premultiplied form is made only if the door asks for it.
          _results.remove(entry.key);
          _results[entry.key] = existing;
          if (!existing.changed) {
            continue; // Equal to the base: nothing to show (see below).
          }
          final buffer = existing.native;
          results[entry.slot] = PreBlendedOverlayTile._lazy(
            existing.bytes,
            tileSize,
            revision,
            buffer != null
                ? () {
                    final scratch = native.premultipliedTileScratch(
                      buffer.pointer,
                      tileSize * tileSize,
                    );
                    return (view: scratch.view, free: scratch.free);
                  }
                : () => (
                    view: premultipliedRgbaCopy(existing.bytes),
                    free: _nothing,
                  ),
          );
          continue;
        }
        final reused = existing?.native;
        final stagedBuffer =
            reused ?? native.acquireTileBuffer(byteLength, zeroed: false);
        final scratch = native.acquireScratch(byteLength);
        final tileLeft = entry.coord.x * tileSize;
        final tileTop = entry.coord.y * tileSize;
        native.setTileSpan(
          spanCount,
          tilePixels: stagedBuffer.pointer,
          tileLeft: tileLeft,
          tileTop: tileTop,
          spanLeft: tileLeft,
          spanRightExclusive: tileLeft + tileSize,
          spanTop: tileTop,
          spanBottomExclusive: tileTop + tileSize,
          basePixels: _baseTilePointerFor(base, tileLeft, tileTop),
          strokePixels: strokeNative.pointer,
          maskPixels: entry.mask?.buffer?.pointer,
          premulOut: scratch.pointer,
        );
        spanCount += 1;
        blends.add((
          slot: entry.slot,
          key: entry.key,
          buffer: stagedBuffer,
          revision: revision,
          isNew: reused == null,
          scratch: scratch,
        ));
      }
      if (spanCount > 0) {
        final changed = native.preBlendTiles(
          count: spanCount,
          tileSize: tileSize,
          kind: _preBlendKindFor(mode: mode, erase: erase),
          mode: _preBlendModeFor(mode),
        );
        for (var i = 0; i < blends.length; i += 1) {
          final entry = blends[i];
          final touched = changed[i] != 0;
          _storeResult(
            entry.key,
            _ResultTile(
              native: entry.buffer,
              bytes: entry.buffer.view,
              revision: entry.revision,
              changed: touched,
            ),
            byteLength,
            isNew: entry.isNew,
          );
          if (!touched) {
            // The result equals the base — every stroke pixel here was
            // masked away, or landed on nothing. Uploading it would draw
            // the committed tile a second time, so there is nothing to
            // show. (The result stays resident: it is already current,
            // and pen-up skips it for the same reason.)
            entry.scratch.free();
            continue;
          }
          results[entry.slot] = PreBlendedOverlayTile._fused(
            entry.buffer.view,
            tileSize,
            entry.revision,
            entry.scratch,
          );
        }
      }
      // Base tiles were read by the kernel through raw pointers: this use
      // is what kept them reachable across the call.
      _baseKeepAlive.clear();
      return results;
    }

    for (final entry in staged) {
      results[entry.slot] = _preBlendTileInDart(
        key: entry.key,
        coord: entry.coord,
        base: base,
        mode: mode,
        erase: erase,
        mask: entry.mask,
      );
    }
    return results;
  }

  static void _nothing() {}

  /// Which composite the stroke lands with — the eraser and the plain
  /// colour brush ride the stamp kernels, everything else the brush
  /// blend (exactly the split the commit makes).
  static int _preBlendKindFor({
    required BrushBlendMode mode,
    required bool erase,
  }) {
    if (erase || mode == BrushBlendMode.erase) {
      return QaNativeEngine.preBlendKindErase;
    }
    if (mode == BrushBlendMode.color) {
      return QaNativeEngine.preBlendKindSrcOver;
    }
    return QaNativeEngine.preBlendKindStroke;
  }

  static int _preBlendModeFor(BrushBlendMode mode) =>
      mode == BrushBlendMode.color || mode == BrushBlendMode.erase
      ? 0
      : strokeBlendModeNativeId(mode);

  /// The Dart route: same math, same bytes, no engine.
  PreBlendedOverlayTile? _preBlendTileInDart({
    required int key,
    required TileCoord coord,
    required BitmapSurface base,
    required BrushBlendMode mode,
    required bool erase,
    required _MaskTile? mask,
  }) {
    final result = _blendResultTile(
      key: key,
      tileX: coord.x,
      tileY: coord.y,
      base: base,
      mode: mode,
      erase: erase,
      mask: mask,
    );
    if (!result.changed) {
      return null; // Equal to the base: the committed tile already shows it.
    }
    return PreBlendedOverlayTile._lazy(
      result.bytes,
      tileSize,
      result.revision,
      () => (view: premultipliedRgbaCopy(result.bytes), free: _nothing),
    );
  }

  /// The base tile covering the aligned rect at ([left], [top]), as a raw
  /// pointer for the kernel — null when the coordinate is empty (the
  /// kernel then stages transparency) or when the grids differ, which
  /// sends the caller down the Dart staging path instead.
  final List<BitmapTile> _baseKeepAlive = <BitmapTile>[];

  Pointer<Uint8>? _baseTilePointerFor(BitmapSurface base, int left, int top) {
    if (base.tileSize != tileSize) {
      return null;
    }
    final tile = base.tileAt(
      TileCoord(x: floorDiv(left, tileSize), y: floorDiv(top, tileSize)),
    );
    if (tile == null) {
      return null;
    }
    // The pointer outlives this call (the kernel reads it), so the TILE
    // has to stay reachable until the batch returns — see
    // BitmapTile.readPixels.
    _baseKeepAlive.add(tile);
    return tile.readPixels((pointer, _) => pointer);
  }

  /// The stroke coverage for a tile — the selection folded with the
  /// opacity ceiling — built once per stroke.
  ///
  /// Null = nothing to mask (full opacity and either no selection or a
  /// tile lying entirely inside it — the kernel's null-mask path is
  /// byte-identical to no mask at all). Neither input can change
  /// mid-stroke: the selection layer is not even mounted while a painting
  /// tool is active and the ceiling is fixed at pen-down, so one build per
  /// tile lasts the stroke.
  _MaskTile? _maskTileFor(int key, TileCoord coord) {
    final region = selectionRegion;
    if (region == null) {
      if (strokeOpacityCoverage(strokeOpacity) >= 255) {
        return null;
      }
      return _uniformMask ??= _buildMaskTile(
        strokeCoverageMask(
          pixelCount: tileSize * tileSize,
          opacity: strokeOpacity,
        )!,
      );
    }
    final cached = _maskTiles[key];
    if (cached != null) {
      return cached.allInside ? null : cached;
    }
    final bytes = strokeCoverageMask(
      selection: region.maskFor(
        left: coord.x * tileSize,
        top: coord.y * tileSize,
        width: tileSize,
        height: tileSize,
      ),
      pixelCount: tileSize * tileSize,
      opacity: strokeOpacity,
    )!;
    final mask = _buildMaskTile(bytes);
    _maskTiles[key] = mask;
    return mask.allInside ? null : mask;
  }

  _MaskTile _buildMaskTile(Uint8List bytes) {
    var allInside = true;
    var allOutside = true;
    for (final coverage in bytes) {
      if (coverage != 255) {
        allInside = false;
      }
      if (coverage != 0) {
        allOutside = false;
      }
      if (!allInside && !allOutside) {
        break;
      }
    }
    final native = _native;
    QaNativeTileBuffer? buffer;
    if (native != null && !allInside && !allOutside) {
      buffer = native.acquireTileBuffer(tileSize * tileSize, zeroed: false);
      buffer.view.setAll(0, bytes);
    }
    return _MaskTile(
      buffer: buffer,
      bytes: bytes,
      allInside: allInside,
      allOutside: allOutside,
    );
  }

  /// (Re)computes the resident RESULT tile for [key] — base bytes staged
  /// fresh, then the stroke blended in place. The blend is not
  /// incremental by design: its input is always (original base,
  /// accumulated stroke), which is what makes a promoted tile impossible
  /// to double-apply — re-running it over its own output is never a
  /// state the pipeline can reach.
  _ResultTile _blendResultTile({
    required int key,
    required int tileX,
    required int tileY,
    required BitmapSurface base,
    required BrushBlendMode mode,
    required bool erase,
    _MaskTile? mask,
  }) {
    final revision = _tileRevisions[key] ?? 0;
    final existing = _results[key];
    if (existing != null && existing.revision == revision) {
      // Refreshed by use: the frontier keeps its results, the tail drops
      // first when the budget bites.
      _results.remove(key);
      _results[key] = existing;
      return existing;
    }
    final tileLeft = tileX * tileSize;
    final tileTop = tileY * tileSize;
    final byteLength = tileSize * tileSize * 4;
    final native = _native;
    final strokeNative = _nativeBuffers[key];
    // The kernel stages the base itself, which needs the grids to agree.
    // They always do in the app (the view configures this rasterizer from
    // the cel surface); a host with its own grid takes the Dart route
    // below, which walks whatever base tiles overlap.
    if (native != null && strokeNative != null && base.tileSize == tileSize) {
      final staged =
          existing?.native ??
          native.acquireTileBuffer(byteLength, zeroed: false);
      native.ensureTileSpanBatch(1);
      native.setTileSpan(
        0,
        tilePixels: staged.pointer,
        tileLeft: tileLeft,
        tileTop: tileTop,
        spanLeft: tileLeft,
        spanRightExclusive: tileLeft + tileSize,
        spanTop: tileTop,
        spanBottomExclusive: tileTop + tileSize,
        basePixels: _baseTilePointerFor(base, tileLeft, tileTop),
        strokePixels: strokeNative.pointer,
        maskPixels: mask?.buffer?.pointer,
      );
      final changed = native.preBlendTiles(
        count: 1,
        tileSize: tileSize,
        kind: _preBlendKindFor(mode: mode, erase: erase),
        mode: _preBlendModeFor(mode),
      );
      _baseKeepAlive.clear();
      final result = _ResultTile(
        native: staged,
        bytes: staged.view,
        revision: revision,
        changed: changed[0] != 0,
      );
      _storeResult(key, result, byteLength, isNew: existing == null);
      return result;
    }
    // Dart route: the same kernels, in Dart. The straight result is a
    // fresh buffer each time (the reference blend is functional), so the
    // resident entry simply swaps.
    // The straight result is a fresh buffer each time, which is exactly
    // what the region gather returns — the base's bytes for this tile
    // rect, with missing base tiles left as zeros. The base grid is the
    // surface's own tile size; a stroke tile can overlap up to four base
    // tiles when the two grids differ, and the walk handles that.
    final staged = bitmapSurfaceRegionPixels(
      base,
      DirtyRegion(
        left: tileLeft,
        top: tileTop,
        rightExclusive: tileLeft + tileSize,
        bottomExclusive: tileTop + tileSize,
      ),
    );
    final blended = preBlendStrokeOverlayPixels(
      dst: staged,
      src: _tiles[key]!,
      mode: mode,
      erase: erase,
      pixelCount: tileSize * tileSize,
      mask: mask?.bytes,
    );
    var changed = false;
    for (var offset = 0; offset < byteLength; offset += 1) {
      if (blended[offset] != staged[offset]) {
        changed = true;
        break;
      }
    }
    final result = _ResultTile(
      native: null,
      bytes: blended,
      revision: revision,
      changed: changed,
    );
    _storeResult(key, result, byteLength, isNew: existing == null);
    return result;
  }

  void _storeResult(
    int key,
    _ResultTile result,
    int byteLength, {
    required bool isNew,
  }) {
    _results.remove(key);
    _results[key] = result;
    if (isNew) {
      _resultBytes += byteLength;
    }
    // Budget: drop the LEAST recently blended results (the ones the brush
    // has moved past). Their coordinates simply re-blend at pen-up — the
    // stroke tiles and the base are both still here, so nothing is lost
    // but the work.
    while (_resultBytes > residentResultByteBudget && _results.length > 1) {
      final oldestKey = _results.keys.first;
      if (oldestKey == key) {
        break;
      }
      final dropped = _results.remove(oldestKey)!;
      final buffer = dropped.native;
      if (buffer != null) {
        _native?.releaseTileBuffer(buffer);
      }
      _resultBytes -= byteLength;
    }
  }

  /// The finished tiles of this stroke, ready to be ADOPTED by the cel
  /// surface — the pen-up commit in one move.
  ///
  /// Every touched coordinate whose resident result is stale (dropped by
  /// the budget, or touched after its last blend) re-blends here; a
  /// coordinate whose result is byte-identical to the base is left out
  /// entirely, so the dirty set stays the TRUE change set and untouched
  /// tiles keep their identity (and their decoded image).
  ///
  /// Ownership of the returned tiles' pixels leaves this rasterizer, so
  /// this may be called ONCE per stroke; [clear] afterwards releases only
  /// what stayed behind.
  List<PromotedStrokeTile> promoteStrokeTiles({
    required BitmapSurface base,
    required BrushBlendMode mode,
    required bool erase,
  }) {
    assert(
      base.tileSize == tileSize,
      'promotion requires the stroke grid to be the surface grid',
    );
    final promoted = <PromotedStrokeTile>[];
    final byteLength = tileSize * tileSize * 4;
    for (final key in _tiles.keys.toList()) {
      final coord = _tileCoords[key]!;
      final mask = _maskTileFor(key, coord);
      if (mask != null && mask.allOutside) {
        // The selection excludes this coordinate: the stroke contributes
        // nothing there, so the committed tile must stay as it is.
        continue;
      }
      final result = _blendResultTile(
        key: key,
        tileX: coord.x,
        tileY: coord.y,
        base: base,
        mode: mode,
        erase: erase,
        mask: mask,
      );
      if (!result.changed) {
        continue;
      }
      final buffer = result.native;
      final tile = buffer != null
          ? BitmapTile.adoptNative(
              size: tileSize,
              pixels: buffer.pointer,
            )
          : BitmapTile(size: tileSize, pixels: result.bytes);
      if (buffer != null) {
        // Adopted: the tile's finalizer owns the block now.
        _results.remove(key);
        _resultBytes -= byteLength;
      }
      promoted.add(PromotedStrokeTile(coord, tile, result.revision));
    }
    return promoted;
  }

  Uint8List _tileBuffer(int tileX, int tileY) {
    final key = _tileKey(tileX, tileY);
    // A dab is about to write here: the coordinate's resident result (if
    // any) is now stale. Over-bumping is safe — the counter is only ever
    // compared for equality, and a redundant re-blend costs one tile.
    _tileRevisions[key] = (_tileRevisions[key] ?? 0) + 1;
    return _tiles.putIfAbsent(key, () {
      _tileCoords[key] = TileCoord(x: tileX, y: tileY);
      final native = _native;
      if (native != null) {
        final buffer = native.acquireTileBuffer(
          tileSize * tileSize * 4,
          zeroed: true,
        );
        _nativeBuffers[key] = buffer;
        return buffer.view;
      }
      return Uint8List(tileSize * tileSize * 4);
    });
  }

  @override
  void copyRow(int x, int y, int count, Uint8List target, int targetOffset) {
    var remaining = count;
    var sourceX = x;
    var writeOffset = targetOffset;
    final tileY = floorDiv(y, tileSize);
    final localRowOffset = (y - tileY * tileSize) * tileSize;
    while (remaining > 0) {
      final tileX = floorDiv(sourceX, tileSize);
      final tileLeft = tileX * tileSize;
      final spanCount = math.min(remaining, tileLeft + tileSize - sourceX);
      final buffer = _tiles[_tileKey(tileX, tileY)];
      if (buffer == null) {
        target.fillRange(writeOffset, writeOffset + spanCount * 4, 0);
      } else {
        final sourceOffset = (localRowOffset + (sourceX - tileLeft)) * 4;
        target.setRange(
          writeOffset,
          writeOffset + spanCount * 4,
          buffer,
          sourceOffset,
        );
      }
      remaining -= spanCount;
      sourceX += spanCount;
      writeOffset += spanCount * 4;
    }
  }

  /// Materializes the stroke's pixels within [strokeBounds] as one
  /// row-major straight-alpha buffer (stride = bounds width) — the pen-up
  /// commit fast path's input. Allocation scales with the STROKE, not the
  /// canvas.
  Uint8List? strokePixelsWithinBounds() {
    final bounds = _strokeBounds;
    if (bounds == null) {
      return null;
    }
    final boundsWidth = bounds.rightExclusive - bounds.left;
    final boundsHeight = bounds.bottomExclusive - bounds.top;
    final buffer = Uint8List(boundsWidth * boundsHeight * 4);
    for (var row = 0; row < boundsHeight; row += 1) {
      copyRow(
        bounds.left,
        bounds.top + row,
        boundsWidth,
        buffer,
        row * boundsWidth * 4,
      );
    }
    return buffer;
  }

  /// Blends `dabs[from..]` into the stroke tiles and returns the union of
  /// the newly touched region (clamped to the canvas), or `null` if nothing
  /// changed.
  DirtyRegion? blendFrom(List<BrushDab> dabs, {int? from}) {
    final start = from ?? _blendedDabCount;
    DirtyRegion? touched;

    for (var index = start; index < dabs.length; index += 1) {
      final region = _blendDab(dabs[index]);
      if (region != null) {
        touched = touched == null ? region : touched.union(region);
      }
    }
    _blendedDabCount = math.max(_blendedDabCount, dabs.length);
    if (touched != null) {
      _strokeBounds = _strokeBounds == null
          ? touched
          : _strokeBounds!.union(touched);
    }
    return touched;
  }

  DirtyRegion? _blendDab(BrushDab dab) {
    // Stamp dabs never reach the LIVE rasterizer: they only enter through
    // programmatic commits (fill, lift, paste, the stroke-blend landing),
    // which call the materializer directly and route stamps to the
    // dedicated 1:1 blend. There is no live stamp path, so refuse rather
    // than fall through — the tip kernel would paint the dab's flat
    // COLOUR where the stamp's bitmap belongs, and the overlay would show
    // a solid blob until pen-up corrected it.
    if (dab.stamp != null) {
      assert(false, 'the live rasterizer has no stamp path');
      return null;
    }

    // ONE dab kernel (see brush_dab_kernel.dart) — the same hoists,
    // lattices and clip the commit resolves. erase is false always: the
    // live overlay never carries the erase flag, because erase strokes
    // composite at display time.
    final plan = BrushDabPlan.of(
      dab,
      canvasSize: canvasSize,
      tileSize: tileSize,
      erase: false,
    );
    if (plan == null) {
      return null;
    }

    // R21: the C kernel runs the live blend exactly like the commit —
    // same spec, same lattices, srcOver only. Byte-identical to the Dart
    // loop below (parity-pinned).
    final native = _native;
    if (native != null) {
      blendDabTilesNative(
        plan,
        native,
        tileSize: tileSize,
        pointerFor: (coord) {
          // _tileBuffer also bumps the tile revision, which is what marks
          // a resident pre-blend result stale.
          _tileBuffer(coord.x, coord.y);
          return _nativeBuffers[_tileKey(coord.x, coord.y)]!.pointer;
        },
      );
      return DirtyRegion(
        left: plan.left,
        top: plan.top,
        rightExclusive: plan.rightExclusive,
        bottomExclusive: plan.bottomExclusive,
      );
    }

    // No engine: the Dart reference blend, the same one the commit falls
    // back to. _tileBuffer creates the tile and bumps its revision, which
    // is exactly what the old inline loop did per (row, tile).
    blendDabTilesDart(plan, tileSize: tileSize, bufferFor: _tileBuffer);

    return DirtyRegion(
      left: plan.left,
      top: plan.top,
      rightExclusive: plan.rightExclusive,
      bottomExclusive: plan.bottomExclusive,
    );
  }
}
