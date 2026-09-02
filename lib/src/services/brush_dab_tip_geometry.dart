import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../models/brush_tip_mask.dart';
import '../models/brush_tip_shape.dart';

/// The per-dab tip constants a dab rasterizer derives once before its pixel
/// loop: the radii, which shape branch applies, and the rotation terms.
///
/// 🚨ONE derivation for the coverage list and the kernel plan (the audit's
/// clone scan, 2026-09-03) — the parity suites pin their bytes, so the
/// arithmetic here is theirs, unchanged.
({
  double radius,
  double hardRadius,
  bool isRound,
  BrushTipMask? tipMask,
  bool isEllipse,
  bool isRotatedRect,
  double tipCos,
  double tipSin,
  double inverseRoundness,
})
brushDabTipGeometry(BrushDab dab) {
  final radius = dab.size / 2.0;
  final hardRadius = radius * dab.hardness;
  final isRound = dab.tipShape == BrushTipShape.round;
  final tipMask = dab.tipMask;
  final isEllipse = tipMask == null && isRound && dab.roundness < 1.0;
  final isRotatedRect =
      tipMask == null &&
      !isRound &&
      (dab.roundness < 1.0 || dab.angleDegrees != 0.0);
  var tipCos = 1.0;
  var tipSin = 0.0;
  var inverseRoundness = 1.0;
  if (isEllipse || isRotatedRect || tipMask != null) {
    final angleRadians = dab.angleDegrees * (math.pi / 180.0);
    tipCos = math.cos(angleRadians);
    tipSin = math.sin(angleRadians);
    inverseRoundness = 1.0 / dab.roundness;
  }
  return (
    radius: radius,
    hardRadius: hardRadius,
    isRound: isRound,
    tipMask: tipMask,
    isEllipse: isEllipse,
    isRotatedRect: isRotatedRect,
    tipCos: tipCos,
    tipSin: tipSin,
    inverseRoundness: inverseRoundness,
  );
}
