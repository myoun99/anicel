import 'dart:typed_data';

import '../models/brush_dab.dart';
import '../models/canvas_point.dart';
import 'canvas_selection.dart';
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
/// ⛔ONE CODE for the float and for every other stamp ([through]). The
/// float is simply the stamp whose rect the box stands on: there the quad's
/// corners are the box's own and the mesh needs no grid past its edge, so
/// the float lands the bytes it always landed.
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
}

/// Move · scale · rotate about the box's pivot.
final class AffineCarry extends StampCarry {
  const AffineCarry(this.affine, {required super.mode, super.within});

  final SelectionAffine affine;

  @override
  BrushDab through(BrushDab stamp, {SelectionVisibleRect? visible}) =>
      transformStampDab(stamp, affine, mode: mode, visible: visible ?? within);
}

/// A free quad (퍼스): the float's rect corners [base] went to [corners]
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

  @override
  BrushDab through(BrushDab stamp, {SelectionVisibleRect? visible}) {
    // The whole quad dragged by one delta carries every stamp by it,
    // byte for byte ([stampDabMovedWholesale]).
    final moved = stampDabMovedWholesale(stamp, base, corners);
    if (moved != null) {
      return moved;
    }
    final own = stampCornersOf(stamp);
    final h = own == null ? null : solveHomography(base, corners);
    if (own == null || h == null) {
      // No picture, or a quad too degenerate to warp through — which the
      // quad transform refuses the same way.
      return stamp;
    }
    return transformStampDabQuad(
      stamp,
      [
        for (var i = 0; i < own.length; i += 1)
          // ⛔The float's own corners go where the box put them, to the
          // bit: solving and re-applying the homography leaves a residue,
          // and the float must land what the preview showed.
          if (own[i] == base[i])
            corners[i]
          else
            applyHomography(h, own[i]),
      ],
      mode: mode,
      visible: visible ?? within,
    );
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

/// A mesh: the [grid] laid over the float's rect, and the canvas follows
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
    final over = _over(stamp);
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

  /// The grid, grown by whole cells until it covers [stamp]'s rect.
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
  /// A stamp the box already covers — the float itself — gets the grid back
  /// as it is.
  MeshGrid _over(BrushDab stamp) {
    final own = stampRectOf(stamp);
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
