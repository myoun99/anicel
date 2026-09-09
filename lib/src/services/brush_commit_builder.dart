import 'dart:typed_data';

import '../models/placed_tile.dart';
import '../models/bitmap_surface.dart';
import '../models/brush_blend_mode.dart';
import '../models/dirty_region.dart';
import '../models/dirty_tile_set.dart';
import '../models/brush_commit_result.dart';
import '../models/brush_dab_sequence.dart';
import '../models/frame_id.dart';
import '../models/layer_id.dart';
import 'bitmap_surface_brush_commit.dart';
import 'brush_commit_cache_invalidation.dart';
import 'brush_stroke_blend.dart';
import 'canvas_selection_paint_clip.dart';

BrushCommitResult brushCommitResultForBrushDabSequenceOnBitmapSurface({
  required BitmapSurface surface,
  required BrushDabSequence sequence,
  required LayerId layerId,
  required FrameId frameId,
  Uint8List? prerasterizedStrokePixels,
  DirtyRegion? prerasterizedStrokeBounds,
  BrushBlendMode blendMode = BrushBlendMode.color,
  BitmapSurface? promotedBase,
  List<PlacedTile>? promotedTiles,
}) {
  // PROMOTION fast path: the live overlay already produced the finished
  // tiles — pre-blended against `promotedBase` with these very kernels,
  // and displayed to the user for the whole stroke. If the cel surface is
  // still that object, committing is a tile PUT: the pixels do not move,
  // they are simply installed. The identity check is the gate — anything
  // that touched the surface in between (a concurrent commit, an undo)
  // drops us onto the ordinary route below, which re-derives everything
  // from the dabs.
  if (promotedTiles != null &&
      promotedBase != null &&
      identical(promotedBase, surface)) {
    if (promotedTiles.isEmpty) {
      return BrushCommitResult.noOp(surface: surface);
    }
    // ONE set build, not one per tile: `DirtyTileSet` is immutable, so
    // folding coordinates in with a per-coordinate add rebuilt the whole
    // set n times for an n-tile commit. The single-coord form is gone
    // now (see DirtyTileSet.addAll) — this is the shape that survives.
    final dirtyTiles = DirtyTileSet(
      promotedTiles.map((placed) => placed.coord),
    );
    return BrushCommitResult.changed(
      beforeSurface: surface,
      afterSurface: surface.putMaterializedTiles(promotedTiles),
      dirtyTiles: dirtyTiles,
      cacheInvalidationPlan: cacheInvalidationPlanForDirtyTiles(
        layerId: layerId,
        frameId: frameId,
        dirtyTiles: dirtyTiles,
      ),
    );
  }
  // Pen-up fast path: when the interactive view already rasterized the
  // stroke incrementally while drawing (same per-dab math), commit is a
  // single composite pass instead of re-running the whole dab loop. A
  // stroke is homogeneous: every dab shares the tool's erase mode.
  var strokePixels = prerasterizedStrokePixels;
  var strokeBounds = prerasterizedStrokeBounds;
  // 🚨F-12: a stroke OPACITY needs the whole stroke as one buffer for
  // exactly the reason a brush blend does — it is a ceiling on what the
  // accumulated stroke may reach, and dab-by-dab it is not a ceiling at all
  // (dabs pile up source-over and converge on 1). So it takes the same
  // route BB-1 built, and the two conditions are one condition.
  final needsWholeStroke =
      blendMode.isSeparable ||
      blendMode == BrushBlendMode.behind ||
      strokeOpacityCoverage(sequence.opacity) < 255;
  if (needsWholeStroke) {
    // BB-1: a brush blend needs the WHOLE stroke as one buffer (the mode
    // must never apply dab-by-dab). Without a live raster (programmatic
    // strokes, a redo without pixels), materialize the dabs onto an
    // EMPTY surface first — same kernels, same pixels.
    if (strokePixels == null || strokeBounds == null) {
      // 🚨★★★**THE SAME RASTERIZER THE CLIP PATH USES, and it had to be:
      // this was a second copy of it that had lost the one rule that
      // matters.** Both build the stroke's coverage on an EMPTY surface,
      // and there `dab.erase` erases nothing from nothing — the copy here
      // kept the flag on, so an erase stroke arriving without live pixels
      // rasterized to an all-zero buffer and committed as a no-op. The
      // sibling flips it off and says why (「what is wanted here is the
      // stroke's COVERAGE, which the commit then re-applies as one erase
      // stamp」). Two implementations of one algorithm, and the one
      // without the law was this one.
      final raster = rasterizeStrokeForClipping(
        dabs: sequence.dabs,
        canvasSize: surface.canvasSize,
        tileSize: surface.tileSize,
      );
      if (raster == null) {
        return BrushCommitResult.noOp(surface: surface);
      }
      strokePixels = raster.pixels;
      strokeBounds = raster.bounds;
    }
  }
  // The CEILING, applied once to the accumulated buffer — the same channel
  // and the same rounding a selection mask uses, because it is the same
  // question ("one factor on the whole stroke") with a constant answer.
  //
  // ⚠️Only on the buffer route. A promoted stroke returned above with its
  // tiles already blended THROUGH this coverage (the live rasterizer folds
  // it into its own mask), and doing it again here would square it.
  if (strokePixels != null && strokeBounds != null) {
    final coverage = strokeCoverageMask(
      pixelCount: strokeBounds.width * strokeBounds.height,
      opacity: sequence.opacity,
    );
    if (coverage != null) {
      strokePixels = Uint8List.fromList(strokePixels);
      applySelectionMaskToStrokeAlpha(
        pixels: strokePixels,
        mask: coverage,
        pixelCount: coverage.length,
      );
    }
  }
  final materialization = strokePixels != null && strokeBounds != null
      ? compositeStrokePixelsOntoBitmapSurface(
          surface: surface,
          strokePixels: strokePixels,
          bounds: strokeBounds,
          // The sequence answers both halves itself — reaching through
          // `dabs` to ask `isNotEmpty` and `first` is asking the list for
          // what the object already knows.
          erase: sequence.firstOrNull?.erase ?? false,
          blendMode: blendMode,
        )
      : materializeBrushDabSequenceOnBitmapSurface(
          surface: surface,
          sequence: sequence,
        );
  final cacheInvalidationPlan = cacheInvalidationPlanForDirtyTiles(
    layerId: layerId,
    frameId: frameId,
    dirtyTiles: materialization.dirtyTiles,
  );

  if (!materialization.hasChanges) {
    return BrushCommitResult.noOp(surface: surface);
  }

  return BrushCommitResult.changed(
    beforeSurface: surface,
    afterSurface: materialization.surface,
    dirtyTiles: materialization.dirtyTiles,
    cacheInvalidationPlan: cacheInvalidationPlan,
  );
}
