import 'dart:typed_data';

import '../models/bitmap_surface.dart';
import '../models/brush_dab.dart';
import '../models/brush_dab_sequence.dart';
import '../models/canvas_size.dart';
import '../models/dirty_region.dart';
import 'bitmap_surface_brush_commit.dart';
import 'brush_dab_dirty_region.dart';
import 'brush_stroke_blend.dart';
import 'canvas_selection_region.dart';

/// A stroke rasterized and CLIPPED to the live selection (R26 #18: "선택
/// 하고 그리면 선택 내부만 그려진다"), ready to ride the ordinary
/// prerasterized-commit route.
class ClippedStrokePixels {
  const ClippedStrokePixels({required this.pixels, required this.bounds});

  final Uint8List pixels;
  final DirtyRegion bounds;
}

/// Confines a stroke buffer to [region] — [applySelectionMaskToStrokeAlpha]
/// over the region's coverage, which is the ONE selection rule the live
/// pre-blend kernel also runs.
///
/// This is the FALLBACK half of R26 #18 now. A stroke drawn with a live
/// raster carries the selection through the pre-blend kernel instead
/// (`BrushLiveStrokeRasterizer.selectionRegion`), so its promoted tiles
/// arrive already masked and the panel passes them straight through.
/// What still comes here: programmatic strokes and history redos, which
/// had no live raster to be masked in. Same mask bytes, same rounding,
/// same rule — so a redo cannot land a different edge than the stroke it
/// replays, at any mask softness.
///
/// Straight-alpha buffers make this exact for every brush blend mode at
/// once: alpha 0 is the documented "destination survives untouched" input
/// of the commit kernels — plain srcOver contributes nothing, the erase
/// stamp removes nothing, and the separable/behind kernels return the
/// destination bytes verbatim. So ONE mask on the stroke buffer clips
/// drawing, erasing and filling alike, with no per-mode special cases.
///
/// Returns null when nothing survives — the caller then skips the commit
/// entirely rather than landing an empty edit.
ClippedStrokePixels? clipStrokePixelsToSelection({
  required Uint8List pixels,
  required DirtyRegion bounds,
  required CanvasSelectionRegion region,
}) {
  final width = bounds.width;
  final height = bounds.height;
  if (width <= 0 || height <= 0) {
    return null;
  }
  final mask = region.maskFor(
    left: bounds.left,
    top: bounds.top,
    width: width,
    height: height,
  );
  final clipped = Uint8List.fromList(pixels);
  applySelectionMaskToStrokeAlpha(
    pixels: clipped,
    mask: mask,
    pixelCount: width * height,
  );
  for (var index = 0; index < mask.length; index += 1) {
    if (clipped[index * 4 + 3] != 0) {
      return ClippedStrokePixels(pixels: clipped, bounds: bounds);
    }
  }
  return null;
}

/// Rasterizes [dabs] into a bounds-local straight-alpha buffer so a
/// stroke that arrives WITHOUT live pixels (programmatic strokes, a redo
/// replaying source dabs) can still be clipped.
///
/// Erase dabs rasterize with the flag flipped OFF: what is wanted here is
/// the stroke's COVERAGE, which the commit then re-applies as one erase
/// stamp — the same "accumulate the stroke, composite once" shape the
/// live rasterizer produces (and unlike the dab-by-dab loop, overlapping
/// erase dabs do not compound).
ClippedStrokePixels? rasterizeStrokeForClipping({
  required List<BrushDab> dabs,
  required CanvasSize canvasSize,
  required int tileSize,
}) {
  if (dabs.isEmpty) {
    return null;
  }
  final coverageDabs = [
    for (final dab in dabs)
      if (dab.erase) dab.copyWith(erase: false) else dab,
  ];
  final sequence = BrushDabSequence(coverageDabs);
  final bounds = dirtyRegionForBrushDabSequence(sequence);
  if (bounds == null) {
    return null;
  }
  final scratch = materializeBrushDabSequenceOnBitmapSurface(
    surface: BitmapSurface(canvasSize: canvasSize, tileSize: tileSize),
    sequence: sequence,
  );
  return ClippedStrokePixels(
    pixels: bitmapSurfaceRegionPixels(scratch.surface, bounds),
    bounds: bounds,
  );
}

/// [dabs] rasterized ([rasterizeStrokeForClipping]) and clipped to
/// [region] ([clipStrokePixelsToSelection]) — the whole of what a stroke
/// that arrives without live pixels goes through before the commit, in
/// one place: the canvas panel's commit funnel runs it for programmatic
/// strokes and history redos, and a fill's promotion runs it so the
/// tiles it shows before the commit are the tiles the commit lands.
///
/// Null when the stroke draws nothing, or nothing of it survives the
/// selection.
ClippedStrokePixels? clipDabsToSelection({
  required List<BrushDab> dabs,
  required CanvasSize canvasSize,
  required int tileSize,
  required CanvasSelectionRegion region,
}) {
  final rasterized = rasterizeStrokeForClipping(
    dabs: dabs,
    canvasSize: canvasSize,
    tileSize: tileSize,
  );
  return rasterized == null
      ? null
      : clipStrokePixelsToSelection(
          pixels: rasterized.pixels,
          bounds: rasterized.bounds,
          region: region,
        );
}
