import 'dart:math' as math;

import '../models/brush_dab.dart';
import '../models/brush_input_source.dart';
import '../models/brush_pressure_curve.dart';
import '../models/brush_shape.dart';

/// Scales a dab's size, opacity, flow, hardness and roundness by its INPUTS,
/// through the per-(setting, source) response curves.
///
/// The dab is expected to still carry the base tool values in those fields,
/// with the inputs it was sampled with beside them. Applied as a
/// post-interpolation step so each inserted dab is scaled by its own
/// interpolated inputs.
///
/// [random] answers the ランダム row: the stroke's own dice, so a throw is
/// made once, when the dab is generated, and the dab carries the result —
/// committing, undoing and saving replay it rather than throwing again.
/// Without dice (a still thumbnail) the row is skipped, the way a device that
/// reports no tilt skips 傾き.
///
/// ## Several sources on one setting MULTIPLY
///
/// ⛔**Our rule, chosen on precedent — NOT a reading of any file format.**
/// See [BrushInputSource] for the survey behind it (Krita's default, MyPaint's
/// log-space addition, and the fact that nothing documents Clip Studio's).
/// What multiplying buys, concretely: a source that is off contributes exactly
/// 1.0, so turning one on cannot disturb the others and the order cannot
/// matter. That is why this loops instead of hand-listing pairs.
///
/// Returns the dab unchanged when it carries no curves at all, so the plain
/// path allocates nothing.
BrushDab applyBrushInputDynamics(
  BrushDab dab, {
  required BrushShape shape,
  math.Random? random,
}) {
  if (shape.curves.isEmpty) {
    return dab;
  }
  double factor(BrushPressureTarget target) =>
      brushInputFactor(dab, shape, target, random: random);
  return dab.copyWith(
    // ⚠️SIZE IS THE ONLY ONE THAT MAY EXCEED ITS BASE, which is why it alone
    // is unclamped: a tilt curve carries Clip Studio's 最大値 (up to 1000%)
    // and a fat wedge from a leaning pen is the whole point. There is no such
    // thing as 300% opacity, so the others are cut back to their ranges —
    // that is a fact about those quantities, not about the curves.
    size: dab.size * factor(BrushPressureTarget.size),
    opacity: (dab.opacity * factor(BrushPressureTarget.opacity)).clamp(
      0.0,
      1.0,
    ),
    flow: (dab.flow * factor(BrushPressureTarget.flow)).clamp(0.0, 1.0),
    hardness: (dab.hardness * factor(BrushPressureTarget.hardness)).clamp(
      0.0,
      1.0,
    ),
    // Roundness is a ratio in (0, 1]; a fully-squashed tip would be a
    // degenerate zero-width ellipse, so it keeps a hair of width.
    roundness: (dab.roundness * factor(BrushPressureTarget.roundness)).clamp(
      0.01,
      1.0,
    ),
  );
}

/// The product of every source's response for [target] — 1.0 when none drive
/// it, so the caller can multiply unconditionally. [random] throws for the
/// ランダム row; without it that row is skipped.
double brushInputFactor(
  BrushDab dab,
  BrushShape shape,
  BrushPressureTarget target, {
  math.Random? random,
}) {
  var factor = 1.0;
  for (final source in BrushInputSource.values) {
    final curve = shape.curveFor(target, source);
    if (curve == null) {
      continue;
    }
    final input = source == BrushInputSource.random
        ? random?.nextDouble()
        : brushInputValue(dab, source);
    if (input == null) {
      continue;
    }
    factor *= curve.evaluate(input);
  }
  return factor;
}

/// The spacing ratio for a segment that ends at [reading]: [shape]'s 間隔
/// through its curves — that reading's pressure, tilt and speed, and one
/// throw of [random] for the ランダム row (F-176-Q2).
///
/// ⚠️Never below [BrushShape.minSpacing] — the 1% floor is the user's
/// (2026-09-24), and a curve at 0% would otherwise ask for a dab per pixel at
/// any size.
double brushSpacingFor(
  BrushDab reading,
  BrushShape shape, {
  math.Random? random,
}) {
  final spacing =
      shape.spacing *
      brushInputFactor(
        reading,
        shape,
        BrushPressureTarget.spacing,
        random: random,
      );
  return math.max(spacing, BrushShape.minSpacing);
}

/// What [dab] measured for [source], normalized to 0..1 — or `null` when this
/// engine cannot answer for that source from the dab, in which case its curve
/// is skipped rather than guessed at.
///
/// ⚠️It stays nullable because the CALLER's contract is "skip what cannot be
/// answered", and that is the question a source is asked, not a fact about
/// which sources currently answer — speed was the null until the pen door
/// learned to measure it, and chance is the null now: the throw is the
/// stroke's, not the dab's ([brushInputFactor]).
double? brushInputValue(BrushDab dab, BrushInputSource source) =>
    switch (source) {
      BrushInputSource.pressure => dab.pressure,
      // 🚨THE COMPLEMENT, not the field itself. 傾き is HOW FAR THE PEN LEANS
      // — more lean, more input — while [BrushDab.tiltAltitude] is how
      // UPRIGHT it is (1.0 vertical, 0.0 flat on the page). They run opposite
      // ways, so the conversion is forced by what the two words mean; it is
      // not a choice about how tilt should behave. Which way the RESPONSE
      // runs is the curve's own shape, and that comes out of the file.
      //
      // ⛔An earlier draft passed `tiltAltitude` straight through with a
      // comment claiming Clip Studio reads the same way round. Nobody had
      // checked that, and it was backwards.
      //
      // ⚠️NULL propagates: a device that reported no tilt cannot answer, and
      // `brushInputFactor` skips a source it cannot answer for. 유저
      // 2026-09-09 (`brush-tilt-no-device-Q1` 답 1). Before this, a mouse
      // arrived as an upright pen and a 0% tilt minimum erased the stroke.
      BrushInputSource.tilt => dab.tiltAltitude == null
          ? null
          : 1.0 - dab.tiltAltitude!,
      // The dab already holds the RATIO, not px/s: the pen door divides by
      // the user's reference speed once, where pressure and tilt are
      // normalized too. See `AppInput.normalizedSpeed`.
      BrushInputSource.speed => dab.speed,
      BrushInputSource.random => null,
    };
