import 'dart:typed_data';

import '../models/brush_dab.dart';
import '../models/brush_stamp_image.dart';
import '../models/dirty_region.dart';
import 'brush_stroke_blend.dart';
import 'selection_clip.dart';

/// A stroke rasterized and CLIPPED to the live selection (R26 #18: "선택
/// 하고 그리면 선택 내부만 그려진다"), ready to ride the ordinary
/// prerasterized-commit route.
class ClippedStrokePixels {
  const ClippedStrokePixels({required this.pixels, required this.bounds});

  final Uint8List pixels;
  final DirtyRegion bounds;
}

/// Confines a stroke buffer to [clip] — [applySelectionMaskToStrokeAlpha]
/// over its coverage, which is the ONE selection rule the live pre-blend
/// kernel also runs.
///
/// This is the FALLBACK half of R26 #18 now. A stroke drawn with a live
/// raster carries the selection through the pre-blend kernel instead
/// (`BrushLiveStrokeRasterizer.selectionClip`), so its promoted tiles
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
  required SelectionClip clip,
}) {
  final width = bounds.width;
  final height = bounds.height;
  if (width <= 0 || height <= 0) {
    return null;
  }
  final mask = clip.maskFor(
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
  required SelectionClip clip,
}) {
  final stamp = dab.stamp!;
  final landing = stamp.landingRect(dab.center);
  if (!clip.mayCover(landing)) {
    return null;
  }
  final window = clip.maskFor(
    left: landing.left,
    top: landing.top,
    width: stamp.width,
    height: stamp.height,
  );
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
