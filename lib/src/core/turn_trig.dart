import 'dart:math' as math;

/// The cosine of a turn of [degrees], EXACT at the quarter turns — see
/// [turnSin] for the pair and the reason.
double turnCos(double degrees) {
  final quarter = _exactQuarterTurn(degrees);
  return quarter == null
      ? math.cos(degrees * math.pi / 180)
      : _quarterCos[quarter];
}

/// The sine of a turn of [degrees], EXACT at the quarter turns.
///
/// `math.cos(pi / 2)` is 6.1e-17, not zero, and that residue is enough to
/// make a quarter turn miss the resampler's lattice: destination pixel
/// centres land a hair off source pixel centres, the footprint reaches a
/// neighbour it should not, and "rotating by 90° gives back the same
/// pixels" becomes a rounding accident rather than a guarantee. Reading
/// the table for exact multiples of 90 makes it structural.
///
/// ⛔ONE TABLE. The transform box's affine and a layer's placement both
/// turn by these, so a picture turned by the box and a row turned by its
/// lane cannot disagree about where a quarter turn went — which is exactly
/// what a second copy of this table would let happen. ↩️It was the box's
/// alone (`SelectionAffine.cosTheta`), and a row's placement turned by the
/// library's: a posed row then crossed onto the canvas through the box's
/// affine and was painted through the other.
double turnSin(double degrees) {
  final quarter = _exactQuarterTurn(degrees);
  return quarter == null
      ? math.sin(degrees * math.pi / 180)
      : _quarterSin[quarter];
}

/// A turn of the plane about its origin, [degrees] clockwise where y runs
/// down (a canvas's, a viewport's): its cosine and sine from the one table
/// above, and what it does to a point.
///
/// ⛔ONE FORMULA, as there is one table. `x·cos − y·sin, x·sin + y·cos`
/// and its way back were written out by hand wherever something turned —
/// the viewport's two conversions, the transform box's affine (three), its
/// resample fold and its scale solve (two), a text's turn about its cross,
/// its frame and the way its letters run, the brush cursor's two axes, a
/// guide's symmetry — and half of them read `math.cos` instead of the
/// table, so a text turned 90° kept a 6e-17 that the box's affine did not
/// (board `a-point-turned-by-an-angle-is-spelled-in-many-places`;
/// `a_point_is_turned_in_one_place_test` holds the rest to it).
final class PlaneTurn {
  PlaneTurn(double degrees) : cos = turnCos(degrees), sin = turnSin(degrees);

  const PlaneTurn._(this.cos, this.sin);

  final double cos;
  final double sin;

  /// The same turn the other way: what takes a turned point back.
  PlaneTurn get back => PlaneTurn._(cos, -sin);

  /// The point ([x], [y]) turned.
  ({double x, double y}) apply(double x, double y) =>
      (x: turnedX(x, y, cos, sin), y: turnedY(x, y, cos, sin));
}

/// The two coordinates of ([x], [y]) turned by the turn whose cosine and
/// sine are [cos] and [sin] — THE formula, which [PlaneTurn.apply] runs.
///
/// Two plain leaves over a turn's two numbers, for a loop that turns a
/// point per pixel and holds those numbers already (a brush tip's,
/// `tipCoverageAt`) and wants no record back per pixel.
@pragma('vm:prefer-inline')
double turnedX(double x, double y, double cos, double sin) =>
    x * cos - y * sin;
@pragma('vm:prefer-inline')
double turnedY(double x, double y, double cos, double sin) =>
    x * sin + y * cos;

/// 0/1/2/3 for an exact 0/90/180/270, null for anything in between.
int? _exactQuarterTurn(double degrees) {
  if (degrees % 90 != 0 || !degrees.isFinite) {
    return null;
  }
  final quarter = (degrees ~/ 90) % 4;
  return quarter < 0 ? quarter + 4 : quarter;
}

const List<double> _quarterCos = <double>[1, 0, -1, 0];
const List<double> _quarterSin = <double>[0, 1, 0, -1];
