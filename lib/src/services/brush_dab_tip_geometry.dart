import 'dart:math' as math;

import '../models/brush_anti_alias.dart';
import '../models/brush_dab.dart';
import '../models/brush_tip_mask.dart';
import '../models/brush_tip_shape.dart';
import 'brush_tip_mask_sampling.dart';

/// The per-dab tip constants a dab rasterizer derives once before its pixel
/// loop: the radii, which shape branch applies, and the rotation terms.
typedef BrushDabTipGeometry = ({
  double radius,
  double minorRadius,
  double hardRadius,
  bool isRound,
  BrushTipMask? tipMask,
  bool isEllipse,
  double tipCos,
  double tipSin,
  double inverseRoundness,
});

/// The numbers a tip is made of, however the caller came by them: a dab
/// carries them as fields, the stamp cache as a quantized cache key.
/// [edgeWidth] is the anti-alias step's ([BrushAntiAlias.edgeWidth]).
typedef BrushTipNumbers = ({
  double size,
  double hardness,
  double roundness,
  double angleDegrees,
  BrushTipShape tipShape,
  BrushTipMask? tipMask,
  double edgeWidth,
});

/// 🚨ONE derivation for the coverage list, the kernel plan and the stamp
/// cache (the audit's clone scan, 2026-09-03) — the parity suites pin
/// their bytes, so the arithmetic here is theirs, unchanged.
///
/// 🚨★★★I-50: a round tip's edge is the WIDER of its hardness ramp and the
/// anti-alias step's [BrushTipNumbers.edgeWidth], and it widens INWARD — the
/// step pulls [hardRadius] in while the rim stays at [radius] (down to the
/// centre, never past it). That is Clip Studio's G펜: its lines fit a ramp
/// inside the rim, not one centred on it — centred, the lines came out a
/// pixel and more too thick (board I-50). A tip whose hardness ramp is the
/// wider one keeps it to the bit, so the edge moves continuously with
/// hardness.
BrushDabTipGeometry brushTipGeometry(BrushTipNumbers tip) {
  final radius = tip.size / 2.0;
  final hardRadius = math.min(
    radius * tip.hardness,
    math.max(0.0, radius - tip.edgeWidth),
  );
  final isRound = tip.tipShape == BrushTipShape.round;
  final tipMask = tip.tipMask;
  final isEllipse = tipMask == null && isRound && tip.roundness < 1.0;
  var tipCos = 1.0;
  var tipSin = 0.0;
  var inverseRoundness = 1.0;
  if (isEllipse || tipMask != null) {
    final angleRadians = tip.angleDegrees * (math.pi / 180.0);
    tipCos = math.cos(angleRadians);
    tipSin = math.sin(angleRadians);
    inverseRoundness = 1.0 / tip.roundness;
  }
  return (
    radius: radius,
    minorRadius: radius * tip.roundness,
    hardRadius: hardRadius,
    isRound: isRound,
    tipMask: tipMask,
    isEllipse: isEllipse,
    tipCos: tipCos,
    tipSin: tipSin,
    inverseRoundness: inverseRoundness,
  );
}

BrushDabTipGeometry brushDabTipGeometry(BrushDab dab) => brushTipGeometry((
  size: dab.size,
  hardness: dab.hardness,
  roundness: dab.roundness,
  angleDegrees: dab.angleDegrees,
  tipShape: dab.tipShape,
  tipMask: dab.tipMask,
  edgeWidth: dab.antiAlias.edgeWidth,
));

/// What a dab's coverage goes through AFTER its tip is sampled — the
/// anti-alias step's last word.
typedef BrushEdgeLaw = ({bool threshold, double contrast});

/// 🚨★★★ONE answer for the kernel plan and the coverage reference (I-50).
///
/// 없음 cuts at half coverage whatever the tip. Any other step: an ANALYTIC
/// round tip already carries its edge — in its ramp ([brushTipGeometry]) or
/// baked into its stamp ([BrushTipMask.edgeBaked]) — and takes its coverage
/// as it is; every other tip keeps the contrast ladder
/// ([BrushAntiAlias.contrast]) — a raster tip has no distance to its edge
/// to widen, and a square's edge was never made wider by the step.
BrushEdgeLaw brushDabEdgeLaw(BrushDab dab) {
  final contrast = dab.antiAlias.contrast;
  if (contrast == null) {
    return (threshold: true, contrast: 1.0);
  }
  final mask = dab.tipMask;
  final carriesItsEdge = mask == null
      ? dab.tipShape == BrushTipShape.round
      : mask.edgeBaked;
  return (threshold: false, contrast: carriesItsEdge ? 1.0 : contrast);
}

/// [coverage] through [law] — the definition the tile and native kernels
/// inline against hoisted values.
double brushEdgeApplied(BrushEdgeLaw law, double coverage) {
  if (law.threshold) {
    return coverage >= 0.5 ? 1.0 : 0.0;
  }
  if (law.contrast == 1.0) {
    return coverage;
  }
  return ((coverage - 0.5) * law.contrast + 0.5).clamp(0.0, 1.0).toDouble();
}

/// What an ANALYTIC round tip covers at ([dx], [dy]) from the dab centre —
/// 0.0 where the tip does not reach, so a caller skips on `<= 0.0` exactly
/// as it did when it wrote the cascade out.
///
/// ⛔THE THREE ROUTES DISAGREEING HERE IS A SILENT REPAINT: the stamp cache
/// BAKES this into a mask, and a stroke picks the baked route or the direct
/// one by cache state alone — so a falloff changed in one place would make
/// the same brush paint two different edges depending on what was cached.
double analyticRoundTipCoverage(
  BrushDabTipGeometry tip,
  double dx,
  double dy,
) {
  final double distance;
  if (tip.isEllipse) {
    final tipU = dx * tip.tipCos - dy * tip.tipSin;
    final tipV = (dx * tip.tipSin + dy * tip.tipCos) * tip.inverseRoundness;
    distance = math.sqrt(tipU * tipU + tipV * tipV);
  } else {
    distance = math.sqrt(dx * dx + dy * dy);
  }
  if (distance > tip.radius) {
    return 0.0;
  }
  final edgeSpan = tip.radius - tip.hardRadius;
  if (distance <= tip.hardRadius || edgeSpan <= 0.0) {
    return 1.0;
  }
  return (1.0 - ((distance - tip.hardRadius) / edgeSpan)).clamp(0.0, 1.0);
}

/// What a ROTATED raster tip covers at ([dx], [dy]) — 0.0 outside the
/// mask's square, which is the skip the callers already made.
double rotatedTipMaskCoverage(
  BrushDabTipGeometry tip,
  BrushTipMask mask,
  double dx,
  double dy,
) {
  final tipU = dx * tip.tipCos - dy * tip.tipSin;
  final tipV = (dx * tip.tipSin + dy * tip.tipCos) * tip.inverseRoundness;
  if (tipU.abs() > tip.radius || tipV.abs() > tip.radius) {
    return 0.0;
  }
  return sampleBrushTipMaskCoverage(
    mask: mask,
    tipU: tipU,
    tipV: tipV,
    radius: tip.radius,
  );
}
