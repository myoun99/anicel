import 'dart:math' as math;
import 'dart:ui' as ui;

import 'directional_blur_passes.dart';
import 'shaded_passes.dart';

/// The most taps one row sum's pass takes — `shaders/row_sum.frag`'s loop
/// bound. Twice a line's: a pass is a raster, and on the Surface Pro 11 a
/// raster of 1920×1080 costs ~20ms whatever is drawn in it (10-28, card
/// effect-step-passes-each-pay-a-snapshot), so a raster up to 4096 wide is
/// two passes where 32 a pass would make it three.
const int rowSumTapsAPass = 64;

/// The most rows an iris spans — `shaders/iris_gather.frag`'s loop bound:
/// a radius of 8192 raster pixels, the longest side a raster has
/// (`maxSubtreeRasterSide`), each way and its own row.
const int irisRowsAtMost = 2 * 8192 + 1;

/// How big an iris's core is beside it — the inside a diffraction fringe
/// pushes the light out of, to the edge ([IrisGatherPass.fringe]). Ours,
/// as the fringe's form is (🗣️I-132-Q4 b): no help page says how wide AE's
/// ring is.
const double irisCoreScale = 0.8;

/// The passes that make every texel of a raster [width] wide the sum of
/// its row up to it ([RowSumPass]) — a one-sided box as long as the row,
/// laid as a line's is ([lineBoxPlan]) — the first reading its picture's
/// [light] as it sums it.
List<RowSumPass> rowSumPasses(int width, {LensLight? light}) {
  final (:passes, :taps) = lineBoxPlan(
    width.toDouble(),
    tapsAPass: rowSumTapsAPass,
  );
  return [
    for (var pass = 0; pass < passes; pass += 1)
      RowSumPass(
        stride: math.pow(taps, pass).toInt(),
        taps: taps,
        light: pass == 0 ? light : null,
      ),
  ];
}

/// A camera lens blur's Iris Properties, as Adobe's help names them (read
/// 2026-10-28): its Shape's [sides], its [roundness] (0…1), its [aspect] —
/// how wide it is to how tall — its [rotation], clockwise in radians, and
/// its Diffraction [fringe] (0…500).
typedef IrisProperties = ({
  int sides,
  double roundness,
  double aspect,
  double rotation,
  double fringe,
});

/// A camera lens blur [radius] raster pixels out over a raster
/// [rasterWidth] wide, as the passes that make it: the row sums, then the
/// [iris] gathered out of them ([IrisGatherPass]) — every pixel the mean of
/// the pixels about it whose centres it covers ([irisSpans]). [paper], on
/// whole pixels, is where it repeats its edge pixels past the paper and is
/// cut to it; null where it reads nothing past its raster.
///
/// Its fringe, 0 to 500, pushes the light out of the iris's core to its
/// edge: Adobe's help (read 2026-10-28) says 100 is a natural halo and 500
/// all the blur's energy on the ring. Ours, the form (🗣️I-132-Q4 b): the
/// core's pixels weigh `1 - fringe / 500`, the edge's 1.
///
/// Its [light] is how it reads what it spreads ([LensLight]) — none to
/// work where it is read as stored and nothing is boosted.
List<ShadedPass> cameraLensBlurPasses({
  required double radius,
  required IrisProperties iris,
  required LensLight light,
  required int rasterWidth,
  required ui.Rect? paper,
}) {
  final read = light.linear || (light.gain > 0 && light.threshold < 1)
      ? light
      : null;
  final reach = radius.floor();
  List<IrisSpan> spans(double scale) =>
      irisSpans(radius: radius * scale, iris: iris, reach: reach);
  final fringe = iris.fringe;
  final outline = spans(1);
  final core = fringe > 0 ? spans(irisCoreScale) : const <IrisSpan>[];
  int covered(List<IrisSpan> rows) => rows.fold(
    0,
    (sum, row) => sum + math.max(0, row.right - row.left + 1),
  );
  // Where the edge holds no pixel — an iris a pixel across, its core the
  // same pixel — there is nowhere to push the light to.
  final pushed = covered(outline) > covered(core) ? fringe / 500 : 0.0;
  return [
    ...rowSumPasses(rasterWidth, light: read),
    IrisGatherPass(
      reach: reach,
      outline: outline,
      core: core,
      fringe: pushed,
      weight: covered(outline) - covered(core) * pushed,
      paper: paper,
      light: read,
    ),
  ];
}

/// The rows an iris covers about its pixel, `2 · reach + 1` from `-reach`
/// down: in each, the columns whose pixel centres lie in it.
///
/// 📐THE IRIS (ours, 🗣️I-132-Q4 b: 「식은 지금대로」 — Adobe's help names
/// the properties and gives no shapes): a regular polygon of its sides
/// whose corners lie [radius] out, an edge lying flat along its bottom — a
/// triangle points up, a square stands square. Its roundness rounds it
/// toward the circle of that radius: the polygon drawn `1 - roundness` as
/// big, and every point within `roundness · radius` of it. Its aspect
/// squeezes it up and down (above 1) or across (below), so it fits the
/// circle still, and its rotation turns it ([IrisProperties]).
///
/// 🔬Exact, not traced: the rounded polygon is the polygon, the strip
/// outward of each edge and the disc about each corner, and a row through
/// it is the span of the rows through those — each worked out where it
/// crosses the row.
List<IrisSpan> irisSpans({
  required double radius,
  required IrisProperties iris,
  required int reach,
}) {
  final corner = (1 - iris.roundness) * radius;
  final half = math.pi / iris.sides;
  final outline = (
    edges: [
      for (var k = 0; k < iris.sides; k += 1)
        (
          normal: (
            x: math.cos(math.pi / 2 + 2 * half * k),
            y: math.sin(math.pi / 2 + 2 * half * k),
          ),
          corner: (
            x: corner * math.cos(math.pi / 2 + half * (2 * k + 1)),
            y: corner * math.sin(math.pi / 2 + half * (2 * k + 1)),
          ),
        ),
    ],
    apothem: corner * math.cos(half),
    side: corner * math.sin(half),
    round: iris.roundness * radius,
  );
  final (across, upDown) = (
    math.min(iris.aspect, 1.0),
    math.min(1 / iris.aspect, 1.0),
  );
  final (cos, sin) = (math.cos(iris.rotation), math.sin(iris.rotation));
  // The row's line, (t, dy), in the iris's own unturned, unsqueezed
  // space: at + t · along.
  final along = (x: cos / across, y: -sin / upDown);
  return [
    for (var dy = -reach; dy <= reach; dy += 1)
      _spanOf(
        _crossings(
          (x: sin * dy / across, y: cos * dy / upDown),
          along,
          outline,
        ),
      ),
  ];
}

typedef _Vector = ({double x, double y});

double _dot(_Vector a, _Vector b) => a.x * b.x + a.y * b.y;

/// A rounded polygon about the origin: its [edges]' outward normals and the
/// corner each ends at, how far its edges lie ([apothem]), half an edge's
/// length ([side]), and how far round it reaches past them ([round]).
typedef _Outline = ({
  List<({_Vector normal, _Vector corner})> edges,
  double apothem,
  double side,
  double round,
});

/// Where the line `at + t · along` lies in [outline] — the polygon, the
/// strip outward of each edge, the disc about each corner — as each one's
/// span of t, null for one it misses.
Iterable<(double, double)?> _crossings(
  _Vector at,
  _Vector along,
  _Outline outline,
) sync* {
  final (:edges, :apothem, :side, :round) = outline;
  if (apothem > 0) {
    yield _withinHalfPlanes(at, along, [
      for (final edge in edges) (normal: edge.normal, most: apothem),
    ]);
  }
  if (round <= 0) {
    return;
  }
  for (final edge in edges) {
    final tangent = (x: -edge.normal.y, y: edge.normal.x);
    yield _withinHalfPlanes(at, along, [
      (normal: edge.normal, most: apothem + round),
      (normal: (x: -edge.normal.x, y: -edge.normal.y), most: -apothem),
      (normal: tangent, most: side),
      (normal: (x: -tangent.x, y: -tangent.y), most: side),
    ]);
    yield _withinDisc(at, along, edge.corner, round);
  }
}

/// The span of t where `at + t · along` keeps `normal · p <= most` for
/// every one of [planes] — null where it leaves them nowhere.
(double, double)? _withinHalfPlanes(
  _Vector at,
  _Vector along,
  List<({_Vector normal, double most})> planes,
) {
  var (low, high) = (double.negativeInfinity, double.infinity);
  for (final (:normal, :most) in planes) {
    final room = most - _dot(normal, at);
    final rate = _dot(normal, along);
    if (rate == 0) {
      // A row along an edge is on it: the tolerance [_spanOf]'s is.
      if (room < -1e-9) {
        return null;
      }
      continue;
    }
    final t = room / rate;
    if (rate > 0) {
      high = math.min(high, t);
    } else {
      low = math.max(low, t);
    }
  }
  return low <= high ? (low, high) : null;
}

/// The span of t where `at + t · along` lies within [radius] of [center] —
/// null where it passes it by.
(double, double)? _withinDisc(
  _Vector at,
  _Vector along,
  _Vector center,
  double radius,
) {
  final away = (x: at.x - center.x, y: at.y - center.y);
  final a = _dot(along, along);
  final b = _dot(along, away);
  final reach = b * b - a * (_dot(away, away) - radius * radius);
  if (reach < 0) {
    return null;
  }
  final root = math.sqrt(reach);
  return ((-b - root) / a, (-b + root) / a);
}

/// The columns whose centres lie in the spans [crossings] make up — one
/// span, the iris being convex. A centre on its edge is in it: the
/// tolerance is for the rounding that puts it a hair either way.
IrisSpan _spanOf(Iterable<(double, double)?> crossings) {
  var (low, high) = (double.infinity, double.negativeInfinity);
  for (final crossing in crossings) {
    if (crossing case (final from, final to)) {
      low = math.min(low, from);
      high = math.max(high, to);
    }
  }
  if (low > high) {
    return (left: 1, right: 0);
  }
  return (left: (low - 1e-9).ceil(), right: (high + 1e-9).floor());
}
