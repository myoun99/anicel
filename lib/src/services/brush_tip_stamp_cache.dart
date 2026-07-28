import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/brush_dab.dart';
import '../models/brush_tip_mask.dart';
import '../models/brush_tip_shape.dart';
import 'brush_tip_mask_sampling.dart';

/// The prerendered tip-stamp cache (R20-B — the CSP/Photoshop brush
/// architecture): every tip, analytic circles included, renders ONCE per
/// quantized parameter set into a raster coverage mask, and dabs are
/// REWRITTEN at generation time to consume that mask as an unrotated
/// [BrushTipMask].
///
/// Why this shape:
///  - Rotation is baked into the mask (1° steps), so every dab —
///    including direction-following rotated raster tips, previously the
///    slow per-pixel-rotation path — rides the fast unrotated-lattice
///    path in the rasterizers AND the C kernel, with NO engine changes.
///  - Subpixel placement needs no phase quantization: the existing
///    bilinear lattice sampling shifts the mask continuously.
///  - live == commit parity holds by construction: dabs resolve ONCE at
///    generation (the same place stroke dynamics run), and the resolved
///    dab is what the overlay rasterizer, the commit materializer, undo
///    replay and the .anicel all see.
///
/// Quantization (user-approved: stroke bytes may change vs the old
/// direct-analytic path): size 1/4 px steps up to 64 px then ~1.1%
/// log steps; hardness/roundness 1/128 steps; angle 1° steps.
class BrushTipStampCache {
  BrushTipStampCache({this.byteBudget = 128 * 1024 * 1024});

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

  /// Rewrites [dab] to its cached-raster-tip form: quantized size, the
  /// prerendered mask, `angleDegrees: 0`, `roundness: 1` (both baked into
  /// the mask). Stamp dabs (lift/fill pixels) and already-resolved dabs
  /// pass through untouched.
  BrushDab resolveDab(BrushDab dab) {
    if (dab.stamp != null) {
      return dab;
    }
    final sourceTip = dab.tipMask;
    if (sourceTip != null && sourceTip.id.startsWith(resolvedIdPrefix)) {
      return dab;
    }
    final sizeQ = quantizeSizeStep(dab.size);
    final size = dequantizeSize(sizeQ);
    final hardnessQ = (dab.hardness.clamp(0.0, 1.0) * 128).round();
    final roundnessQ = (dab.roundness.clamp(0.0, 1.0) * 128).round().clamp(
      1,
      128,
    );
    final angleQ = ((dab.angleDegrees.round() % 360) + 360) % 360;
    final tipId = sourceTip?.id ?? 'analytic:${dab.tipShape.name}';
    final key = '$resolvedIdPrefix$tipId|$sizeQ|$hardnessQ|$roundnessQ|$angleQ';

    var mask = _masks.remove(key);
    if (mask != null) {
      _masks[key] = mask; // LRU touch.
    } else {
      mask = _render(
        key: key,
        sourceTip: sourceTip,
        tipShape: dab.tipShape,
        size: size,
        hardness: hardnessQ / 128.0,
        roundness: roundnessQ / 128.0,
        angleDegrees: angleQ.toDouble(),
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
  /// rotation/roundness/hardness baked in.
  BrushTipMask _render({
    required String key,
    required BrushTipMask? sourceTip,
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
    // contract). Raster source tips keep more of their native detail.
    var maskSize = (size.ceil() + 2).clamp(4, 256);
    if (sourceTip != null) {
      maskSize = math.max(maskSize, math.min(sourceTip.size, 512));
    }

    final angleRadians = angleDegrees * (math.pi / 180.0);
    final tipCos = math.cos(angleRadians);
    final tipSin = math.sin(angleRadians);
    final inverseRoundness = 1.0 / roundness;
    final hardRadius = radius * hardness;
    final edgeSpan = radius - hardRadius;
    final minorRadius = radius * roundness;
    final isRound = tipShape == BrushTipShape.round;

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
        double coverage;
        if (sourceTip != null) {
          // Raster tip: today's rotated sampling, evaluated once here.
          final tipU = dx * tipCos - dy * tipSin;
          final tipV = (dx * tipSin + dy * tipCos) * inverseRoundness;
          if (tipU.abs() > radius || tipV.abs() > radius) {
            continue;
          }
          coverage = sampleBrushTipMaskCoverage(
            mask: sourceTip,
            tipU: tipU,
            tipV: tipV,
            radius: radius,
          );
        } else if (isRound) {
          // Analytic circle/ellipse with the hardness falloff — the same
          // math the materializer ran per canvas pixel.
          double distance;
          if (roundness < 1.0) {
            final tipU = dx * tipCos - dy * tipSin;
            final tipV = (dx * tipSin + dy * tipCos) * inverseRoundness;
            distance = math.sqrt(tipU * tipU + tipV * tipV);
          } else {
            distance = math.sqrt(dx * dx + dy * dy);
          }
          if (distance > radius) {
            continue;
          }
          if (distance <= hardRadius || edgeSpan <= 0.0) {
            coverage = 1.0;
          } else {
            coverage = (1.0 - ((distance - hardRadius) / edgeSpan)).clamp(
              0.0,
              1.0,
            );
          }
        } else {
          // Analytic square / rotated rectangle: full coverage inside.
          if (roundness < 1.0 || angleDegrees != 0.0) {
            final tipU = dx * tipCos - dy * tipSin;
            final tipV = dx * tipSin + dy * tipCos;
            if (tipU.abs() > radius || tipV.abs() > minorRadius) {
              continue;
            }
          }
          coverage = 1.0;
        }
        if (coverage <= 0.0) {
          continue;
        }
        alpha[index] = (coverage * 255.0).round().clamp(0, 255);
      }
    }
    return BrushTipMask(id: key, size: maskSize, alpha: alpha);
  }
}
