import 'dart:math' as math;

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
typedef BrushTipNumbers = ({
  double size,
  double hardness,
  double roundness,
  double angleDegrees,
  BrushTipShape tipShape,
  BrushTipMask? tipMask,
});

/// 🚨ONE derivation for the coverage list, the kernel plan and the stamp
/// cache (the audit's clone scan, 2026-09-03) — the parity suites pin
/// their bytes, so the arithmetic here is theirs, unchanged.
BrushDabTipGeometry brushTipGeometry(BrushTipNumbers tip) {
  final radius = tip.size / 2.0;
  final hardRadius = radius * tip.hardness;
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
));

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
