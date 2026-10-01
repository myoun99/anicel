import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/brush_anti_alias.dart';
import '../models/brush_dab.dart';
import '../models/brush_tip_mask.dart';
import '../models/brush_tip_shape.dart';
import 'brush_dab_tip_geometry.dart';

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

  final LinkedHashMap<String, BrushTipMask> _masks = LinkedHashMap();
  int _bytes = 0;

  int get residentBytes => _bytes;
  int get entryCount => _masks.length;

  /// Rewrites an analytic [dab] to its cached-stamp form: quantized size,
  /// the prerendered mask, `angleDegrees: 0`, `roundness: 1` (both baked
  /// into the mask). A dab that already carries a mask — a raster tip, or
  /// one this cache resolved — and a stamp dab (lift/fill pixels) pass
  /// through untouched.
  BrushDab resolveDab(BrushDab dab) {
    if (dab.stamp != null || dab.tipMask != null) {
      return dab;
    }
    final sizeQ = quantizeSizeStep(dab.size);
    final size = dequantizeSize(sizeQ);
    final hardnessQ = (dab.hardness.clamp(0.0, 1.0) * 128).round();
    final roundnessQ = (dab.roundness.clamp(0.0, 1.0) * 128).round().clamp(
      1,
      128,
    );
    final round = dab.tipShape == BrushTipShape.round;
    // A circle is the same stamp at every angle ([brushTipGeometry] turns
    // only an ellipse), so its angle is not part of what the stamp is.
    final angleQ = round && roundnessQ == 128
        ? 0
        : ((dab.angleDegrees.round() % 360) + 360) % 360;
    // I-50: an analytic ROUND tip's stamp carries the anti-alias step's edge
    // ([brushTipGeometry]), so the step is part of what the stamp is; every
    // other tip's step applies after sampling, as before.
    final bakedStep = round ? dab.antiAlias : null;
    final step = bakedStep == null ? '' : '|${bakedStep.name}';
    final key =
        '${resolvedIdPrefix}analytic:${dab.tipShape.name}'
        '|$sizeQ|$hardnessQ|$roundnessQ|$angleQ$step';

    var mask = _masks.remove(key);
    if (mask != null) {
      _masks[key] = mask; // LRU touch.
    } else {
      mask = _render(
        key: key,
        tipShape: dab.tipShape,
        size: size,
        hardness: hardnessQ / 128.0,
        roundness: roundnessQ / 128.0,
        angleDegrees: angleQ.toDouble(),
        bakedStep: bakedStep,
      );
      _masks[key] = mask;
      _bytes += _maskCost(mask);
      while (_masks.length > 1 && _bytes > byteBudget) {
        final oldest = _masks.keys.first;
        _bytes -= _maskCost(_masks.remove(oldest)!);
      }
    }

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

  void clear() {
    _masks.clear();
    _bytes = 0;
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
  /// rotation/roundness/hardness baked in — and, given [bakedStep], that
  /// anti-alias step's edge (I-50).
  BrushTipMask _render({
    required String key,
    required BrushTipShape tipShape,
    required double size,
    required double hardness,
    required double roundness,
    required double angleDegrees,
    required BrushAntiAlias? bakedStep,
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
      edgeWidth: bakedStep?.edgeWidth ?? 0.0,
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
    return BrushTipMask(
      id: key,
      size: maskSize,
      alpha: alpha,
      edgeBaked: bakedStep != null,
    );
  }
}
