import '../models/brush_dab.dart';
import '../models/brush_input_source.dart';
import '../models/brush_pressure_curve.dart';
import '../models/brush_shape.dart';

/// Scales a dab's size/opacity/flow/hardness by its INPUTS, through the
/// per-(setting, source) response curves.
///
/// The dab is expected to still carry the base tool values in its
/// [BrushDab.size]/[BrushDab.opacity]/[BrushDab.flow]/[BrushDab.hardness]
/// fields, with the inputs it was sampled with beside them. Applied as a
/// post-interpolation step so each inserted dab is scaled by its own
/// interpolated inputs.
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
/// ⚠️Randomness is NOT a source here — it is `BrushShape.sizeJitter` and its
/// siblings, multiplied in by `brush_stroke_dynamics.dart`. One job, one
/// machine.
///
/// Returns the dab unchanged when it carries no curves at all, so the plain
/// path allocates nothing.
BrushDab applyBrushInputDynamics(BrushDab dab, {required BrushShape shape}) {
  if (shape.curves.isEmpty) {
    return dab;
  }
  return dab.copyWith(
    // ⚠️SIZE IS THE ONLY ONE THAT MAY EXCEED ITS BASE, which is why it alone
    // is unclamped: a tilt curve carries Clip Studio's 最大値 (up to 1000%)
    // and a fat wedge from a leaning pen is the whole point. There is no such
    // thing as 300% opacity, so the other three are cut back to [0, 1] —
    // that is a fact about those quantities, not about the curves.
    size: dab.size * _factorFor(dab, shape, BrushPressureTarget.size),
    opacity: (dab.opacity * _factorFor(dab, shape, BrushPressureTarget.opacity))
        .clamp(0.0, 1.0),
    flow: (dab.flow * _factorFor(dab, shape, BrushPressureTarget.flow))
        .clamp(0.0, 1.0),
    hardness:
        (dab.hardness * _factorFor(dab, shape, BrushPressureTarget.hardness))
            .clamp(0.0, 1.0),
  );
}

/// The product of every source's response for [target] — 1.0 when none drive
/// it, so the caller can multiply unconditionally.
double _factorFor(BrushDab dab, BrushShape shape, BrushPressureTarget target) {
  var factor = 1.0;
  for (final source in BrushInputSource.values) {
    final curve = shape.curveFor(target, source);
    if (curve == null) {
      continue;
    }
    final input = brushInputValue(dab, source);
    if (input == null) {
      continue;
    }
    factor *= curve.evaluate(input);
  }
  return factor;
}

/// What [dab] measured for [source], normalized to 0..1 — or `null` when this
/// engine cannot answer for that source yet, in which case its curve is
/// skipped rather than guessed at.
///
/// 🔜[BrushInputSource.speed] is the null: `BrushInputSample` carries no
/// timestamp, so nothing here can measure px/s. Its curve is stored and
/// imported faithfully and contributes nothing until that changes — see
/// [BrushInputSource.speed].
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
      // ⚠️A device that reports NO tilt sits at altitude 1.0, so it lands
      // here as lean 0.0 — the floor of the curve. For an imported brush
      // with a 0% minimum that is a stroke that vanishes on a mouse. There
      // is no "the device said nothing" value to tell that case apart from a
      // genuinely upright pen; see the board card `brush-tilt-no-device-Q1`.
      BrushInputSource.tilt => 1.0 - dab.tiltAltitude,
      BrushInputSource.speed => null,
    };
