
import '../models/tiles_covering.dart';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/bitmap_surface.dart';
import '../models/brush_blend_mode.dart';
import '../models/separable_blend_mode.dart';
import '../models/dirty_region.dart';
import 'brush_stamp_span_kernel.dart';

/// BB-1 (R26 #9): the stroke-level blend kernel.
///
/// A brush blend applies ONCE per stroke: the live rasterizer's
/// straight-alpha stroke buffer blends against the cel's pixels within
/// the stroke bounds, and the RESULT lands through the ordinary stamp
/// kernels (an erase-rect pass then a source-over pass — see
/// `compositeStrokePixelsOntoBitmapSurface`). Never dab-by-dab:
/// overlapping dabs inside one stroke must not double-apply the mode.
///
/// Math: the W3C/Skia separable-blend equation on straight alpha —
///   αo = αs + αd(1-αs)
///   Co = [ αs(1-αd)Cs + αd(1-αs)Cd + αs·αd·B(Cs,Cd) ] / αo
/// in doubles per channel (softLight needs floats anyway; this is a
/// one-shot pen-up pass over stroke bounds, not a per-frame path). The
/// live overlay runs the SAME math per dirty tile (R27 #4,
/// [preBlendStrokeOverlayPixels]) — live and committed pixels are one
/// set of bytes, no GPU approximation anywhere.
///
/// Untouched pixels stay BYTE-EXACT: source alpha 0 copies the
/// destination verbatim (the erase-rect landing pass covers the whole
/// bounds, so any drift here would corrupt pixels the stroke never
/// touched).

/// The surface's straight-RGBA pixels within [bounds], BOUNDS-LOCAL
/// (row-major, stride = bounds width). Missing tiles read transparent.
Uint8List bitmapSurfaceRegionPixels(BitmapSurface surface, DirtyRegion bounds) {
  final width = bounds.rightExclusive - bounds.left;
  final height = bounds.bottomExclusive - bounds.top;
  final region = Uint8List(width * height * 4);
  if (width <= 0 || height <= 0) {
    return region;
  }
  final tileSize = surface.tileSize;
  for (final covered in tilesCovering(surface, bounds)) {
    final worldLeft = covered.worldLeft;
    final worldTop = covered.worldTop;
    final copyLeft = covered.left;
    final copyTop = covered.top;
    final copyRight = covered.rightExclusive;
    final copyBottom = covered.bottomExclusive;
    final rowBytes = (copyRight - copyLeft) * 4;
    // Inside readPixels: the tile is the receiver, so its buffer cannot
    // be finalized out from under these reads (see BitmapTile.readPixels —
    // the live rasterizer's copy of this exact loop, `_copyBaseRectInto`,
    // is where that bug was caught).
    covered.tile.readPixels((_, tilePixels) {
      for (var y = copyTop; y < copyBottom; y += 1) {
        final srcOffset =
            ((y - worldTop) * tileSize + (copyLeft - worldLeft)) * 4;
        final dstOffset =
            ((y - bounds.top) * width + (copyLeft - bounds.left)) * 4;
        region.setRange(dstOffset, dstOffset + rowBytes, tilePixels, srcOffset);
      }
    });
  }
  return region;
}

/// THE selection rule (R26 #18): scales a straight-alpha stroke buffer's
/// ALPHA by [mask]'s coverage, in place.
///
/// Every path that confines a stroke to a selection goes through this —
/// the live pre-blend's Dart route, the commit's clip for strokes with no
/// live raster, and a fill's stamp bytes — and the C kernel's
/// `qa_mask_alpha` is a transcription of it. One rule, one rounding
/// (Skia's mul-div-255), so the preview, the committed pixels and a redo
/// cannot disagree about where the selection ends. Three separate rules
/// is what this replaced, and they only agreed by accident: while masks
/// are binary, "zero the texel" and "scale alpha by 0" are the same
/// thing; the moment a mask goes soft (the selection tool's feather / AA
/// knobs) they stop being.
///
/// RGB is left alone deliberately. Alpha 0 is the documented "the
/// destination survives untouched" input of every commit kernel — none
/// of them read colour behind it — and premultiplying for display zeroes
/// those bytes anyway.
/// The stroke's own OPACITY as a coverage byte — the channel a selection
/// mask already speaks.
///
/// 🚨★F-12 (유저 2026-08-24): 「포토샵이나 다른 프로툴의 경우 불투명도 낮추면
/// 스트로크동안 dab이 겹친다고 해도 **해당 불투명도 이상으로 안 진해지지
/// 않나?** 지금 우리는 … **겹치면 100%만큼 진해지는거같은데**」.
///
/// The professional law: FLOW is what one dab lays, OPACITY is the ceiling
/// the whole stroke may reach. Ours multiplied both into every dab, so
/// overlapping dabs converged on 1 whatever the setting said.
///
/// ★It is a MASK WITH NO SHAPE, and that is the whole implementation. The
/// selection round already had to solve "one factor on the ACCUMULATED
/// stroke, never per dab" — masking dabs individually breaks soft edges
/// because `srcOver(a₁·m, a₂·m) ≠ srcOver(a₁, a₂)·m` — and this is the same
/// problem with a constant. So the opacity is folded INTO the mask bytes
/// and every kernel downstream, C included, needs no change at all.
int strokeOpacityCoverage(double opacity) =>
    (opacity.clamp(0.0, 1.0) * 255).round();

/// [selection] with [opacity] folded in, or a uniform mask when there is no
/// selection — null when there is nothing to scale at all.
///
/// ⚠️Folded into the MASK rather than applied as a second pass, because the
/// native kernel takes exactly one mask: `mul255(a, mul255(m, o))` is what
/// C computes, so Dart has to compute it the same way round or the two
/// drift by a byte at soft edges.
Uint8List? strokeCoverageMask({
  Uint8List? selection,
  required int pixelCount,
  required double opacity,
}) {
  final uniform = strokeOpacityCoverage(opacity);
  if (uniform >= 255) {
    return selection;
  }
  if (selection == null) {
    return Uint8List(pixelCount)..fillRange(0, pixelCount, uniform);
  }
  final folded = Uint8List(pixelCount);
  for (var i = 0; i < pixelCount; i += 1) {
    final coverage = selection[i];
    if (coverage == 0) {
      continue;
    }
    final product = coverage * uniform + 128;
    folded[i] = (product + (product >> 8)) >> 8;
  }
  return folded;
}

void applySelectionMaskToStrokeAlpha({
  required Uint8List pixels,
  required Uint8List mask,
  required int pixelCount,
}) {
  for (var i = 0; i < pixelCount; i += 1) {
    final coverage = mask[i];
    if (coverage == 255) {
      continue;
    }
    final offset = i * 4 + 3;
    final alpha = pixels[offset];
    if (coverage == 0 || alpha == 0) {
      pixels[offset] = 0;
      continue;
    }
    final product = alpha * coverage + 128;
    pixels[offset] = (product + (product >> 8)) >> 8;
  }
}

/// The C-side `QA_STROKE_BLEND_*` id for [mode] (BB-N1, ABI 22) — a fixed
/// FFI contract; both tables MUST stay in lockstep. color/erase never
/// reach the blend kernel (they ride the ordinary stamp path).
int strokeBlendModeNativeId(BrushBlendMode mode) {
  return switch (mode) {
    // ⛔`behind` is the one id that is NOT separable — it is a porter-duff
    // head with a place in the kernel's table, so it states its own number.
    BrushBlendMode.behind => 0,
    BrushBlendMode.color || BrushBlendMode.erase => throw ArgumentError.value(
      mode,
      'mode',
      'color/erase land through the ordinary stamp kernels',
    ),
    _ => separableBlendModeNativeId(mode.separable!),
  };
}

/// The same fixed ids, asked of the SEPARABLE vocabulary directly.
///
/// 🚨★★★ONE TABLE, TWO DOORS (v33). The dab kernel's DUAL MASK combines two
/// coverages through the very same `qa_stroke_blend_channel` the stroke
/// kernel reads, so it needs the very same ids — and a second switch
/// spelling them out would be a copy the moment either one gained a mode.
/// [strokeBlendModeNativeId] is now this plus the two porter-duff answers
/// its own callers need.
int separableBlendModeNativeId(SeparableBlendMode mode) {
  return switch (mode) {
    SeparableBlendMode.add => 1,
    SeparableBlendMode.darken => 2,
    SeparableBlendMode.multiply => 3,
    SeparableBlendMode.colorBurn => 4,
    SeparableBlendMode.lighten => 5,
    SeparableBlendMode.screen => 6,
    SeparableBlendMode.colorDodge => 7,
    SeparableBlendMode.overlay => 8,
    SeparableBlendMode.softLight => 9,
    SeparableBlendMode.hardLight => 10,
    SeparableBlendMode.difference => 11,
    SeparableBlendMode.exclusion => 12,
  };
}

/// The separable B(Cs, Cd) table, in doubles.
///
/// 🚨★★★PUBLIC SINCE v33 — the dab kernel's DUAL MASK combines two
/// COVERAGES through this very table. A second transcription would be a
/// copy of the only thing in the app that has to agree with
/// `qa_stroke_blend_channel` byte for byte.
///
/// ⚠️It takes a [BrushBlendMode] because that is what its first caller
/// speaks; a separable-only caller passes `mode.blendMode` — no, it passes
/// the [BrushBlendMode] of the same name, which `SeparableBlendMode` and
/// `BrushBlendMode` share by construction ([BrushBlendMode.separable]).
double blendSeparableChannel(SeparableBlendMode mode, double cs, double cd) {
  switch (mode) {
    case SeparableBlendMode.darken:
      return math.min(cs, cd);
    case SeparableBlendMode.multiply:
      return cs * cd;
    case SeparableBlendMode.colorBurn:
      if (cd >= 1) {
        return 1;
      }
      if (cs <= 0) {
        return 0;
      }
      return 1 - math.min(1, (1 - cd) / cs);
    case SeparableBlendMode.lighten:
      return math.max(cs, cd);
    case SeparableBlendMode.screen:
      return cs + cd - cs * cd;
    case SeparableBlendMode.colorDodge:
      if (cd <= 0) {
        return 0;
      }
      if (cs >= 1) {
        return 1;
      }
      return math.min(1, cd / (1 - cs));
    case SeparableBlendMode.overlay:
      return blendSeparableChannel(SeparableBlendMode.hardLight, cd, cs);
    case SeparableBlendMode.softLight:
      if (cs <= 0.5) {
        return cd - (1 - 2 * cs) * cd * (1 - cd);
      }
      final d = cd <= 0.25
          ? ((16 * cd - 12) * cd + 4) * cd
          : math.sqrt(cd);
      return cd + (2 * cs - 1) * (d - cd);
    case SeparableBlendMode.hardLight:
      // multiply(2cs, cd) below the pivot, screen(2cs-1, cd) above.
      return cs <= 0.5
          ? 2 * cs * cd
          : (2 * cs - 1) + cd - (2 * cs - 1) * cd;
    case SeparableBlendMode.difference:
      return (cs - cd).abs();
    case SeparableBlendMode.exclusion:
      return cs + cd - 2 * cs * cd;
    case SeparableBlendMode.add:
      // ⛔ADD HAS NO B(Cs, Cd), and refusing is what keeps that visible.
      // Skia's `plus` is a saturating add of PREMULTIPLIED colour, so the
      // stroke kernel answers it before reaching this table and the dual
      // mask answers it in [blendDualCoverage]. An arm here that returned
      // "something reasonable" would be a third definition of 加算 that
      // agrees with neither.
      throw ArgumentError.value(
        mode,
        'mode',
        'add is a premultiplied saturating add, not a channel blend — see '
            'blendDualCoverage / the stroke kernel',
      );
  }
}

int _clampByte(double value) {
  final rounded = (value * 255).round();
  return rounded < 0 ? 0 : (rounded > 255 ? 255 : rounded);
}

/// R27 #4: the live overlay's PRE-BLEND — the exact bytes the pen-up
/// commit will land for the region, computed the moment the tile shows.
///
/// The GPU preview approximated non-plain modes within ±1/255 because it
/// re-derived the blend in float; the user's rule is ZERO drift in every
/// mode. So the overlay stops handing the GPU anything to blend: this
/// runs the SAME per-pixel math the commit runs — [blendStrokeRegionPixels]
/// for the kernel modes, and for color/erase the stamp blitter ITSELF
/// ([BrushStampBlitter]) at opacity 1, because that landing IS one
/// stamp of the stroke buffer (see
/// `compositeStrokePixelsOntoBitmapSurface`).
/// The result draws as a plain REPLACEMENT tile, so pen-up cannot move a
/// byte: identical bytes flow into identical composites.
///
/// [dst]/[src] are BOUNDS-LOCAL straight RGBA; [erase] covers both the
/// eraser tool and the 소거 blend mode (the tool locks the mode, so the
/// two arrive together). [BrushBlendMode.color] is that same stamp
/// blitter's srcOver at opacity 1 (the color landing is one stamp of the
/// stroke buffer) — every stroke mode pre-blends now (user rule 07-23:
/// ONE display pipeline, live == commit unconditionally).
/// [mask] (R28 selection): 1 byte of coverage per pixel, scaling the
/// STROKE's alpha before the composite — `a = mul255(a, mask)`, the same
/// rounding the kernel uses. Null means no selection and is byte-for-byte
/// the pre-mask path. It applies to the ACCUMULATED stroke, never per
/// dab: masking dabs individually would break soft masks, because
/// srcOver(a₁·m, a₂·m) ≠ srcOver(a₁, a₂)·m.
Uint8List preBlendStrokeOverlayPixels({
  required Uint8List dst,
  required Uint8List src,
  required BrushBlendMode mode,
  required bool erase,
  required int pixelCount,
  Uint8List? mask,
}) {
  if (mask != null) {
    // One masked copy up front keeps the kernels below untouched — they
    // are the commit's own code and must stay byte-identical to it.
    final masked = Uint8List.fromList(src);
    applySelectionMaskToStrokeAlpha(
      pixels: masked,
      mask: mask,
      pixelCount: pixelCount,
    );
    src = masked;
  }
  final stampErase = erase || mode == BrushBlendMode.erase;
  if (stampErase || mode == BrushBlendMode.color) {
    // The color/erase landing IS one stamp of the stroke buffer at
    // opacity 1, so this runs THE stamp blitter rather than a hand-kept
    // mirror of it: sa==0 leaves the pixel verbatim (junk alpha==0 RGB
    // included, exactly like the commit's skip), sa==255 copies or zeroes
    // it byte-hard, and the general case runs the same double expressions
    // in the same order — because it is the same code. The parity test
    // pins the result against the real commit, native kernel included.
    //
    // The blitter writes IN PLACE, over the destination the commit is
    // about to change. Here the caller wants a fresh buffer instead (the
    // live rasterizer diffs the result against `dst` to decide whether
    // the tile moved), so a copy of `dst` is what it blends into.
    final result = Uint8List.fromList(dst);
    BrushStampBlitter(
      rgba: src,
      dabOpacity: 1.0,
      erase: stampErase,
    ).blendSpanInPlace(result, 0, 0, pixelCount);
    return result;
  }
  final result = blendStrokeRegionPixels(
    dst: dst,
    src: src,
    mode: mode,
    pixelCount: pixelCount,
  );
  // Mirror the LANDING normalization: the commit lands the kernel result
  // through an erase-clear + srcOver stamp, whose srcOver skips α==0
  // pixels — a fully transparent result pixel therefore lands as
  // (0,0,0,0) whatever RGB the kernel's verbatim-copy rule carried (the
  // native kernel mirrors the same rule). Without this the straight
  // bytes differ where the base held α==0 junk RGB, even though both
  // display identically after premultiply.
  for (var i = 0; i < pixelCount; i += 1) {
    final o = i * 4;
    if (result[o + 3] == 0) {
      result[o] = 0;
      result[o + 1] = 0;
      result[o + 2] = 0;
    }
  }
  return result;
}

/// Blends the stroke buffer [src] against the cel region [dst] (both
/// BOUNDS-LOCAL straight RGBA of [pixelCount] pixels) through [mode],
/// returning the RESULT region the landing pass writes verbatim.
Uint8List blendStrokeRegionPixels({
  required Uint8List dst,
  required Uint8List src,
  required BrushBlendMode mode,
  required int pixelCount,
}) {
  assert(mode != BrushBlendMode.color && mode != BrushBlendMode.erase,
      'color/erase land through the ordinary stamp kernels');
  final result = Uint8List(pixelCount * 4);
  for (var i = 0; i < pixelCount; i += 1) {
    final o = i * 4;
    final sa = src[o + 3];
    if (sa == 0) {
      result[o] = dst[o];
      result[o + 1] = dst[o + 1];
      result[o + 2] = dst[o + 2];
      result[o + 3] = dst[o + 3];
      continue;
    }
    final da = dst[o + 3];
    if (mode == BrushBlendMode.behind) {
      if (da == 255) {
        result[o] = dst[o];
        result[o + 1] = dst[o + 1];
        result[o + 2] = dst[o + 2];
        result[o + 3] = 255;
        continue;
      }
      if (da == 0) {
        result[o] = src[o];
        result[o + 1] = src[o + 1];
        result[o + 2] = src[o + 2];
        result[o + 3] = sa;
        continue;
      }
      // destination-over on straight alpha.
      final as_ = sa / 255.0;
      final ad = da / 255.0;
      final ao = ad + as_ * (1 - ad);
      for (var c = 0; c < 3; c += 1) {
        result[o + c] = _clampByte(
          (ad * dst[o + c] / 255.0 + (1 - ad) * as_ * src[o + c] / 255.0) / ao,
        );
      }
      result[o + 3] = _clampByte(ao);
      continue;
    }
    if (da == 0) {
      result[o] = src[o];
      result[o + 1] = src[o + 1];
      result[o + 2] = src[o + 2];
      result[o + 3] = sa;
      continue;
    }
    final as_ = sa / 255.0;
    final ad = da / 255.0;
    if (mode == BrushBlendMode.add) {
      // Skia plus: saturating premultiplied add.
      final ao = math.min(1.0, as_ + ad);
      for (var c = 0; c < 3; c += 1) {
        final premul = math.min(
          1.0,
          src[o + c] / 255.0 * as_ + dst[o + c] / 255.0 * ad,
        );
        result[o + c] = _clampByte(premul / ao);
      }
      result[o + 3] = _clampByte(ao);
      continue;
    }
    final ao = as_ + ad * (1 - as_);
    for (var c = 0; c < 3; c += 1) {
      final cs = src[o + c] / 255.0;
      final cd = dst[o + c] / 255.0;
      final b = blendSeparableChannel(mode.separable!, cs, cd);
      result[o + c] = _clampByte(
        (as_ * (1 - ad) * cs + ad * (1 - as_) * cd + as_ * ad * b) / ao,
      );
    }
    result[o + 3] = _clampByte(ao);
  }
  return result;
}

/// How the DUAL mask combines with the coverage under it (v33).
///
/// [dual] is the SOURCE, [coverage] the destination — the dual tip is the
/// second tip applied over the first. ⚠️Multiply is commutative so nothing
/// that exists today can tell the order apart; the non-commutative modes
/// are REASONED, not measured, and want a side-by-side against Clip Studio
/// before anything is built on them.
///
/// ⛔ADD IS NOT IN THE B(Cs, Cd) TABLE. Skia's `plus` is a saturating add of
/// PREMULTIPLIED colour, which is why the stroke kernel answers it before
/// [blendSeparableChannel] is reached; on a single coverage that same
/// operation is `min(1, cs + cd)`. Clip Studio's 合成モード index 12 is 加算,
/// so this arm is one of the two modes actually found in the user's files —
/// not a hypothetical.
///
/// 🚨The C mirror is `qa_dual_combine`, and the parity suite pins the pair.
double blendDualCoverage(
  SeparableBlendMode mode,
  double dual,
  double coverage,
) {
  if (mode == SeparableBlendMode.add) {
    final sum = dual + coverage;
    return sum > 1.0 ? 1.0 : sum;
  }
  return blendSeparableChannel(mode, dual, coverage);
}
