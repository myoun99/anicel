import 'dart:typed_data';
import 'dart:ui' show Offset;

import '../core/point_bounds.dart';
import '../models/brush_dab.dart';
import '../models/canvas_point.dart';
import 'canvas_selection.dart';
import 'canvas_selection_region.dart';
import 'resample/resample_kernel.dart';

/// 🚨★★★**WHAT AN OPEN BOX DOES TO A STAMP, AS A MAPPING OF THE CANVAS.**
///
/// A transform box stands on its float and moves it — by an affine, through
/// a quad's four corners (퍼스), or through a mesh's grid. Each is a mapping
/// of the canvas, so any OTHER stamp standing on the canvas can be carried
/// through the same one: the cels a confirm over a frame range reaches
/// never floated anything, and each takes the transform on its own pixels
/// (F-116-b · F-164, 유저 2026-09-17: 「**동시적용은 가능하게**」 · H41,
/// 2026-09-24: 「선택도구 사용했으면 어떤프레임이든 선택도구 안쪽만, 아니면
/// 각자 그림 전체적용」).
///
/// ↩️Only the AFFINE travelled to those cels (`a-warp-over-a-frame-range-
/// lands-on-one-cel`, measured 2026-10-06): a quad or a mesh confirmed over
/// a range warped the cel you stood on and left every other cel as it was,
/// because the box's affine — all the confirm handed down — is the identity
/// under a warp.
///
/// ⛔ONE CODE for the float and for every other stamp ([through]). The box
/// stands on its own rect, the one 일반 draws (F-570), and the float is a
/// stamp like the rest: what it holds past that rect — the whole pixels its
/// edge rounds out to, a grow, a feather — follows the mapping on past the
/// edge, as another cel's picture does.
sealed class StampCarry {
  const StampCarry({required this.mode, this.within});

  /// How pixels are resampled — the tool's setting, the one the float took.
  final ResampleMode mode;

  /// Nothing is resampled past this rect: the pasteboard wall, past which
  /// nothing lands either (C-ipad-crash, 2026-09-11 — a picture scaled past
  /// the stage built pixels the commit then threw away).
  final SelectionVisibleRect? within;

  /// [stamp] — standing on the canvas — through the mapping. [visible]
  /// narrows the work to what a PREVIEW shows; a landing asks for all of it,
  /// up to [within].
  BrushDab through(BrushDab stamp, {SelectionVisibleRect? visible});

  /// [region] — standing on the canvas — through the mapping: a selection
  /// goes where its pixels go ([through]).
  ///
  /// 🚨ONE CODE for the pixels and the selection (card a-mesh-warp-turns-
  /// the-selection-into-its-box, 2026-11-21). ↩️The layer asked each warp
  /// of the selection itself, twice — as it confirmed and as its ants were
  /// drawn — and the mesh's answer was its grid's outer ring (R20-D3,
  /// 07-14, nobody's order): a lasso warped by the mesh became the box it
  /// stood in, holding pixels the mesh never moved, where the quad carried
  /// it whole.
  CanvasSelectionRegion regionThrough(CanvasSelectionRegion region);
}

/// Move · scale · rotate about the box's pivot.
final class AffineCarry extends StampCarry {
  const AffineCarry(this.affine, {required super.mode, super.within});

  final SelectionAffine affine;

  @override
  BrushDab through(BrushDab stamp, {SelectionVisibleRect? visible}) =>
      transformStampDab(stamp, affine, mode: mode, visible: visible ?? within);

  @override
  CanvasSelectionRegion regionThrough(CanvasSelectionRegion region) =>
      region.mapped(affine.apply);
}

/// A free quad (퍼스): the box's corners [base] went to [corners]
/// (TL · TR · BR · BL), and the canvas follows the homography between them.
final class QuadCarry extends StampCarry {
  const QuadCarry({
    required this.base,
    required this.corners,
    required super.mode,
    super.within,
  });

  final List<CanvasPoint> base;
  final List<CanvasPoint> corners;

  /// The quad transform's own, from the box's rect: the whole quad dragged
  /// by one delta carries every stamp by it, byte for byte, and a quad too
  /// degenerate to warp through moves no pixel.
  @override
  BrushDab through(BrushDab stamp, {SelectionVisibleRect? visible}) =>
      transformStampDabThroughQuad(
        stamp,
        (from: base, to: corners),
        mode: mode,
        visible: visible ?? within,
      );

  /// A quad too degenerate to warp through moves no pixel ([through]), and
  /// so no selection.
  @override
  CanvasSelectionRegion regionThrough(CanvasSelectionRegion region) {
    final h = solveHomography(base, corners);
    return h == null
        ? region
        : region.mapped((point) => applyHomography(h, point));
  }
}

/// A mesh's grid: `columns × rows` cells over the rect [base], its nodes at
/// [points] — row-major, `(columns + 1) * (rows + 1)` of them.
typedef MeshGrid = ({
  StampRect base,
  int columns,
  int rows,
  List<CanvasPoint> points,
});

/// A mesh: the [grid] laid over the box's rect, and the canvas follows
/// its cells.
final class MeshCarry extends StampCarry {
  const MeshCarry(this.grid, {required super.mode, super.within});

  final MeshGrid grid;

  StampRect get base => grid.base;
  int get columns => grid.columns;
  int get rows => grid.rows;
  List<CanvasPoint> get points => grid.points;

  @override
  BrushDab through(BrushDab stamp, {SelectionVisibleRect? visible}) {
    // The whole grid dragged by one delta carries every stamp by it, byte
    // for byte — asked of the box's OWN grid, as the quad asks it of its
    // own corners. ⛔Not left to the transform: a grid carried on past its
    // box ([_over]) restates the drag with a residue of its own (measured
    // on the default 3×3: sixteen different deltas where there was one),
    // and another cel's picture was resampled for a move.
    final moved = stampDabMovedWholesale(
      stamp,
      meshRestGrid(base, columns: columns, rows: rows),
      points,
    );
    if (moved != null) {
      return moved;
    }
    final over = _over(stampRectOf(stamp));
    return transformStampDabMesh(
      stamp,
      columns: over.columns,
      rows: over.rows,
      points: over.points,
      base: over.base,
      mode: mode,
      visible: visible ?? within,
    );
  }

  /// Each outline of [region] through the grid's cells, as [through]
  /// carries a pixel: a triangle of a cell at a time, split by its
  /// diagonal from top right to bottom left, the grid grown as a stamp's is
  /// past the box ([_over]). An edge is cut where it crosses a cell's side
  /// or diagonal — each triangle maps straight lines to straight lines, and
  /// the grid bends them where two meet.
  @override
  CanvasSelectionRegion regionThrough(CanvasSelectionRegion region) =>
      region.ringsThrough((ring) {
        final over = _over(_boundsOf(ring));
        return [
          for (var at = 0; at < ring.length; at += 1)
            for (final point in _cutWhereItBends(
              over,
              ring[at],
              ring[(at + 1) % ring.length],
            ))
              _pointThrough(over, point),
        ];
      });

  /// The grid, grown by whole cells until it covers the rect [own] — a
  /// stamp's, or a selection's outline's.
  ///
  /// 🚨A MESH IS DEFINED ON ITS BOX AND NOWHERE ELSE, and another cel's
  /// picture may reach past the box — it frames the STANDING cel's ink
  /// (H41: with nothing selected each cel is carried whole). Past the edge
  /// the grid goes on the way its outermost cells were heading: each new
  /// node sits one more edge-cell step out, so the mapping is continuous
  /// across the box's edge and the part of a drawing outside the box
  /// follows the part inside. ⛔Not left where it was (a tear along the
  /// box's edge) and not cut off (유저 H41: 「다른 프레임 그림의 잘려서
  /// 변형안먹힌 부분이 있었어」).
  ///
  /// A stamp the box already covers gets the grid back as it is.
  MeshGrid _over(StampRect? own) {
    final cellWidth = base.width / columns;
    final cellHeight = base.height / rows;
    int cellsPast(double overhang, double cell) =>
        overhang <= 0 ? 0 : (overhang / cell).ceil();
    final left = own == null ? 0 : cellsPast(base.left - own.left, cellWidth);
    final top = own == null ? 0 : cellsPast(base.top - own.top, cellHeight);
    final right = own == null
        ? 0
        : cellsPast(
            own.left + own.width - (base.left + base.width),
            cellWidth,
          );
    final bottom = own == null
        ? 0
        : cellsPast(
            own.top + own.height - (base.top + base.height),
            cellHeight,
          );
    if (left == 0 && top == 0 && right == 0 && bottom == 0) {
      return grid;
    }
    return (
      base: (
        left: base.left - left * cellWidth,
        top: base.top - top * cellHeight,
        width: (left + columns + right) * cellWidth,
        height: (top + rows + bottom) * cellHeight,
      ),
      columns: left + columns + right,
      rows: top + rows + bottom,
      points: [
        for (var row = -top; row <= rows + bottom; row += 1)
          for (var column = -left; column <= columns + right; column += 1)
            _nodeAt(column, row),
      ],
    );
  }

  /// The grid's node at ([column], [row]) — one of [points] inside the
  /// grid, and past its edge the edge's node carried on by the step the
  /// edge cell made, once a cell.
  CanvasPoint _nodeAt(int column, int row) {
    CanvasPoint at(int c, int r) => points[r * (columns + 1) + c];
    final c = column.clamp(0, columns);
    final r = row.clamp(0, rows);
    final edge = at(c, r);
    var x = edge.x;
    var y = edge.y;
    if (column != c) {
      final inner = at(c == 0 ? 1 : columns - 1, r);
      final cells = (column - c).abs();
      x += cells * (edge.x - inner.x);
      y += cells * (edge.y - inner.y);
    }
    if (row != r) {
      final inner = at(c, r == 0 ? 1 : rows - 1);
      final cells = (row - r).abs();
      x += cells * (edge.x - inner.x);
      y += cells * (edge.y - inner.y);
    }
    return CanvasPoint(x: x, y: y);
  }
}

/// The rect [ring]'s points span; null where it has none.
StampRect? _boundsOf(List<CanvasPoint> ring) {
  if (ring.isEmpty) {
    return null;
  }
  final bounds = pointsBounds([
    for (final point in ring) Offset(point.x, point.y),
  ]);
  return (
    left: bounds.left,
    top: bounds.top,
    width: bounds.width,
    height: bounds.height,
  );
}

/// [from] and the points past it on the way to [to] where the edge crosses
/// a side or a diagonal of [grid]'s cells, in order — [to] itself left to
/// the edge after.
List<CanvasPoint> _cutWhereItBends(
  MeshGrid grid,
  CanvasPoint from,
  CanvasPoint to,
) {
  final (u0, v0) = _cellUnits(grid, from);
  final (u1, v1) = _cellUnits(grid, to);
  final cuts = <double>{
    ..._crossings(u0, u1),
    ..._crossings(v0, v1),
    ..._crossings(u0 + v0, u1 + v1),
  }.toList()..sort();
  return [
    from,
    for (final t in cuts)
      CanvasPoint(
        x: from.x + t * (to.x - from.x),
        y: from.y + t * (to.y - from.y),
      ),
  ];
}

/// Where between 0 and 1, exclusive, a value going from [from] to [to]
/// passes a whole number.
Iterable<double> _crossings(double from, double to) sync* {
  if (from == to) {
    return;
  }
  final (low, high) = from < to ? (from, to) : (to, from);
  for (var whole = low.floor() + 1; whole < high; whole += 1) {
    yield (whole - from) / (to - from);
  }
}

/// [point] in [grid]'s cells: a cell a unit each way from its base's top
/// left.
(double, double) _cellUnits(MeshGrid grid, CanvasPoint point) => (
  (point.x - grid.base.left) / (grid.base.width / grid.columns),
  (point.y - grid.base.top) / (grid.base.height / grid.rows),
);

/// [point] through the triangle of [grid]'s cell it stands in — (top left,
/// top right, bottom left) on the top left side of the diagonal, (top
/// right, bottom right, bottom left) past it, as `transformStampDabMesh`
/// lays them: its place in the cell's rest triangle, at the same weights
/// of the nodes where they went.
CanvasPoint _pointThrough(MeshGrid grid, CanvasPoint point) {
  final (u, v) = _cellUnits(grid, point);
  final column = u.floor().clamp(0, grid.columns - 1);
  final row = v.floor().clamp(0, grid.rows - 1);
  final (across, down) = (u - column, v - row);
  CanvasPoint at(int c, int r) => grid.points[r * (grid.columns + 1) + c];
  final (topRight, bottomLeft) = (at(column + 1, row), at(column, row + 1));
  final (corner, weight) = across + down <= 1
      ? (at(column, row), 1 - across - down)
      : (at(column + 1, row + 1), across + down - 1);
  final (toRight, toBottom) = across + down <= 1
      ? (across, down)
      : (1 - down, 1 - across);
  return CanvasPoint(
    x: weight * corner.x + toRight * topRight.x + toBottom * bottomLeft.x,
    y: weight * corner.y + toRight * topRight.y + toBottom * bottomLeft.y,
  );
}

/// A point through the homography [h] ([solveHomography]'s nine numbers);
/// the point itself where the mapping has no answer (on its horizon).
CanvasPoint applyHomography(Float64List h, CanvasPoint point) {
  final w = h[6] * point.x + h[7] * point.y + h[8];
  if (w.abs() < 1e-12) {
    return point;
  }
  return CanvasPoint(
    x: (h[0] * point.x + h[1] * point.y + h[2]) / w,
    y: (h[3] * point.x + h[4] * point.y + h[5]) / w,
  );
}
