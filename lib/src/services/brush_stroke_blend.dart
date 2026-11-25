
import '../models/tiles_covering.dart';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/brush_blend_mode.dart';
import '../models/brush_dab.dart' show BrushDualView;
import '../models/non_separable_blend_mode.dart';
import '../models/separable_blend_mode.dart';
import '../models/brush_texture_mode.dart';
import '../models/dirty_region.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuBlend;

// BB-1 (R26 #9): a brush blend applies ONCE per stroke — the stroke's
// buffer laid on the cel in its mode, never dab by dab (overlapping dabs
// inside one stroke must not double-apply the mode). The engine lays it,
// the live overlay's pre-blend and the pen-up landing alike
// (`compositeStrokePixelsOntoBitmapSurface`, blend.wgsl's `blend_laid`),
// so what shows is what lands. ↩️Till 2026-11-14 the stroke-level blend
// was written here too, in doubles (`blendStrokeRegionPixels`), with the
// overlay's pre-blend beside it (`preBlendStrokeOverlayPixels`, R27 #4) —
// for an overlay on a grid parted from its cel's, a road the app never
// took (board `the-off-engine-cpu-commit-lives-only-for-tests`).

/// The surface's straight-RGBA pixels within [bounds], BOUNDS-LOCAL
/// (row-major, stride = bounds width). Missing tiles read transparent.
Uint8List bitmapSurfaceRegionPixels(
  BitmapSurface surface,
  DirtyRegion bounds, {
  TileBytesOf bytesOf = readTilesInPlace,
}) {
  final width = bounds.rightExclusive - bounds.left;
  final height = bounds.bottomExclusive - bounds.top;
  final region = Uint8List(width * height * 4);
  if (width <= 0 || height <= 0) {
    return region;
  }
  final tileSize = surface.tileSize;
  final covering = tilesCovering(surface, bounds).toList();
  var next = 0;
  bytesOf([for (final covered in covering) covered.tile], (tilePixels) {
    final covered = covering[next];
    next += 1;
    final copyLeft = covered.left;
    final rowBytes = (covered.rightExclusive - copyLeft) * 4;
    for (var y = covered.top; y < covered.bottomExclusive; y += 1) {
      final srcOffset =
          ((y - covered.worldTop) * tileSize + (copyLeft - covered.worldLeft)) *
          4;
      final dstOffset =
          ((y - bounds.top) * width + (copyLeft - bounds.left)) * 4;
      region.setRange(dstOffset, dstOffset + rowBytes, tilePixels, srcOffset);
    }
  });
  return region;
}

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

/// [opacity] as a mask over [pixelCount] pixels — null at full opacity,
/// nothing to scale.
///
/// ↩️It folded a selection's mask in till 2026-11-14 — into the MASK, not
/// as a second pass, so that every road computed `mul255(a, mul255(m, o))`
/// — and a selection cuts on the engine alone now (`drawnByTheEngineAlone`).
Uint8List? strokeCoverageMask({
  required int pixelCount,
  required double opacity,
}) {
  final uniform = strokeOpacityCoverage(opacity);
  if (uniform >= 255) {
    return null;
  }
  return Uint8List(pixelCount)..fillRange(0, pixelCount, uniform);
}

/// THE coverage rule (R26 #18): scales a straight-alpha stroke buffer's
/// ALPHA by [mask]'s coverage, in place — the stroke's opacity ceiling
/// (F-12) on a stroke handed over as a buffer, which the commit's buffer
/// goes through, so the committed pixels and a redo round it the same
/// (Skia's mul-div-255). ↩️The overlay's Dart pre-blend went through it
/// too till 2026-11-14.
///
/// ↩️It was THE selection rule till 2026-11-14: every path that confined
/// a stroke to a selection went through it — the live pre-blend, the
/// commit's buffer, a fill's stamp bytes — where three rules had agreed
/// only while masks were binary ("zero the texel" and "scale alpha by 0"
/// part the moment a mask goes soft). A selection cuts on the engine
/// alone now (`drawnByTheEngineAlone`).
///
/// RGB is left alone deliberately. Alpha 0 is the documented "the
/// destination survives untouched" input of every commit kernel — none
/// of them read colour behind it — and premultiplying for display zeroes
/// those bytes anyway.
void applyCoverageToStrokeAlpha({
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

/// The blend the engine lands a stroke's picture in — the eraser's where
/// [erase], the plain one for a brush that only paints.
int engineBlendModeOf(BrushBlendMode mode, {required bool erase}) {
  if (erase || mode == BrushBlendMode.erase) {
    return GpuBlend.erase;
  }
  return mode == BrushBlendMode.color
      ? GpuBlend.normal
      : strokeBlendModeNativeId(mode);
}

/// The engine's blend id for [mode] (`BLEND_*`, blend.wgsl) — a fixed
/// contract; both tables MUST stay in lockstep. color/erase have no place
/// in the table: [engineBlendModeOf] names theirs. ↩️The ids were the C
/// stroke kernel's (`QA_STROKE_BLEND_*`, BB-N1, ABI 22), which went with
/// the C on 2026-11-12.
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
    _ => switch (mode.separable) {
      final separable? => separableBlendModeNativeId(separable),
      null => nonSeparableBlendModeNativeId(mode.nonSeparable!),
    },
  };
}

/// The same fixed ids, asked of the SEPARABLE vocabulary directly.
///
/// 🚨★★★ONE TABLE, TWO DOORS (v33). The dab kernel's DUAL MASK combines two
/// coverages through the very same B table the stroke blend reads
/// ([blendSeparableChannel]), so it needs the very same ids — and a second
/// switch spelling them out would be a copy the moment either one gained a
/// mode.
/// [strokeBlendModeNativeId] is now this and [nonSeparableBlendModeNativeId]
/// plus the two porter-duff answers its own callers need.
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
    SeparableBlendMode.linearBurn => 13,
    SeparableBlendMode.subtract => 14,
    SeparableBlendMode.vividLight => 15,
    SeparableBlendMode.linearLight => 16,
    SeparableBlendMode.pinLight => 17,
    SeparableBlendMode.hardMix => 18,
    SeparableBlendMode.divide => 19,
    SeparableBlendMode.glowDodge => 26,
    SeparableBlendMode.glowAdd => 27,
  };
}

/// The same fixed ids for the six that mix the three channels, which have
/// no separable row; they follow the separable table's (brush-fidelity).
///
/// ↩️Spelled inside [strokeBlendModeNativeId] while only the brush had
/// them. brush-fidelity-Q4 gave the layer list two of the six, composed by
/// `shaders/layer_blend.frag` reading these very ids — so this is the
/// third door onto the one table, for the same reason the separable door
/// is the second.
int nonSeparableBlendModeNativeId(NonSeparableBlendMode mode) {
  return switch (mode) {
    NonSeparableBlendMode.darkerColor => 20,
    NonSeparableBlendMode.lighterColor => 21,
    NonSeparableBlendMode.hue => 22,
    NonSeparableBlendMode.saturation => 23,
    NonSeparableBlendMode.chroma => 24,
    NonSeparableBlendMode.luminosity => 25,
  };
}

/// The separable B(Cs, Cd) table, in doubles.
///
/// 🚨★★★PUBLIC SINCE v33 — the dab kernel's DUAL MASK combines two
/// COVERAGES through this very table, and a second transcription would be
/// a copy of it. ↩️Till 2026-11-12 the C kernel's `qa_stroke_blend_channel`
/// had to agree with it byte for byte, and went with the C; the engine's is
/// `blend_channel` (blend.wgsl).
///
/// ⚠️It takes a [BrushBlendMode] because that is what its first caller
/// speaks; a separable-only caller passes `mode.blendMode` — no, it passes
/// the [BrushBlendMode] of the same name, which `SeparableBlendMode` and
/// `BrushBlendMode` share by construction ([BrushBlendMode.separable]).
///
/// A mode that [SeparableBlendMode.glows] has the B of the mode it glows:
/// what differs is what its composite hands in (blend.wgsl).
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
    case SeparableBlendMode.colorDodge || SeparableBlendMode.glowDodge:
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
    case SeparableBlendMode.linearBurn:
      final sum = cs + cd - 1;
      return sum > 0 ? sum : 0.0;
    case SeparableBlendMode.subtract:
      final rest = cd - cs;
      return rest > 0 ? rest : 0.0;
    case SeparableBlendMode.vividLight:
      // colorBurn(2cs, cd) below the pivot, colorDodge(2cs-1, cd) above —
      // hardLight's split with the two dodge/burn heads in place of
      // multiply/screen.
      return cs <= 0.5
          ? blendSeparableChannel(SeparableBlendMode.colorBurn, 2 * cs, cd)
          : blendSeparableChannel(
              SeparableBlendMode.colorDodge,
              2 * cs - 1,
              cd,
            );
    case SeparableBlendMode.linearLight:
      final sum = cd + 2 * cs - 1;
      return sum < 0 ? 0.0 : (sum > 1 ? 1.0 : sum);
    case SeparableBlendMode.pinLight:
      if (cs <= 0.5) {
        final doubled = 2 * cs;
        return cd < doubled ? cd : doubled;
      }
      final raised = 2 * cs - 1;
      return cd > raised ? cd : raised;
    case SeparableBlendMode.hardMix:
      // Every channel goes all the way: white where the two reach a whole,
      // black where they fall short — on bytes, s + d >= 255. 🔬Every pair
      // of bytes summing to 255 lands on exactly 1.0 here (all 256 checked,
      // 2026-10-17), so the plain comparison is the byte rule.
      return cs + cd >= 1 ? 1.0 : 0.0;
    case SeparableBlendMode.divide:
      // The destination divided by the source. Nothing divided is nothing;
      // anything divided by nothing is as bright as a channel goes.
      if (cd <= 0) {
        return 0;
      }
      if (cs <= 0) {
        return 1;
      }
      final quotient = cd / cs;
      return quotient < 1 ? quotient : 1.0;
    case SeparableBlendMode.exclusion:
      return cs + cd - 2 * cs * cd;
    case SeparableBlendMode.add || SeparableBlendMode.glowAdd:
      // ↩️ADD HAD NO B: Skia's `plus`, a saturating add of premultiplied
      // colour, answered before this table. That is 加算(発光); Clip Studio's
      // 加算 has this B and mixes by alpha ([SeparableBlendMode.glows]).
      return math.min(1, cs + cd);
  }
}

/// The byte alpha a stroke with a second tip shows where its first plane
/// holds [firstWide] and its second [secondWide] (both alpha * 65535) —
/// the view the bytes are rebuilt through. A channel's byte is its
/// plane's, rounded (`(wide / 257).round()`), under any alpha above 0.
///
/// 🚨★★★THE SECOND TIP IS A SECOND STROKE (ABI 60; board
/// an-imported-pencil-drops-its-second-brush Q3 b, 유저 2026-10-25 「두 번째
/// 획으로 다시 만든다」). Its dabs are stamped along the same path
/// (`BrushSecondStroke`) and pile on the tile's SECOND plane (alpha *
/// 65535); the first tip's dabs pile on the 16-bit plane as any stroke's
/// do. The BYTES are the view of the two: the first plane's colour, and its
/// alpha combined with the second's through the tip's mode at its density
/// ([dualViewLevel]). Outside the first tip's ink nothing shows — a second
/// tip lays only where both lay (Photoshop's Dual Brush, and the mask brush
/// Krita draws it with lays its mask over the WHOLE stroke). A pure
/// function of the two planes, so the order the two strokes' dabs land in
/// moves no byte, and what the stroke shows as it is drawn is what it
/// lands. ↩️Until ABI 60 the second tip was a tiled mask over each dab, at
/// a random phase a dab: a grain inside each stamp, never a stroke of its
/// own.
///
/// That the tip has a mode at all is `BrushDualView`'s to say. The Dart
/// kernel and the reference both read this, and the engine's is
/// `pile.wgsl`'s. ↩️Till 2026-11-12 this text stood beside the C kernel's
/// `qa_dual_view_rows`, which went with the C.
int dualViewAlpha(int firstWide, int secondWide, BrushDualView view) {
  final alpha = dualViewLevel(firstWide / 65535.0, secondWide / 65535.0, view);
  return (alpha * 255.0).round().clamp(0, 255);
}

/// The alpha a stroke with a second tip shows where its first tip laid
/// [first] and its second [second] — [dualViewAlpha] before it is a byte,
/// and what the brush list's swatch reads, whose planes are doubles.
/// Where the first tip laid nothing, nothing shows: a second tip lays only
/// where both lay.
///
/// The second tip's coverage is the SOURCE of the blend, the first's the
/// destination — the dual tip is the second tip applied over the first.
/// ⚠️Multiply is commutative so nothing that exists today can tell the order
/// apart; the non-commutative modes are REASONED, not measured, and want a
/// side-by-side against Clip Studio before anything is built on them.
///
/// ⛔MULTIPLY KEEPS ITS OWN LINE. The general form below is
/// `lerp(a, B(s, a), d)`, which for B = multiply is the SAME NUMBER and NOT
/// THE SAME BYTES: `a * ((1-d) + d*s)` and `a*(1-d) + d*s*a` differ in the
/// last bit of a double, and the default should be the one written plainly.
double dualViewLevel(double first, double second, BrushDualView view) {
  if (first <= 0.0) {
    return 0.0;
  }
  final density = view.density;
  if (view.compositeMode == SeparableBlendMode.multiply) {
    return first * ((1.0 - density) + density * second);
  }
  final combined =
      first * (1.0 - density) +
      density * blendSeparableChannel(view.compositeMode, second, first);
  return combined > 1.0 ? 1.0 : combined;
}

/// What a dab lays where the paper stands [sample] high, under the
/// [BrushTextureMode.height] texture: its [coverage] times the [density] is
/// how deep it reaches into the paper, and it touches where the paper rises
/// above that floor — fully once the paper stands [paperHeightBand] above
/// it.
///
/// The reference reads this (`forEachBrushPixelCoverage`); the engine's is
/// `dab.wgsl`'s.
double paperHeightCoverage(double coverage, double sample, double density) {
  final touched = (sample + density * coverage - 1.0) / paperHeightBand;
  if (touched <= 0.0) {
    return 0.0;
  }
  return touched >= 1.0 ? 1.0 : touched;
}

/// How far above a dab's floor the paper must stand to take the dab fully
/// ([paperHeightCoverage]): narrow, so the dab's edge is the paper's edge —
/// a grain one texel across stays one texel, not a soft blur of it.
const double paperHeightBand = 0.25;
