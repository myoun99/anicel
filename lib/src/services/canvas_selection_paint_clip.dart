import 'dart:typed_data';

import '../models/bitmap_surface.dart';
import '../models/brush_dab.dart';
import '../models/brush_dab_sequence.dart';
import '../models/canvas_size.dart';
import '../models/dirty_region.dart';
import 'bitmap_surface_brush_commit.dart';
import 'brush_dab_dirty_region.dart';
import 'brush_stroke_blend.dart';
import 'brush_stroke_commit_data.dart';
import 'selection_clip.dart';

/// A stroke's coverage rasterized on an empty surface — bounds-local
/// straight-alpha RGBA and the bounds it covers — ready to ride the
/// ordinary prerasterized-commit route.
class StrokeCoveragePixels {
  const StrokeCoveragePixels({required this.pixels, required this.bounds});

  final Uint8List pixels;
  final DirtyRegion bounds;
}

/// Rasterizes [dabs] into a bounds-local straight-alpha buffer — the
/// buffer the live overlay would have piled up — so a stroke that arrives
/// WITHOUT live pixels (re-derived from its dabs, or a stamp) can still be
/// composited once.
///
/// Erase dabs rasterize with the flag flipped OFF: what is wanted here is
/// the stroke's COVERAGE, which the commit then re-applies as one erase
/// stamp — the same "accumulate the stroke, composite once" shape the
/// live rasterizer produces. ↩️This said the dab-by-dab loop made
/// overlapping erase dabs compound where this does not; both leave
/// b·Π(1−s), and what differs is only where the rounding falls
/// (erase-live-and-dab-route-round-apart).
StrokeCoveragePixels? rasterizeStrokeCoverage({
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
  return StrokeCoveragePixels(
    pixels: bitmapSurfaceRegionPixels(scratch.surface, bounds),
    bounds: bounds,
  );
}

/// A finished stroke's commit payload confined to [clip]: the payload with
/// the selection the commit cuts it by where it lands
/// ([BrushStrokeCommitData.selection]) — on [surface], the cel as it stands
/// at the commit, or on whichever cel lays it down again. Null when the
/// selection reaches none of it, and the caller then commits nothing at
/// all.
///
/// 🚨★★★PROMOTED TILES ARE THE ANSWER ONLY WHILE [surface] IS THE ONE THEY
/// WERE BLENDED AGAINST. They were masked in the pre-blend kernel, so on
/// that surface they are already cut, and the commit installs them as they
/// are. Once anything has landed on the cel in between, the commit ignores
/// them and re-derives the stroke from its dabs — and until the funnel
/// existed it re-derived the WHOLE stroke there, the selection forgotten.
/// So the payload carries its selection whichever way it lands.
///
/// ↩️Till 2026-11-14 the stroke was cut HERE, on the CPU: its dabs
/// rasterized and folded under the mask (`clipDabsToSelection`), each stamp
/// folded in its own picture (`clipStampDabToSelection`), a blur laid again
/// through the clip as tiles of [surface]. The commit cuts every one of them
/// on the engine now, under the clip's mask, where it lands
/// (`brushCommitResultForBrushDabSequenceOnBitmapSurface`) — the mask a live
/// stroke under the same clip lands under.
///
/// ⛔ONE funnel for the canvas's selection (R26 #18, 「선택하고 그리면 선택
/// 내부만 그려진다」) and what a sheet window keeps of its stroke — the same
/// question, 「only here」, asked of the same payload.
BrushStrokeCommitData? clipStrokeCommitToSelection(
  BrushStrokeCommitData data, {
  required SelectionClip clip,
  required BitmapSurface surface,
}) {
  final promoted = data.promotedTiles;
  final standing = promoted != null && identical(data.promotedBase, surface);
  if (standing ? promoted.isEmpty : !_reaches(clip, data)) {
    return null;
  }
  return data.through(clip);
}

/// Whether [clip] may select any pixel [data] lands on: its live buffer's
/// bounds, or the reach of any of its dabs ([SelectionClip.mayCover]).
bool _reaches(SelectionClip clip, BrushStrokeCommitData data) {
  final bounds = data.strokeBounds;
  if (bounds != null) {
    return clip.mayCover(bounds);
  }
  for (final dab in data.sourceDabs) {
    if (dirtyRegionForBrushDab(dab) case final reach?
        when clip.mayCover(reach)) {
      return true;
    }
  }
  return false;
}
