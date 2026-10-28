import 'dart:math' as math;

import 'package:anicel/src/services/shaded_passes.dart';

/// `iris_table.frag`'s core: the iris drawn this much as big.
const double irisCoreScale = 0.8;

/// The columns about a pixel one row of an iris covers, [left] to [right]
/// — none where [left] is past [right].
typedef IrisRow = ({int left, int right});

/// How far the pixel centre ([dx], [dy]) about an iris's own lies past the
/// edge of [iris] drawn [radius] out — less than 0 inside — asked point by
/// point, unturned and unsqueezed, of the polygon drawn `1 - roundness` as
/// big: none of the crossings `iris_table.frag` works its rows out from.
double pastTheIris(int dx, int dy, double radius, IrisProperties iris) {
  final (:sides, :roundness, :aspect, :rotation, fringe: _) = iris;
  // Turned back, then unsqueezed.
  final (cos, sin) = (math.cos(rotation), math.sin(rotation));
  final x = (cos * dx + sin * dy) / math.min(aspect, 1.0);
  final y = (-sin * dx + cos * dy) / math.min(1 / aspect, 1.0);
  final corner = (1 - roundness) * radius;
  final rounding = roundness * radius;
  if (corner <= 0) {
    return math.sqrt(x * x + y * y) - rounding;
  }
  final corners = [
    for (var k = 0; k < sides; k += 1)
      (
        corner * math.cos(math.pi / 2 + math.pi / sides * (2 * k + 1)),
        corner * math.sin(math.pi / 2 + math.pi / sides * (2 * k + 1)),
      ),
  ];
  var inside = true;
  var nearest = double.infinity;
  for (var k = 0; k < sides; k += 1) {
    final (ax, ay) = corners[k];
    final (bx, by) = corners[(k + 1) % sides];
    // The corners run by a growing angle: the inside crosses positive.
    if ((bx - ax) * (y - ay) - (by - ay) * (x - ax) < 0) {
      inside = false;
    }
    final (ex, ey) = (bx - ax, by - ay);
    final t = (((x - ax) * ex + (y - ay) * ey) / (ex * ex + ey * ey)).clamp(
      0.0,
      1.0,
    );
    final (px, py) = (ax + ex * t - x, ay + ey * t - y);
    nearest = math.min(nearest, math.sqrt(px * px + py * py));
  }
  return (inside ? -nearest : nearest) - rounding;
}

/// The rows [iris] covers [radius] out, `2 · reach + 1` of them from
/// `-reach` down — its own reach unless one is given, as a core's rows are
/// its iris's — in each, the columns whose centres lie within [edge] of
/// it, `iris_table.frag`'s own reach of a centre on the edge. An iris of no
/// radius covers no centre.
List<IrisRow> irisRowsOf(
  double radius,
  IrisProperties iris, {
  int? reach,
  double edge = 1e-3,
}) {
  final rows = reach ?? radius.floor();
  return [
    for (var dy = -rows; dy <= rows; dy += 1)
      if (radius <= 0)
        (left: 1, right: 0)
      else
        _rowOf([
          for (var dx = -rows - 1; dx <= rows + 1; dx += 1)
            if (pastTheIris(dx, dy, radius, iris) <= edge) dx,
        ]),
  ];
}

/// What an iris covers, as `iris_gather.frag` weighs it: its outline's
/// rows from `-reach` down, its core's over the same rows, the share of the
/// core's light its fringe pushes out to the edge, and what its weights add
/// up to — no more than 0 where it covers no centre, and the pixel is
/// itself.
typedef IrisCover = ({
  int reach,
  List<IrisRow> outline,
  List<IrisRow> core,
  double pushed,
  double weight,
});

/// What [iris] covers [radius] out.
IrisCover irisCoverOf(double radius, IrisProperties iris) {
  final reach = radius.floor();
  final outline = irisRowsOf(radius, iris);
  final fringe = iris.fringe / 500;
  final core = fringe > 0
      ? irisRowsOf(radius * irisCoreScale, iris, reach: reach)
      : const <IrisRow>[];
  final (onOutline, onCore) = (coveredBy(outline), coveredBy(core));
  final pushed = onOutline > onCore ? fringe : 0.0;
  return (
    reach: reach,
    outline: outline,
    core: core,
    pushed: pushed,
    weight: onOutline - onCore * pushed,
  );
}

/// Whether a pixel centre lies a hair — less than [hair], yet not on it —
/// from the edge of [iris] drawn [radius] out, or, where it has a fringe,
/// from its core's: where `iris_table.frag`, which reaches [irisRowsOf]'s
/// `edge` along a row, not square to the edge, may put it either way. A
/// centre on the edge, as on a square's side, falls in on both. An iris of
/// no radius has no edge.
bool aCentreIsAHairFromTheEdge(
  double radius,
  IrisProperties iris, {
  double hair = 2e-3,
}) {
  final reach = radius.floor();
  for (final drawn in [radius, if (iris.fringe > 0) radius * irisCoreScale]) {
    for (var dy = -reach; dy <= reach && drawn > 0; dy += 1) {
      for (var dx = -reach - 1; dx <= reach + 1; dx += 1) {
        final past = pastTheIris(dx, dy, drawn, iris).abs();
        if (past > 1e-9 && past < hair) {
          return true;
        }
      }
    }
  }
  return false;
}

IrisRow _rowOf(List<int> covered) => covered.isEmpty
    ? (left: 1, right: 0)
    : (left: covered.first, right: covered.last);

int coveredBy(List<IrisRow> rows) => rows.fold(
  0,
  (sum, row) => sum + math.max(0, row.right - row.left + 1),
);
