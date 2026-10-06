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
