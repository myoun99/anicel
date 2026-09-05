import 'dart:math' as math;
import 'dart:typed_data';

import '../core/floor_math.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/brush_blend_mode.dart';
import '../models/brush_dab.dart';
import '../models/brush_dab_sequence.dart';
import '../models/brush_stamp_image.dart';
import '../models/brush_tip_shape.dart';
import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/dirty_region.dart';
import '../models/dirty_tile_set.dart';
import '../models/pasteboard_bounds.dart';
import '../models/tile_coord.dart';
import '../native/qa_native_engine.dart';
import '../core/dev_profile.dart';
import 'brush_dab_kernel.dart';
import 'brush_stroke_blend.dart';

class BrushSurfaceMaterialization {
  const BrushSurfaceMaterialization({
    required this.surface,
    required this.dirtyTiles,
  });

  final BitmapSurface surface;
  final DirtyTileSet dirtyTiles;

  bool get hasChanges => dirtyTiles.isNotEmpty;
}

/// Rasterizes [sequence] onto [surface] and returns the updated surface plus
/// the tiles it changed.
///
/// This is the stroke-commit hot path. It blends dabs directly into per-tile
/// scratch byte buffers: each touched tile's pixels are copied at most once,
/// and no per-pixel objects are allocated. The blend math is kept identical to
/// the reference pixel pipeline (`brushPixelBlendOperationsForDabSequence` +
/// `applyBrushPixelBlendOperationsToBitmapTile`), which remains as the slow
/// per-pixel-operation oracle used by the parity test.
BrushSurfaceMaterialization materializeBrushDabSequenceOnBitmapSurface({
  required BitmapSurface surface,
  required BrushDabSequence sequence,
}) {
  // Strokes clip at the PASTEBOARD (canvas + one canvas size in every
  // direction), not the canvas — drawing off the stage is the point.
  // Composite/export raster at canvas size, which crops for free. The
  // clip itself lives in BrushDabPlan, so both raster routes take it.
  final canvasSize = surface.canvasSize;
  final tileSize = surface.tileSize;
  final tileByteLength = tileSize * tileSize * BitmapTile.bytesPerPixel;

  // Mutable scratch pixels per touched tile. `BitmapTile.pixels` already
  // returns a defensive copy, so it can be mutated freely; blank tiles start
  // as zeroed buffers without allocating a BitmapTile.
  //
  // With the native engine loaded (R18 A-1 / R19-Z) the scratch lives in
  // pooled NATIVE memory: staging is a C memcpy from the tile's native
  // buffer, Dart works through a typed-data view (the fallback and stamp
  // loops run unchanged) while the kernel gets the raw pointer, and the
  // commit tail ADOPTS the changed buffers as the finished tiles — the
  // whole sequence materializes with zero pixel copies out.
  final native = QaNativeEngine.instance;
  final nativeTiles = native == null ? null : <TileCoord, QaNativeTileBuffer>{};
  final scratchBuffers = <TileCoord, Uint8List>{};
  final changedCoords = <TileCoord>{};

  Uint8List scratchBufferFor(TileCoord coord) {
    return scratchBuffers.putIfAbsent(coord, () {
      final tile = surface.tileAt(coord);
      if (nativeTiles != null) {
        final buffer = native!.acquireTileBuffer(
          tileByteLength,
          zeroed: tile == null,
        );
        nativeTiles[coord] = buffer;
        if (tile != null) {
          // readPixels keeps the tile alive across the copy — a bare
          // pointer would let its finalizer recycle the block mid-memcpy
          // (see BitmapTile.readPixels).
          tile.readPixels(
            (pointer, _) =>
                native.copyBytes(buffer.pointer, pointer, tileByteLength),
          );
        }
        return buffer.view;
      }
      if (tile == null) {
        return Uint8List(tileByteLength);
      }
      return tile.pixels;
    });
  }

  void releaseNativeTiles() {
    if (nativeTiles != null) {
      for (final buffer in nativeTiles.values) {
        native!.releaseTileBuffer(buffer);
      }
      nativeTiles.clear();
    }
  }

  for (final dab in sequence.dabs) {
    // RGBA stamp dabs (R14-④ bitmap lift) take a dedicated 1:1 blend path
    // — the generic tip machinery below stays byte-untouched (its parity
    // pins never see stamps; live == commit still holds by construction
    // because stamps only enter through programmatic commits).
    final stamp = dab.stamp;
    if (stamp != null) {
      _blendStampDab(
        dab: dab,
        stamp: stamp,
        canvasSize: canvasSize,
        tileSize: tileSize,
        scratchBufferFor: scratchBufferFor,
        nativeTileFor: nativeTiles == null
            ? null
            : (coord) {
                scratchBufferFor(coord);
                return nativeTiles[coord]!;
              },
        changedCoords: changedCoords,
      );
      continue;
    }

    // ONE dab kernel (see brush_dab_kernel.dart): the hoists, the six
    // axis lattices and the clipped bounds are resolved in the same place
    // the live rasterizer resolves them, so the two cannot drift.
    final plan = BrushDabPlan.of(
      dab,
      canvasSize: canvasSize,
      tileSize: tileSize,
      erase: dab.erase,
    );
    if (plan == null) {
      continue;
    }

    // Native kernel (R18 A-1): identical pixel visits and float math, one
    // pooled batch per dab straight into the native-backed scratch. The
    // Dart loop below stays byte-for-byte as the reference fallback.
    if (native != null) {
      // pointerFor runs once per span, in span order, so recording the
      // coordinate here keeps batchCoords aligned with the changed flags.
      final batchCoords = <TileCoord>[];
      final changed = blendDabTilesNative(
        plan,
        native,
        tileSize: tileSize,
        pointerFor: (tileX, tileY) {
          final coord = TileCoord(x: tileX, y: tileY);
          scratchBufferFor(coord);
          batchCoords.add(coord);
          return nativeTiles![coord]!.pointer;
        },
      );
      if (changed != null) {
        for (var i = 0; i < batchCoords.length; i += 1) {
          if (changed[i] != 0) {
            changedCoords.add(batchCoords[i]);
          }
        }
      }
      continue;
    }

    blendDabTilesDart(
      plan,
      tileSize: tileSize,
      bufferFor: (tileX, tileY) =>
          scratchBufferFor(TileCoord(x: tileX, y: tileY)),
      onTileChanged: (tileX, tileY) =>
          changedCoords.add(TileCoord(x: tileX, y: tileY)),
    );
  }

  if (changedCoords.isEmpty) {
    releaseNativeTiles();
    return BrushSurfaceMaterialization(
      surface: surface,
      dirtyTiles: DirtyTileSet.empty(),
    );
  }

  final sortedCoords = changedCoords.toList()
    ..sort((a, b) {
      final yComparison = a.y.compareTo(b.y);
      if (yComparison != 0) return yComparison;
      return a.x.compareTo(b.x);
    });

  var updatedSurface = surface;
  var dirtyTiles = DirtyTileSet.empty();
  labProbe('commit.putTiles', () {
    // R19-Z: the CHANGED scratch buffers become the finished tiles — the
    // tile ADOPTS the native buffer (ownership leaves the pool; the
    // tile's finalizer frees it), so a full-canvas commit writes zero
    // pixel copies out. Untouched staged buffers still return to the
    // pool below; the Dart fallback keeps the constructor copy.
    updatedSurface = updatedSurface.putTiles([
      for (final coord in sortedCoords)
        if (nativeTiles != null)
          BitmapTile.adoptNative(
            coord: coord,
            size: tileSize,
            pixels: nativeTiles.remove(coord)!.pointer,
          )
        else
          BitmapTile(
            coord: coord,
            size: tileSize,
            pixels: scratchBuffers[coord]!,
          ),
    ]);
    for (final coord in sortedCoords) {
      dirtyTiles = dirtyTiles.add(coord);
    }
  });
  releaseNativeTiles();

  return BrushSurfaceMaterialization(
    surface: updatedSurface,
    dirtyTiles: dirtyTiles,
  );
}

/// The RGBA stamp blend (R14-④): the stamp's straight-alpha pixels land
/// 1:1 source-over centered on the dab ([BrushStampImage.landingRect]).
/// The source-over float grouping matches the generic path's exactly.
void _blendStampDab({
  required BrushDab dab,
  required BrushStampImage stamp,
  required CanvasSize canvasSize,
  required int tileSize,
  required Uint8List Function(TileCoord) scratchBufferFor,
  required QaNativeTileBuffer Function(TileCoord)? nativeTileFor,
  required Set<TileCoord> changedCoords,
}) {
  final dabOpacity = dab.opacity;
  if (dabOpacity == 0.0) {
    return;
  }
  final landing = stamp.landingRect(dab.center);
  // Pasteboard clip, NOT canvas: a selection dropped past the stage edge
  // keeps its pixels (they land on the pasteboard instead of vanishing).
  final clip = landing.intersection(canvasSize.pasteboardRegion);
  if (clip == null) {
    return;
  }
  // Locals, not field reads: the Dart loop below is per pixel.
  final stampLeft = landing.left;
  final stampTop = landing.top;
  final left = clip.left;
  final top = clip.top;
  final rightExclusive = clip.rightExclusive;
  final bottomExclusive = clip.bottomExclusive;
  final rgba = stamp.rgba;

  // R18 A-0/A-1.5/F-1: the native core blends whole (dab, tile) spans in
  // ONE call each (the per-row FFI call overhead was the fill commit's
  // dominant term), and both sides are native memory — the tile scratch
  // is native-backed and the stamp uploads once per rgba identity (a
  // move session re-commits the SAME stamp per drag move, so repeats are
  // pure pointer math). Byte-identical to the Dart loop below
  // (parity-pinned); Dart remains the reference and the fallback.
  final native = QaNativeEngine.instance;
  final stampUpload = (native != null && nativeTileFor != null)
      ? labProbe('stamp.upload', () => native.uploadStampBytes(rgba))
      : null;
  if (stampUpload != null) {
    // One BATCH call for the whole stamp (R18 A-3a): spans fan out
    // across the C worker pool; disjoint tiles keep it byte-identical
    // to the sequential loop.
    final (
      firstX: tileXStart,
      lastX: tileXEnd,
      firstY: tileYStart,
      lastY: tileYEnd,
    ) = tileRangeOf(
      left: left,
      top: top,
      rightExclusive: rightExclusive,
      bottomExclusive: bottomExclusive,
      tileSize: tileSize,
    );
    final batchCoords = <TileCoord>[];
    labProbe('stamp.stage', () {
      native!.ensureTileSpanBatch(
        (tileYEnd - tileYStart + 1) * (tileXEnd - tileXStart + 1),
      );
      for (var tileY = tileYStart; tileY <= tileYEnd; tileY += 1) {
        final tileTop = tileY * tileSize;
        for (var tileX = tileXStart; tileX <= tileXEnd; tileX += 1) {
          final coord = TileCoord(x: tileX, y: tileY);
          final tileLeft = tileX * tileSize;
          native.setTileSpan(
            batchCoords.length,
            tilePixels: nativeTileFor!(coord).pointer,
            tileLeft: tileLeft,
            tileTop: tileTop,
            spanLeft: math.max(left, tileLeft),
            spanRightExclusive: math.min(rightExclusive, tileLeft + tileSize),
            spanTop: math.max(top, tileTop),
            spanBottomExclusive: math.min(bottomExclusive, tileTop + tileSize),
          );
          batchCoords.add(coord);
        }
      }
    });
    final changed = labProbe(
      'stamp.blend',
      () => native!.stampBlendTiles(
        count: batchCoords.length,
        tileSize: tileSize,
        stampBytes: stampUpload,
        stampWidth: stamp.width,
        stampLeft: stampLeft,
        stampTop: stampTop,
        opacity: dabOpacity,
        erase: dab.erase,
      ),
    );
    for (var i = 0; i < batchCoords.length; i += 1) {
      if (changed[i] != 0) {
        changedCoords.add(batchCoords[i]);
      }
    }
    return;
  }

  final (
    firstX: tileXStart,
    lastX: tileXEnd,
    firstY: _,
    lastY: _,
  ) = tileRangeOf(
    left: left,
    top: top,
    rightExclusive: rightExclusive,
    bottomExclusive: bottomExclusive,
    tileSize: tileSize,
  );
  for (var y = top; y < bottomExclusive; y += 1) {
    final tileY = floorDiv(y, tileSize);
    final localRowOffset = (y - tileY * tileSize) * tileSize;
    final stampRowOffset = (y - stampTop) * stamp.width;

    for (var tileX = tileXStart; tileX <= tileXEnd; tileX += 1) {
      final coord = TileCoord(x: tileX, y: tileY);
      final tileLeft = tileX * tileSize;
      final spanLeft = math.max(left, tileLeft);
      final spanRightExclusive = math.min(rightExclusive, tileLeft + tileSize);

      final buffer = scratchBufferFor(coord);
      for (var x = spanLeft; x < spanRightExclusive; x += 1) {
        final sourceOffset = (stampRowOffset + (x - stampLeft)) * 4;
        final stampA = rgba[sourceOffset + 3];
        if (stampA == 0) {
          continue;
        }
        final offset =
            (localRowOffset + (x - tileLeft)) * BitmapTile.bytesPerPixel;

        // Opaque full-coverage fast paths (R16-④ measured: full-canvas
        // fill/lift stamps spent ~0.5s in the per-pixel double math) —
        // a fully covering stamp pixel at opacity 1 is a byte copy
        // (srcOver) or a byte zero (erase).
        if (stampA == 255 && dabOpacity == 1.0) {
          if (dab.erase) {
            if (buffer[offset] != 0 ||
                buffer[offset + 1] != 0 ||
                buffer[offset + 2] != 0 ||
                buffer[offset + 3] != 0) {
              buffer[offset] = 0;
              buffer[offset + 1] = 0;
              buffer[offset + 2] = 0;
              buffer[offset + 3] = 0;
              changedCoords.add(coord);
            }
          } else {
            if (buffer[offset] != rgba[sourceOffset] ||
                buffer[offset + 1] != rgba[sourceOffset + 1] ||
                buffer[offset + 2] != rgba[sourceOffset + 2] ||
                buffer[offset + 3] != 255) {
              buffer[offset] = rgba[sourceOffset];
              buffer[offset + 1] = rgba[sourceOffset + 1];
              buffer[offset + 2] = rgba[sourceOffset + 2];
              buffer[offset + 3] = 255;
              changedCoords.add(coord);
            }
          }
          continue;
        }
        final sourceAlpha = (stampA / 255.0) * dabOpacity;
        final destR = buffer[offset];
        final destG = buffer[offset + 1];
        final destB = buffer[offset + 2];
        final destA = buffer[offset + 3];
        final destinationAlpha = destA / 255.0;

        int outRByte;
        int outGByte;
        int outBByte;
        int outAByte;
        if (dab.erase) {
          // Stamp-ERASE (R15-④): destination-out from the stamp's EXACT
          // alpha — no tip-mask resampling, so a lift's cut edge is
          // byte-hard (the bilinear tip-mask erase left a half-alpha ring
          // at the selection silhouette: the fringe + origin remnant).
          final outAlpha = destinationAlpha * (1.0 - sourceAlpha);
          if (outAlpha == 0.0) {
            outRByte = 0;
            outGByte = 0;
            outBByte = 0;
            outAByte = 0;
          } else {
            outRByte = destR;
            outGByte = destG;
            outBByte = destB;
            outAByte = (outAlpha * 255.0).round().clamp(0, 255);
          }
          if (outRByte != destR ||
              outGByte != destG ||
              outBByte != destB ||
              outAByte != destA) {
            buffer[offset] = outRByte;
            buffer[offset + 1] = outGByte;
            buffer[offset + 2] = outBByte;
            buffer[offset + 3] = outAByte;
            changedCoords.add(coord);
          }
          continue;
        }

        final outAlpha = sourceAlpha + destinationAlpha * (1.0 - sourceAlpha);
        if (outAlpha == 0.0) {
          outRByte = 0;
          outGByte = 0;
          outBByte = 0;
          outAByte = 0;
        } else {
          final inverseSourceAlpha = 1.0 - sourceAlpha;
          outRByte =
              ((rgba[sourceOffset] * sourceAlpha +
                          destR * destinationAlpha * inverseSourceAlpha) /
                      outAlpha)
                  .round()
                  .clamp(0, 255);
          outGByte =
              ((rgba[sourceOffset + 1] * sourceAlpha +
                          destG * destinationAlpha * inverseSourceAlpha) /
                      outAlpha)
                  .round()
                  .clamp(0, 255);
          outBByte =
              ((rgba[sourceOffset + 2] * sourceAlpha +
                          destB * destinationAlpha * inverseSourceAlpha) /
                      outAlpha)
                  .round()
                  .clamp(0, 255);
          outAByte = (outAlpha * 255.0).round().clamp(0, 255);
        }

        if (outRByte != destR ||
            outGByte != destG ||
            outBByte != destB ||
            outAByte != destA) {
          buffer[offset] = outRByte;
          buffer[offset + 1] = outGByte;
          buffer[offset + 2] = outBByte;
          buffer[offset + 3] = outAByte;
          changedCoords.add(coord);
        }
      }
    }
  }
}

/// Composites a pre-rasterized straight-alpha stroke buffer onto [surface]
/// within [bounds].
///
/// [strokePixels] is BOUNDS-LOCAL: row-major with stride = the bounds
/// width, exactly what `BrushLiveStrokeRasterizer.strokePixelsWithinBounds`
/// materializes — its size scales with the stroke, never the canvas.
///
/// This is the pen-up fast path: the interactive view rasterizes the stroke
/// incrementally while the pointer moves (`BrushLiveStrokeRasterizer`, same
/// per-dab math as [materializeBrushDabSequenceOnBitmapSurface]), so commit
/// only needs one source-over pass of the finished stroke over the existing
/// artwork instead of re-running the whole dab loop — removing the commit
/// hiccup for long dense strokes. The composited pixels are exactly the
/// stroke the user watched being drawn.
///
/// R21: implemented as ONE synthetic stamp dab through the ordinary
/// materializer — the stroke buffer IS a stamp at the bounds (integer
/// placement is exact: center = left + w/2 rounds back to left), and the
/// stamp blend's opacity-1 source-over/destination-out is byte-identical
/// to the old inline loop. That routes the pen-up composite through the
/// SAME C kernels as everything else; the pure-Dart pass here was a
/// measured ~91ms-avg/193ms-max UI hitch per stroke at 2340×1654.
BrushSurfaceMaterialization compositeStrokePixelsOntoBitmapSurface({
  required BitmapSurface surface,
  required Uint8List strokePixels,
  required DirtyRegion bounds,
  bool erase = false,
  BrushBlendMode blendMode = BrushBlendMode.color,
}) {
  final width = bounds.rightExclusive - bounds.left;
  final height = bounds.bottomExclusive - bounds.top;
  if (width <= 0 || height <= 0) {
    return BrushSurfaceMaterialization(
      surface: surface,
      dirtyTiles: DirtyTileSet.empty(),
    );
  }
  BrushDab boundsStampDab({
    required String id,
    required Uint8List rgba,
    required bool erase,
    int sequence = 0,
  }) => BrushDab(
    center: CanvasPoint(x: bounds.left + width / 2, y: bounds.top + height / 2),
    color: 0xFF000000,
    size: math.max(width, height).toDouble(),
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: sequence,
    erase: erase,
    stamp: BrushStampImage(id: id, width: width, height: height, rgba: rgba),
  );

  // BB-1 (R26 #9): a non-trivial BRUSH BLEND applies once per stroke.
  if (blendMode != BrushBlendMode.color && blendMode != BrushBlendMode.erase) {
    // BB-N1 (ABI 22): with the engine loaded, C blends the stroke buffer
    // straight into the staged tile scratch — no region extraction, no
    // result buffer, no two-pass stamp landing — fanned across the
    // worker pool. Byte-identical to the Dart route below (parity-pinned).
    final native = QaNativeEngine.instance;
    if (native != null) {
      return _materializeStrokeBlendNative(
        surface: surface,
        strokePixels: strokePixels,
        bounds: bounds,
        mode: blendMode,
        native: native,
      );
    }
    // Dart REFERENCE + fallback: the result region is computed through
    // the blend kernel and lands through the SAME stamp passes as
    // everything else: an erase-rect pass clears the bounds, then a
    // source-over pass writes the result verbatim (over emptiness
    // srcOver IS replace, byte-exactly). Pixels the stroke never touched
    // come back verbatim from the kernel's alpha-0 copy rule, so the
    // round trip is invisible outside the ink.
    final result = blendStrokeRegionPixels(
      dst: bitmapSurfaceRegionPixels(surface, bounds),
      src: strokePixels,
      mode: blendMode,
      pixelCount: width * height,
    );
    final opaqueRect = Uint8List(width * height * 4)
      ..fillRange(0, width * height * 4, 0xFF);
    return materializeBrushDabSequenceOnBitmapSurface(
      surface: surface,
      sequence: BrushDabSequence([
        boundsStampDab(id: 'stroke-blend-clear', rgba: opaqueRect, erase: true),
        boundsStampDab(
          id: 'stroke-blend-result',
          rgba: result,
          erase: false,
          sequence: 1,
        ),
      ]),
    );
  }
  return materializeBrushDabSequenceOnBitmapSurface(
    surface: surface,
    sequence: BrushDabSequence([
      boundsStampDab(
        id: 'stroke-composite',
        rgba: strokePixels,
        erase: erase || blendMode == BrushBlendMode.erase,
      ),
    ]),
  );
}

/// BB-N1 (ABI 22): the native once-per-stroke blend landing. Stages every
/// tile the bounds cover (existing bytes copied in, missing tiles zeroed
/// — the kernel's da==0 branch IS the transparent read), blends the
/// stroke buffer in place through `qa_stroke_blend_tiles` (one pooled
/// call), and adopts the CHANGED buffers as the finished tiles. Pixels
/// the stroke never inked copy through verbatim, so an untouched tile
/// reports unchanged and returns to the pool — the dirty set is the
/// TRUE change set (the Dart fallback route over-reports: its erase+
/// rewrite passes mark every bounds tile).
BrushSurfaceMaterialization _materializeStrokeBlendNative({
  required BitmapSurface surface,
  required Uint8List strokePixels,
  required DirtyRegion bounds,
  required BrushBlendMode mode,
  required QaNativeEngine native,
}) {
  final canvasSize = surface.canvasSize;
  final tileSize = surface.tileSize;
  final tileByteLength = tileSize * tileSize * BitmapTile.bytesPerPixel;
  // The stroke buffer is BOUNDS-LOCAL (stride = bounds width, origin =
  // bounds top-left, like a stamp's raw placement); the blend clips at
  // the pasteboard exactly like the stamp path.
  final clip = bounds.intersection(canvasSize.pasteboardRegion);
  if (clip == null) {
    return BrushSurfaceMaterialization(
      surface: surface,
      dirtyTiles: DirtyTileSet.empty(),
    );
  }
  final left = clip.left;
  final top = clip.top;
  final rightExclusive = clip.rightExclusive;
  final bottomExclusive = clip.bottomExclusive;
  final strokeUpload = labProbe(
    'strokeBlend.upload',
    () => native.uploadStampBytes(strokePixels),
  );
  final (
    firstX: tileXStart,
    lastX: tileXEnd,
    firstY: tileYStart,
    lastY: tileYEnd,
  ) = tileRangeOf(
    left: left,
    top: top,
    rightExclusive: rightExclusive,
    bottomExclusive: bottomExclusive,
    tileSize: tileSize,
  );
  final nativeTiles = <TileCoord, QaNativeTileBuffer>{};
  final batchCoords = <TileCoord>[];
  labProbe('strokeBlend.stage', () {
    native.ensureTileSpanBatch(
      (tileYEnd - tileYStart + 1) * (tileXEnd - tileXStart + 1),
    );
    for (var tileY = tileYStart; tileY <= tileYEnd; tileY += 1) {
      final tileTop = tileY * tileSize;
      for (var tileX = tileXStart; tileX <= tileXEnd; tileX += 1) {
        final coord = TileCoord(x: tileX, y: tileY);
        final tile = surface.tileAt(coord);
        final buffer = native.acquireTileBuffer(
          tileByteLength,
          zeroed: tile == null,
        );
        if (tile != null) {
          // readPixels keeps the tile alive across the copy — a bare
          // pointer would let its finalizer recycle the block mid-memcpy
          // (see BitmapTile.readPixels).
          tile.readPixels(
            (pointer, _) =>
                native.copyBytes(buffer.pointer, pointer, tileByteLength),
          );
        }
        nativeTiles[coord] = buffer;
        final tileLeft = tileX * tileSize;
        native.setTileSpan(
          batchCoords.length,
          tilePixels: buffer.pointer,
          tileLeft: tileLeft,
          tileTop: tileTop,
          spanLeft: math.max(left, tileLeft),
          spanRightExclusive: math.min(rightExclusive, tileLeft + tileSize),
          spanTop: math.max(top, tileTop),
          spanBottomExclusive: math.min(bottomExclusive, tileTop + tileSize),
        );
        batchCoords.add(coord);
      }
    }
  });
  final changed = labProbe(
    'strokeBlend.blend',
    () => native.strokeBlendTiles(
      count: batchCoords.length,
      tileSize: tileSize,
      strokeBytes: strokeUpload,
      strokeWidth: bounds.rightExclusive - bounds.left,
      strokeLeft: bounds.left,
      strokeTop: bounds.top,
      mode: strokeBlendModeNativeId(mode),
    ),
  );
  final changedCoords = <TileCoord>[
    for (var i = 0; i < batchCoords.length; i += 1)
      if (changed[i] != 0) batchCoords[i],
  ];
  void releaseStagedTiles() {
    for (final buffer in nativeTiles.values) {
      native.releaseTileBuffer(buffer);
    }
    nativeTiles.clear();
  }

  if (changedCoords.isEmpty) {
    releaseStagedTiles();
    return BrushSurfaceMaterialization(
      surface: surface,
      dirtyTiles: DirtyTileSet.empty(),
    );
  }
  changedCoords.sort((a, b) {
    final yComparison = a.y.compareTo(b.y);
    if (yComparison != 0) return yComparison;
    return a.x.compareTo(b.x);
  });
  var updatedSurface = surface;
  var dirtyTiles = DirtyTileSet.empty();
  labProbe('strokeBlend.putTiles', () {
    // Changed buffers become the finished tiles (adopted, R19-Z);
    // unchanged staged buffers return to the pool below.
    updatedSurface = updatedSurface.putTiles([
      for (final coord in changedCoords)
        BitmapTile.adoptNative(
          coord: coord,
          size: tileSize,
          pixels: nativeTiles.remove(coord)!.pointer,
        ),
    ]);
    for (final coord in changedCoords) {
      dirtyTiles = dirtyTiles.add(coord);
    }
  });
  releaseStagedTiles();
  return BrushSurfaceMaterialization(
    surface: updatedSurface,
    dirtyTiles: dirtyTiles,
  );
}
