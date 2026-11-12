import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gpu_engine/gpu_engine.dart';

import '../core/floor_math.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/brush_blend_mode.dart';
import '../models/brush_dab.dart';
import '../models/brush_dab_sequence.dart';
import '../models/brush_stamp_image.dart';
import '../models/brush_tip_shape.dart';
import '../models/canvas_point.dart';
import '../models/dirty_region.dart';
import '../models/dirty_tile_set.dart';
import '../models/pasteboard_bounds.dart';
import '../models/placed_tile.dart';
import '../models/tile_coord.dart';
import '../native/app_gpu_engine.dart';
import '../native/engine_stamp_pictures.dart';
import '../native/engine_tile_ledger.dart';
import '../core/dev_profile.dart';
import 'brush_dab_kernel.dart';
import 'brush_stroke_landing.dart';
import 'brush_stamp_span_kernel.dart';
import 'brush_stroke_blend.dart';
import 'commit_tile_scratch.dart';

class BrushSurfaceMaterialization {
  const BrushSurfaceMaterialization({
    required this.surface,
    required this.dirtyTiles,
  });

  final BitmapSurface surface;
  final DirtyTileSet dirtyTiles;

  bool get hasChanges => dirtyTiles.isNotEmpty;
}

/// Whether a commit on [surface] is laid on the engine: its grid, on the
/// isolate that has the engine. ⛔A worker has none to ask, and what would
/// come back are tiles of a pool no other isolate reads: a vector layer an
/// import draws plans its strokes on a worker and lays them on the isolate
/// that has the engine (`clipVectorTiles`). ↩️Till 2026-11-12 it drew them
/// on the worker, as the small grids are drawn — the last road that way had
/// in the app; the small grids are tests' alone now.
bool _landsOnEngine(BitmapSurface surface) =>
    surface.tileSize == gpuTileSide && appGpuEngineIsHere;

/// Rasterizes [sequence] onto [surface] and returns the updated surface plus
/// the tiles it changed.
///
/// On the engine's grid the engine lays it ([_materializedOnEngine]). On
/// another the dabs blend here, directly into per-tile scratch byte
/// buffers: each touched tile's pixels are copied at most once, and no
/// per-pixel objects are allocated. The blend math is kept identical to the
/// reference pixel pipeline (`brushPixelBlendOperationsForDabSequence` +
/// `applyBrushPixelBlendOperationsToBitmapTile`), which remains as the slow
/// per-pixel-operation oracle used by the parity test.
BrushSurfaceMaterialization materializeBrushDabSequenceOnBitmapSurface({
  required BitmapSurface surface,
  required BrushDabSequence sequence,
}) {
  if (_landsOnEngine(surface)) {
    return _materializedOnEngine(surface, sequence);
  }
  // Strokes clip at the PASTEBOARD (as far past the canvas as the
  // project's size reaches, the canvas itself when it is off — I-109),
  // not the canvas — drawing off the stage is the point.
  // Composite/export raster at canvas size, which crops for free. The
  // clip itself lives in BrushDabPlan, so both raster routes take it.
  final wall = surface.pasteboard;
  final tileSize = surface.tileSize;

  // A stroke with a second tip says so on every dab ([BrushDab.dual]).
  final secondTip =
      sequence.dabs.isNotEmpty && sequence.dabs.first.dual != null;
  final scratch = CommitTileScratch(surface, secondTip: secondTip);
  final changedCoords = <TileCoord>{};

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
        wall: wall,
        tileSize: tileSize,
        scratch: scratch,
        changedCoords: changedCoords,
      );
      continue;
    }

    // ONE dab kernel (see brush_dab_kernel.dart): the hoists, the six
    // axis lattices and the clipped bounds are resolved in the same place
    // the live rasterizer resolves them, so the two cannot drift.
    final plan = BrushDabPlan.of(
      dab,
      wall: wall,
      tileSize: tileSize,
      erase: dab.erase,
    );
    if (plan == null) {
      continue;
    }

    blendDabTilesDart(
      plan,
      tileSize: tileSize,
      bufferFor: (tileX, tileY) =>
          scratch.planesFor(TileCoord(x: tileX, y: tileY)),
      onTileChanged: (tileX, tileY) =>
          changedCoords.add(TileCoord(x: tileX, y: tileY)),
    );
  }

  return _finishMaterialization(
    surface: surface,
    scratch: scratch,
    changedCoords: changedCoords,
  );
}

/// [sequence] laid on [surface] by the engine (flip lane ⓒ), in its order:
/// a run of brush dabs piled and laid as one stroke, each stamp by itself —
/// a lift's landing means what it says only dab by dab. What each lands on
/// is what the one before it left.
BrushSurfaceMaterialization _materializedOnEngine(
  BitmapSurface surface,
  BrushDabSequence sequence,
) {
  var landed = surface;
  final changed = <TileCoord>{};
  void put(List<PlacedTile> tiles) {
    if (tiles.isNotEmpty) {
      landed = landed.putMaterializedTiles(tiles);
      changed.addAll(tiles.map((tile) => tile.coord));
    }
  }

  final dabs = sequence.dabs;
  var at = 0;
  while (at < dabs.length) {
    final first = dabs[at];
    final stamp = first.stamp;
    if (stamp != null) {
      at += 1;
      put(
        _pictureOnEngine(
          landed,
          EngineStampPictures.of(stamp),
          stamp.landingRect(first.center),
          (
            opacity: first.opacity,
            mode: engineBlendModeOf(BrushBlendMode.color, erase: first.erase),
          ),
        ),
      );
      continue;
    }
    var end = at + 1;
    while (end < dabs.length &&
        dabs[end].stamp == null &&
        dabs[end].erase == first.erase) {
      end += 1;
    }
    put(strokeLandedOn(landed, BrushDabSequence(dabs.getRange(at, end))));
    at = end;
  }
  final coords = changed.toList()..sort(TileCoord.compareRowMajor);
  return BrushSurfaceMaterialization(
    surface: landed,
    dirtyTiles: coords.isEmpty ? DirtyTileSet.empty() : DirtyTileSet(coords),
  );
}

/// [picture] over [landing], what the pasteboard's wall leaves of it — a
/// selection dropped past the stage's edge keeps its pixels there —, laid
/// on [surface] as [laid] says: the tiles it changes, a blank one where
/// none is left.
List<PlacedTile> _pictureOnEngine(
  BitmapSurface surface,
  GpuStampPicture picture,
  DirtyRegion landing,
  ({double opacity, int mode}) laid,
) {
  final (:opacity, :mode) = laid;
  final clip = landing.intersection(surface.pasteboard.region);
  if (clip == null) {
    return const [];
  }
  final tileSize = surface.tileSize;
  final (:firstX, :lastX, :firstY, :lastY) = clip.tileRange(tileSize: tileSize);
  final coords = [
    for (var y = firstY; y <= lastY; y += 1)
      for (var x = firstX; x <= lastX; x += 1) TileCoord(x: x, y: y),
  ];
  final landed = EngineTileLedger.instance.land(
    EngineTileLedger.landedCel,
    [
      for (final coord in coords)
        (column: coord.x, row: coord.y, under: surface.tileAt(coord)),
    ],
    by: (pool, cel, asked) => appGpuStampLanding.land(
      appGpuComposite,
      pool,
      cel,
      picture,
      left: landing.left,
      top: landing.top,
      within: (clip.left, clip.top, clip.rightExclusive, clip.bottomExclusive),
      asks: asked,
      opacity: (opacity * 65535).round(),
      mode: mode,
    ),
    compared: true,
  );
  return [
    for (var at = 0; at < landed.length; at += 1)
      if (landed[at].change != GpuChange.same)
        (
          coord: coords[at],
          tile: landed[at].tile ?? BitmapTile.blank(size: tileSize),
        ),
  ];
}

/// The commit's tail off the engine's grid: the CHANGED scratch tiles
/// become the surface's tiles, row-major. A tile the pass emptied is
/// DROPPED rather than stored — see [BitmapSurface.putMaterializedTiles].
///
/// ⚠️[DirtyTileSet] still names a dropped coordinate, and has to: its one
/// consumer is [CacheInvalidationPlan.fromDirtyTiles], and a coordinate
/// whose tile just went away is exactly one whose cached picture must go
/// with it.
BrushSurfaceMaterialization _finishMaterialization({
  required BitmapSurface surface,
  required CommitTileScratch scratch,
  required Iterable<TileCoord> changedCoords,
}) {
  final sortedCoords = changedCoords.toList()..sort(TileCoord.compareRowMajor);
  if (sortedCoords.isEmpty) {
    return BrushSurfaceMaterialization(
      surface: surface,
      dirtyTiles: DirtyTileSet.empty(),
    );
  }
  var updatedSurface = surface;
  labProbe('commit.putTiles', () {
    updatedSurface = surface.putMaterializedTiles([
      for (final coord in sortedCoords) (coord: coord, tile: scratch.finish(coord)),
    ]);
  });
  return BrushSurfaceMaterialization(
    surface: updatedSurface,
    dirtyTiles: DirtyTileSet(sortedCoords),
  );
}

/// The RGBA stamp blend (R14-④): the stamp's straight-alpha pixels land
/// 1:1 source-over centered on the dab ([BrushStampImage.landingRect]).
/// The source-over float grouping matches the generic path's exactly.
void _blendStampDab({
  required BrushDab dab,
  required BrushStampImage stamp,
  required PasteboardWall wall,
  required int tileSize,
  required CommitTileScratch scratch,
  required Set<TileCoord> changedCoords,
}) {
  final dabOpacity = dab.opacity;
  if (dabOpacity == 0.0) {
    return;
  }
  final landing = stamp.landingRect(dab.center);
  // Pasteboard clip, NOT canvas: a selection dropped past the stage edge
  // keeps its pixels (they land on the pasteboard instead of vanishing).
  final clip = landing.intersection(wall.region);
  if (clip == null) {
    return;
  }
  // Locals, not field reads: the loop below is per pixel.
  final stampLeft = landing.left;
  final stampTop = landing.top;
  final left = clip.left;
  final top = clip.top;
  final rightExclusive = clip.rightExclusive;
  final bottomExclusive = clip.bottomExclusive;
  final rgba = stamp.rgba;
  final erase = dab.erase;

  // One blitter per dab: the stamp's bytes, its opacity and its erase
  // flag do not change between spans, so they are resolved before the
  // row loop and never re-read inside it.
  final blitter = BrushStampBlitter(
    rgba: rgba,
    dabOpacity: dabOpacity,
    erase: erase,
  );
  final (firstX: tileXStart, lastX: tileXEnd, firstY: _, lastY: _) = clip
      .tileRange(tileSize: tileSize);
  for (var y = top; y < bottomExclusive; y += 1) {
    final tileY = floorDiv(y, tileSize);
    final localRowOffset = (y - tileY * tileSize) * tileSize;
    final stampRowOffset = (y - stampTop) * stamp.width;

    for (var tileX = tileXStart; tileX <= tileXEnd; tileX += 1) {
      final coord = TileCoord(x: tileX, y: tileY);
      final tileLeft = tileX * tileSize;
      final spanLeft = math.max(left, tileLeft);
      final spanRightExclusive = math.min(rightExclusive, tileLeft + tileSize);

      final buffer = scratch.bufferFor(coord);
      if (blitter.blendSpanInPlace(
        buffer,
        (localRowOffset + (spanLeft - tileLeft)) * BitmapTile.bytesPerPixel,
        (stampRowOffset + (spanLeft - stampLeft)) * 4,
        spanRightExclusive - spanLeft,
      )) {
        changedCoords.add(coord);
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
/// This is the pen-up fast path: the interactive view piles the stroke up
/// on its own buffer while the pointer moves (`BrushLiveStrokeRasterizer`,
/// the dab kernels [materializeBrushDabSequenceOnBitmapSurface] runs), so
/// commit is one source-over pass of the finished stroke over the existing
/// artwork — removing the commit hiccup for long dense strokes. The
/// composited pixels are exactly the stroke the user watched being drawn.
///
/// ⚠️It is also the ONLY way a stroke of brush dabs lands: one re-derived
/// from its dabs is piled up on an empty surface first and comes through
/// here (`brushCommitResultForBrushDabSequenceOnBitmapSurface`). The same
/// dabs laid on the artwork one by one reach the same sum but round after
/// every dab, a level away over paint.
///
/// R21: off the engine's grid it is ONE synthetic stamp dab through the
/// ordinary materializer — the stroke buffer IS a stamp at the bounds
/// (integer placement is exact: center = left + w/2 rounds back to left),
/// and the stamp blend's opacity-1 source-over/destination-out is
/// byte-identical to the old inline loop.
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
  if (_landsOnEngine(surface)) {
    // One landing whatever the blend: the engine lays the stroke's picture
    // in its mode.
    final tiles = _pictureOnEngine(
      surface,
      GpuStampPicture(appGpuEngine, strokePixels, width, height),
      bounds,
      (opacity: 1, mode: engineBlendModeOf(blendMode, erase: erase)),
    );
    final coords = [for (final tile in tiles) tile.coord]
      ..sort(TileCoord.compareRowMajor);
    return BrushSurfaceMaterialization(
      surface: coords.isEmpty ? surface : surface.putMaterializedTiles(tiles),
      dirtyTiles: coords.isEmpty ? DirtyTileSet.empty() : DirtyTileSet(coords),
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
    // The result region is computed through the blend kernel and lands
    // through the SAME stamp passes as everything else: an erase-rect pass
    // clears the bounds, then a source-over pass writes the result
    // verbatim (over emptiness srcOver IS replace, byte-exactly). Pixels
    // the stroke never touched come back verbatim from the kernel's
    // alpha-0 copy rule, so the round trip is invisible outside the ink.
    // ⚠️The dirty set is every tile of the bounds, not the true change
    // set: the two passes mark each.
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
