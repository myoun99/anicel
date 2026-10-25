import 'dart:math' as math;
import 'dart:typed_data';

import '../core/lru.dart';
import '../models/brush_anti_alias.dart';
import '../models/brush_dab.dart';
import '../models/brush_tip_mask.dart';
import '../models/brush_tip_shape.dart';
import 'brush_dab_tip_geometry.dart';
import 'mark_under_a_pixel.dart';

/// The prerendered tip-stamp cache (R20-B — the CSP/Photoshop brush
/// architecture): every ANALYTIC tip renders ONCE per quantized parameter
/// set into a raster coverage mask, and dabs are REWRITTEN at generation
/// time to consume that mask as an unrotated [BrushTipMask].
///
/// Why this shape:
///  - Rotation is baked into the mask (1° steps), so every dab —
///    including direction-following rotated raster tips, previously the
///    slow per-pixel-rotation path — rides the fast unrotated-lattice
///    path in the rasterizers AND the C kernel, with NO engine changes.
///    ↩️Not raster tips any more — see below.
///  - Subpixel placement needs no phase quantization: the existing
///    bilinear lattice sampling shifts the mask continuously.
///  - live == commit parity holds by construction: dabs resolve ONCE at
///    generation (the same place stroke dynamics run), and the resolved
///    dab is what the overlay rasterizer, the commit materializer, undo
///    replay and the .anicel all see.
///
/// 🚨★★★A RASTER TIP IS NOT BAKED — the kernels sample it where it is,
/// under the dab's own angle and roundness (board F-251, 2026-10-01,
/// measured). Baking one costs its SOURCE's resolution per 1° of angle: a
/// 6px dab of a 256px tip rendered 65,536 texels and uploaded 512KB, and
/// with a random or stroke-following angle nearly every dab missed — 227
/// such masks fill the whole budget — so the user's TVPaint pencil spent
/// ~3ms a dab. Sampled in place the same dab costs ~10µs, at the source's
/// full detail (one resample, not two), and keeps its CORNERS: the baked
/// mask held only the dab's axis-aligned box, so a rotated tip lost
/// whatever reached past it. ⛔Do not buy the speed back by baking at a
/// lower resolution — that was measured too, and the grain went with it.
/// 🚨★★★NOR IS A ROUND TIP, since 2026-10-25 — it is its profile
/// ([resolveDab] has why), so a square is all this still bakes.
///
/// Quantization (user-approved: stroke bytes may change vs the old
/// direct-analytic path): size 1/4 px steps up to 64 px then ~1.1%
/// log steps; hardness/roundness 1/128 steps; angle 1° steps — and none
/// for a circle, whose stamp is the same at every angle.
class BrushTipStampCache {
  BrushTipStampCache({this.byteBudget = defaultByteBudget});

  /// What a cache holds at the automatic allowance — the memory tab
  /// scales it ([CacheBudgets.brushTips]).
  static const int defaultByteBudget = 128 * 1024 * 1024;

  static final BrushTipStampCache instance = BrushTipStampCache();

  /// Resolved-mask id prefix — marks a dab as already cache-resolved
  /// (resolution is idempotent).
  static const String resolvedIdPrefix = 'tipstamp|';

  /// LRU byte budget for rendered masks. A mask costs
  /// `size² × 9` bytes resident (alpha bytes + the Float64 normalized
  /// copy the samplers read).
  int byteBudget;

  late final Lru<String, BrushTipMask> _masks = Lru(
    limit: () => byteBudget,
    costOf: _maskCost,
  );

  int get residentBytes => _masks.held;
  int get entryCount => _masks.length;

  /// Rewrites an analytic [raw] dab to the form it is laid in: a round tip
  /// quantized (below), a square to its prerendered mask with
  /// `angleDegrees: 0` and `roundness: 1`. A dab that already carries a
  /// mask — a raster tip, or one this cache resolved — and a stamp dab
  /// (lift/fill pixels) pass through untouched, but for a size under a
  /// pixel ([liftedToOnePixel] — every dab a stroke lays comes through
  /// here).
  BrushDab resolveDab(BrushDab raw) {
    final dab = liftedToOnePixel(raw);
    if (dab.stamp != null || dab.tipMask != null) {
      return dab;
    }
    final sizeQ = quantizeSizeStep(dab.size);
    final size = dequantizeSize(sizeQ);
    final hardnessQ = (dab.hardness.clamp(0.0, 1.0) * 128).round();
    if (dab.tipShape == BrushTipShape.round) {
      // 🚨★★★A ROUND TIP IS NOT BAKED — it is its profile, read along its
      // radius ([RoundTipProfile]), and its pile beside it (board
      // a-one-pixel-dab-drops-out-by-where-it-lies Q4, 2026-10-25): a stamp
      // a texel a pixel, sampled bilinearly, blurred the profile a second
      // time (measured there). What it is quantized by is what keys its
      // profile; its roundness and angle turn the pixel into its space and
      // are left as they are.
      final hardness = hardnessQ / 128.0;
      return size == dab.size && hardness == dab.hardness
          ? dab
          : dab.copyWith(size: size, hardness: hardness);
    }
    final roundnessQ = (dab.roundness.clamp(0.0, 1.0) * 128).round().clamp(
      1,
      128,
    );
    final angleQ = ((dab.angleDegrees.round() % 360) + 360) % 360;
    final key =
        '${resolvedIdPrefix}analytic:${dab.tipShape.name}'
        '|$sizeQ|$hardnessQ|$roundnessQ|$angleQ';

    final mask = _masks.resolve(
      key,
      () => _render(
        key: key,
        tipShape: dab.tipShape,
        size: size,
        hardness: hardnessQ / 128.0,
        roundness: roundnessQ / 128.0,
        angleDegrees: angleQ.toDouble(),
      ),
    );

    return dab.copyWith(
      size: size,
      tipMask: mask,
      angleDegrees: 0.0,
      roundness: 1.0,
    );
  }

  List<BrushDab> resolveDabs(List<BrushDab> dabs) {
    if (dabs.isEmpty) {
      return dabs;
    }
    return [for (final dab in dabs) resolveDab(dab)];
  }

  static int _maskCost(BrushTipMask mask) => mask.size * mask.size * 9;

  /// Size quantizer: 1/4 px steps up to 64 px, then ~1.1% relative log
  /// steps — fine enough that pressure-driven size curves stay smooth,
  /// coarse enough that a stroke reuses a handful of masks.
  static int quantizeSizeStep(double size) {
    final clamped = size.clamp(0.25, 1e6);
    if (clamped <= 64.0) {
      return (clamped * 4).round().clamp(1, 256);
    }
    return 256 + (64.0 * (math.log(clamped / 64.0) / math.ln2)).round();
  }

  static double dequantizeSize(int step) {
    if (step <= 256) {
      return step / 4.0;
    }
    return 64.0 * math.pow(2.0, (step - 256) / 64.0).toDouble();
  }

  /// Renders one cache mask: texel (i, j) carries the coverage today's
  /// per-pixel path would compute at the canvas offset the consumer's
  /// sampler maps that texel to — so consuming the mask through the
  /// existing unrotated bilinear samplers reproduces the tip, with
  /// rotation/roundness/hardness baked in.
  BrushTipMask _render({
    required String key,
    required BrushTipShape tipShape,
    required double size,
    required double hardness,
    required double roundness,
    required double angleDegrees,
  }) {
    final radius = size / 2.0;
    // ≈1 texel per canvas pixel, CAPPED for huge brushes (R21): a 1000px
    // tip at full resolution meant a ~1M-texel render (plus an 8MB
    // Float64 table and an 8MB engine upload) PER cache miss, on the UI
    // thread, and pressure-driven size sweeps miss constantly — the
    // reported 8K/1000px stall. Above the cap the bilinear lattice
    // upsamples the mask; an analytic tip's edge softens by at most
    // ~radius/cap pixels (≈2px at 1000px — the CSP/PS big-brush
    // contract).
    final maskSize = (size.ceil() + 2).clamp(4, 256);

    final tip = brushTipGeometry((
      size: radius * 2.0,
      hardness: hardness,
      roundness: roundness,
      angleDegrees: angleDegrees,
      tipShape: tipShape,
      tipMask: null,
      edge: BrushAntiAlias.none.edge,
      // The mask is the raw coverage; the dab that lays it cuts it.
      threshold: false,
    ));

    // The consumer maps texel i to tip-space (canvas-offset) coordinates
    // through sampleBrushTipMaskCoverage's grid: mask [0, S) spans
    // [-radius, +radius].
    final texelSpan = (2.0 * radius) / maskSize;
    final alpha = Uint8List(maskSize * maskSize);
    var index = 0;
    for (var j = 0; j < maskSize; j += 1) {
      final dy = (j + 0.5) * texelSpan - radius;
      for (var i = 0; i < maskSize; i += 1, index += 1) {
        final dx = (i + 0.5) * texelSpan - radius;
        // The law the coverage list runs per canvas pixel, evaluated once
        // per texel here.
        final coverage = tipCoverageAt(tip, dx, dy);
        if (coverage <= 0.0) {
          continue;
        }
        alpha[index] = (coverage * 255.0).round().clamp(0, 255);
      }
    }
    return BrushTipMask(id: key, size: maskSize, alpha: alpha);
  }
}
