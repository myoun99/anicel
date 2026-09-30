import 'dart:typed_data';

import '../models/bitmap_surface.dart';
import '../models/brush_dab.dart';
import '../models/brush_dab_sequence.dart';
import '../models/brush_stamp_image.dart';
import '../models/canvas_size.dart';
import '../models/dirty_region.dart';
import 'bitmap_surface_brush_commit.dart';
import 'brush_dab_dirty_region.dart';
import 'brush_stroke_blend.dart';
import 'brush_stroke_commit_data.dart';
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

/// 🚨★★★A STAMP CLIPS IN ITS OWN PICTURE (board
/// `a-stamp-rounds-twice-inside-a-selection`, 2026-09-28). A stamp — a fill,
/// a shape fill, a pasted or stamped piece — lands 1:1: its picture's alpha
/// times the dab's opacity, rounded once where it falls. A selection over it
/// is folded into that PICTURE by the one selection rule
/// ([applySelectionMaskToStrokeAlpha]), and the stamp then lands 1:1 as it
/// would anyway — so wherever the selection covers it wholly it lands the
/// bytes it lands with no selection at all (절대명령 2: 선택이 있든 없든 같은
/// 코드가 답한다).
///
/// ↩️It was rasterized onto an empty surface like a brush stroke first —
/// its alpha rounded there, at the dab's opacity — then clipped and
/// composited: a second rounding, and a stamp under 100% landed a level
/// apart inside a selection and out of one.
///
/// Null when nothing of it survives: out of the selection's reach, or
/// masked away entirely.
BrushDab? clipStampDabToSelection(
  BrushDab dab, {
  required CanvasSelectionRegion region,
}) {
  final stamp = dab.stamp!;
  final landing = stamp.landingRect(dab.center);
  if (!region.mayCover(landing)) {
    return null;
  }
  return _stampThroughWindow(
    dab,
    region.maskFor(
      left: landing.left,
      top: landing.top,
      width: stamp.width,
      height: stamp.height,
    ),
  );
}

/// [dab]'s stamp through a selection mask rasterized ALREADY — [mask]
/// covering [box], nothing selected outside it — which is how the PIXEL
/// verbs read a selection: once over its own box, at its 확장·페더·AA
/// (`buildSelectionMask`; 유저 2026-09-09 「선택의 aa 따르게」).
///
/// ⛔The same fold as [clipStampDabToSelection], from a different mask: a
/// soft mask must be read off the selection's OWN box, because its passes
/// read neighbours and a box cut to the stamp would ramp against its own
/// edge. Which one a caller hands in is the reading its verb has; what the
/// stamp does with it is this one rule.
///
/// Null when nothing of it survives.
BrushDab? clipStampDabToSelectionMask(
  BrushDab dab, {
  required Uint8List mask,
  required ({int left, int top, int width, int height}) box,
}) {
  final stamp = dab.stamp!;
  final landing = stamp.landingRect(dab.center);
  final window = Uint8List(stamp.width * stamp.height);
  final left = landing.left > box.left ? landing.left : box.left;
  final right = landing.rightExclusive < box.left + box.width
      ? landing.rightExclusive
      : box.left + box.width;
  final top = landing.top > box.top ? landing.top : box.top;
  final bottom = landing.bottomExclusive < box.top + box.height
      ? landing.bottomExclusive
      : box.top + box.height;
  if (right <= left || bottom <= top) {
    return null;
  }
  for (var y = top; y < bottom; y += 1) {
    final from = (y - box.top) * box.width + (left - box.left);
    final to = (y - landing.top) * stamp.width + (left - landing.left);
    window.setRange(to, to + (right - left), mask, from);
  }
  return _stampThroughWindow(dab, window);
}

/// [dab]'s stamp with [window] — one mask byte per stamp pixel — folded
/// into its alpha ([applySelectionMaskToStrokeAlpha]); null when nothing
/// is left.
BrushDab? _stampThroughWindow(BrushDab dab, Uint8List window) {
  final stamp = dab.stamp!;
  final rgba = Uint8List.fromList(stamp.rgba);
  applySelectionMaskToStrokeAlpha(
    pixels: rgba,
    mask: window,
    pixelCount: stamp.width * stamp.height,
  );
  for (var alpha = 3; alpha < rgba.length; alpha += 4) {
    if (rgba[alpha] != 0) {
      return dab.copyWith(
        stamp: BrushStampImage(
          id: '${stamp.id}-in-selection',
          width: stamp.width,
          height: stamp.height,
          rgba: rgba,
        ),
      );
    }
  }
  return null;
}

/// [dabs] rasterized ([rasterizeStrokeForClipping]) and clipped to
/// [region] ([clipStrokePixelsToSelection]) — the whole of what a stroke
/// of brush dabs that arrives without live pixels goes through before the
/// commit: the canvas panel's commit funnel runs it for programmatic
/// strokes and history redos. A stamp takes [clipStampDabToSelection]
/// instead.
///
/// Null when the stroke draws nothing, or nothing of it survives the
/// selection.
///
/// Dabs the selection cannot reach are left out before anything is
/// rasterized — the live rasterizer's rule ([CanvasSelectionRegion.mayCover]),
/// for the same reason: the mask would zero every pixel they add.
ClippedStrokePixels? clipDabsToSelection({
  required List<BrushDab> dabs,
  required CanvasSize canvasSize,
  required int tileSize,
  required CanvasSelectionRegion region,
}) {
  final reaching = [
    for (final dab in dabs)
      if (dirtyRegionForBrushDab(dab) case final reach?)
        if (region.mayCover(reach)) dab,
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
          region: region,
        );
}

/// A finished stroke's commit payload confined to [region], for landing on
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
  required CanvasSelectionRegion region,
  required BitmapSurface surface,
}) {
  final promoted = data.promotedTiles;
  if (promoted != null && identical(data.promotedBase, surface)) {
    return promoted.isEmpty ? null : data;
  }
  final pixels = data.strokePixels;
  final bounds = data.strokeBounds;
  if ((pixels == null || bounds == null) &&
      data.sourceDabs.every((dab) => dab.stamp != null)) {
    final stamps = [
      for (final dab in data.sourceDabs)
        ?clipStampDabToSelection(dab, region: region),
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
          region: region,
        )
      : clipStrokePixelsToSelection(
          pixels: pixels,
          bounds: bounds,
          region: region,
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
  );
}
