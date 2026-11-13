
import '../models/bitmap_surface.dart';
import '../models/brush_dab.dart';
import '../models/brush_dab_sequence.dart';
import '../models/canvas_size.dart';
import 'bitmap_surface_brush_commit.dart';
import 'brush_stroke_landing.dart';
import 'brush_dab_dirty_region.dart';
import 'brush_stroke_blend.dart';
import 'brush_stroke_commit_data.dart';
import 'selection_clip.dart';
import 'selection_fold.dart';

/// Rasterizes [dabs] into a bounds-local straight-alpha buffer — the
/// buffer the live overlay would have piled up — so a stroke that arrives
/// WITHOUT live pixels (re-derived from its dabs, or a stamp) can still be
/// clipped and composited once.
///
/// Erase dabs rasterize with the flag flipped OFF: what is wanted here is
/// the stroke's COVERAGE, which the commit then re-applies as one erase
/// stamp — the same "accumulate the stroke, composite once" shape the
/// live rasterizer produces. ↩️This said the dab-by-dab loop made
/// overlapping erase dabs compound where this does not; both leave
/// b·Π(1−s), and what differs is only where the rounding falls
/// (erase-live-and-dab-route-round-apart).
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
/// [clip] ([clipStrokePixelsToSelection]) — the whole of what a stroke
/// of brush dabs that arrives without live pixels goes through before the
/// commit: the canvas panel's commit funnel runs it for programmatic
/// strokes and history redos. A stamp takes [clipStampDabToSelection]
/// instead.
///
/// Null when the stroke draws nothing, or nothing of it survives the
/// selection.
///
/// Dabs the selection cannot reach are left out before anything is
/// rasterized — the live rasterizer's rule ([SelectionClip.mayCover]),
/// for the same reason: the mask would zero every pixel they add.
ClippedStrokePixels? clipDabsToSelection({
  required List<BrushDab> dabs,
  required CanvasSize canvasSize,
  required int tileSize,
  required SelectionClip clip,
}) {
  final reaching = [
    for (final dab in dabs)
      if (dirtyRegionForBrushDab(dab) case final reach?)
        if (clip.mayCover(reach)) dab,
  ];
  final rasterized = rasterizeStrokeForClipping(
    dabs: reaching,
    canvasSize: canvasSize,
    tileSize: tileSize,
  );
  return rasterized == null
      ? null
      : clipStrokePixelsToSelection(
          pixels: rasterized.pixels,
          bounds: rasterized.bounds,
          clip: clip,
        );
}

/// A finished stroke's commit payload confined to [clip], for landing on
/// [surface] — the cel as it stands at the commit. Null when nothing of
/// the stroke survives, and the caller then commits nothing at all.
///
/// 🚨★★★PROMOTED TILES ARE THE ANSWER ONLY WHILE [surface] IS THE ONE THEY
/// WERE BLENDED AGAINST. They were masked in the pre-blend kernel, so on
/// that surface they are already clipped and pass straight through. Once
/// anything has landed on the cel in between, the commit ignores them and
/// re-derives the stroke from its dabs (`BrushStrokeCommitData`) — and
/// until this function it re-derived the WHOLE stroke there, the selection
/// forgotten: the clip had passed promoted payloads through unconditionally.
/// So a moved surface takes the same route as a stroke with no live pixels:
/// the dabs, rasterized and clipped here, and the commit composites what
/// is left — or, for stamps, each stamp clipped in its own picture
/// ([clipStampDabToSelection]) and landed 1:1.
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
  if (promoted != null && identical(data.promotedBase, surface)) {
    return promoted.isEmpty ? null : data;
  }
  if (data.sourceDabs.firstOrNull?.blurs ?? false) {
    return _blurLandedThrough(clip, data, surface);
  }
  final pixels = data.strokePixels;
  final bounds = data.strokeBounds;
  if ((pixels == null || bounds == null) &&
      data.sourceDabs.every((dab) => dab.stamp != null)) {
    final stamps = [
      for (final dab in data.sourceDabs)
        ?clipStampDabToSelection(dab, clip: clip),
    ];
    return stamps.isEmpty
        ? null
        : BrushStrokeCommitData(
            sourceDabs: stamps,
            blendMode: data.blendMode,
            strokeOpacity: data.strokeOpacity,
          );
  }
  final clipped = pixels == null || bounds == null
      ? clipDabsToSelection(
          dabs: data.sourceDabs,
          canvasSize: surface.canvasSize,
          tileSize: surface.tileSize,
          clip: clip,
        )
      : clipStrokePixelsToSelection(
          pixels: pixels,
          bounds: bounds,
          clip: clip,
        );
  if (clipped == null) {
    return null;
  }
  return BrushStrokeCommitData(
    sourceDabs: data.sourceDabs,
    strokePixels: clipped.pixels,
    strokeBounds: clipped.bounds,
    blendMode: data.blendMode,
    strokeOpacity: data.strokeOpacity,
    end: data.end,
  );
}

/// I-75: a blur has no stroke buffer to cut — it is laid again here,
/// through [clip], as tiles of this very [surface], which the commit
/// then installs as it installs a promotion.
BrushStrokeCommitData? _blurLandedThrough(
  SelectionClip clip,
  BrushStrokeCommitData data,
  BitmapSurface surface,
) {
  final tiles = strokeLandedOn(
    surface,
    BrushDabSequence(data.sourceDabs, data.strokeOpacity),
    selection: clip,
  );
  return tiles.isEmpty
      ? null
      : BrushStrokeCommitData(
          sourceDabs: data.sourceDabs,
          blendMode: data.blendMode,
          strokeOpacity: data.strokeOpacity,
          promotedBase: surface,
          promotedTiles: tiles,
          end: data.end,
        );
}
