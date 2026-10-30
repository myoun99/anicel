import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/shaded_passes.dart';
import 'package:anicel/src/ui/canvas/iris_blur_shader.dart';

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

/// What [pass] covers at its level [level], as [table] — the table it lays
/// — has it: its core's rows read where it has a fringe, and the light
/// pushed to the edge only where the edge holds a pixel the core does not.
IrisCover irisLaidCoverOf(
  IrisTable table,
  IrisGatherPass pass, {
  int level = 0,
}) {
  final outline = irisLevelOf(table, pass.reach, level: level);
  final fringe = pass.iris.fringe / 500;
  final core = fringe > 0
      ? irisLevelOf(table, pass.reach, level: level, k: 1).rows
      : const <IrisRow>[];
  final (onOutline, onCore) = (coveredBy(outline.rows), coveredBy(core));
  final pushed = onOutline > onCore ? fringe : 0.0;
  return (
    reach: outline.reach,
    outline: outline.rows,
    core: core,
    pushed: pushed,
    weight: onOutline - onCore * pushed,
  );
}

/// The table [pass] lays (`iris_table.frag`), as floats: red, green, blue
/// and alpha a texel — of its [levels], one or a blur map's 256.
typedef IrisTable = ({Float32List texels, int width, int levels});

Future<IrisTable> irisTableOf(WidgetTester tester, IrisGatherPass pass) async {
  final table = IrisBlurShader.tableFor(pass.rows);
  addTearDown(table.dispose);
  final bytes = (await tester.runAsync(
    () => table.toByteData(format: ui.ImageByteFormat.rawExtendedRgba128),
  ))!;
  return (
    texels: bytes.buffer.asFloat32List(),
    width: table.width,
    levels: pass.map == null ? 1 : 256,
  );
}

/// Level [level]'s rows of the outline (k 0) or core (k 1), and what its
/// head says: its reach, and the centres that outline or core covers —
/// out of [table] laid for a pass reaching [reachMost].
({List<IrisRow> rows, int reach, double covered}) irisLevelOf(
  IrisTable table,
  int reachMost, {
  int level = 0,
  int k = 0,
}) {
  final rows = 2 * reachMost + 1;
  final rowsALine = math.min(rows, 1024);
  final linesALevel = (rows / rowsALine).ceil();
  double at(int row, int channel) {
    final line = level * linesALevel + row ~/ rowsALine;
    final column = (row % rowsALine) * 2 + k;
    return table.texels[(line * table.width + column) * 4 + channel];
  }

  final head = (table.levels * linesALevel + level ~/ table.width) *
          table.width +
      level % table.width;
  final reach = table.texels[head * 4].toInt();
  return (
    reach: reach,
    covered: table.texels[head * 4 + 1 + k],
    rows: [
      for (var dy = -reach; dy <= reach; dy += 1)
        (
          left: at(dy + reachMost, 0).toInt(),
          right: at(dy + reachMost, 1).toInt(),
        ),
    ],
  );
}

int coveredBy(List<IrisRow> rows) => rows.fold(
  0,
  (sum, row) => sum + math.max(0, row.right - row.left + 1),
);
