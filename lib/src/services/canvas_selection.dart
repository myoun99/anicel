import 'dart:math' as math;
import 'dart:typed_data';

import '../core/floor_math.dart';
import '../models/bitmap_surface.dart';
import '../models/pasteboard_bounds.dart';
import '../models/brush_dab.dart';
import '../models/brush_stamp_image.dart';
import '../models/brush_tip_shape.dart';
import '../models/canvas_point.dart';
import '../models/tile_coord.dart';
import 'canvas_selection_region.dart';

/// A selection region in canvas coordinates (P9): a closed polygon — the
/// rectangle marquee is its 4-corner special case, the lasso is the
/// freehand path as drawn.
class CanvasSelectionShape {
  CanvasSelectionShape(List<CanvasPoint> points)
    : points = List<CanvasPoint>.unmodifiable(points),
      assert(points.length >= 3, 'a selection polygon needs 3+ points');

  factory CanvasSelectionShape.rect({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    final minX = math.min(left, right);
    final maxX = math.max(left, right);
    final minY = math.min(top, bottom);
    final maxY = math.max(top, bottom);
    return CanvasSelectionShape([
      CanvasPoint(x: minX, y: minY),
      CanvasPoint(x: maxX, y: minY),
      CanvasPoint(x: maxX, y: maxY),
      CanvasPoint(x: minX, y: maxY),
    ]);
  }

  final List<CanvasPoint> points;

  /// Even-odd ray cast (the polygon closes implicitly).
  bool containsPoint(CanvasPoint point) {
    var inside = false;
    for (var i = 0, j = points.length - 1; i < points.length; j = i, i += 1) {
      final a = points[i];
      final b = points[j];
      final crosses =
          (a.y > point.y) != (b.y > point.y) &&
          point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x;
      if (crosses) {
        inside = !inside;
      }
    }
    return inside;
  }

  CanvasSelectionShape translated({required double dx, required double dy}) {
    return CanvasSelectionShape([
      for (final point in points) CanvasPoint(x: point.x + dx, y: point.y + dy),
    ]);
  }

  /// Value equality (R28-S: the composite region compares step by step,
  /// and the ants painter's [CustomPainter.shouldRepaint] rides on it).
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! CanvasSelectionShape || other.points.length != points.length) {
      return false;
    }
    for (var i = 0; i < points.length; i += 1) {
      if (other.points[i] != points[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(points);
}

/// The Ctrl+T free-transform affine (P9b), canvas space:
/// `p' = R(θ) · S(sx, sy) · (p − pivot) + pivot + t` — rotate/scale about
/// the fixed [pivot] (the base box center at session start), then
/// translate. Anchored handle scaling (Photoshop's opposite-corner
/// anchor) is expressed by compensating [tx]/[ty], so ONE composite
/// covers every handle interaction.
class SelectionAffine {
  const SelectionAffine({
    required this.pivot,
    this.sx = 1,
    this.sy = 1,
    this.rotationDegrees = 0,
    this.tx = 0,
    this.ty = 0,
  });

  final CanvasPoint pivot;
  final double sx;
  final double sy;
  final double rotationDegrees;
  final double tx;
  final double ty;

  bool get isIdentity =>
      sx == 1 && sy == 1 && rotationDegrees == 0 && tx == 0 && ty == 0;

  double get _radians => rotationDegrees * math.pi / 180;

  CanvasPoint apply(CanvasPoint point) {
    final lx = (point.x - pivot.x) * sx;
    final ly = (point.y - pivot.y) * sy;
    final cos = math.cos(_radians);
    final sin = math.sin(_radians);
    return CanvasPoint(
      x: lx * cos - ly * sin + pivot.x + tx,
      y: lx * sin + ly * cos + pivot.y + ty,
    );
  }

  SelectionAffine copyWith({
    double? sx,
    double? sy,
    double? rotationDegrees,
    double? tx,
    double? ty,
  }) {
    return SelectionAffine(
      pivot: pivot,
      sx: sx ?? this.sx,
      sy: sy ?? this.sy,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      tx: tx ?? this.tx,
      ty: ty ?? this.ty,
    );
  }
}

/// The selected dabs through [affine] (the Ctrl+T commit): centers map
/// exactly, the scalar dab size scales by √|sx·sy| (the plan's mapping —
/// non-uniform scale approximates through the area factor) and the tip
/// angle turns with the rotation. Brush properties otherwise untouched.
List<BrushDab> transformDabs(List<BrushDab> dabs, SelectionAffine affine) {
  final sizeScale = math.sqrt((affine.sx * affine.sy).abs());
  return [
    for (final dab in dabs)
      dab.copyWith(
        center: affine.apply(dab.center),
        size: math.max(dab.size * sizeScale, 0.01),
        angleDegrees: dab.angleDegrees + affine.rotationDegrees,
      ),
  ];
}

/// The selection region through [affine] — the ants follow the transform.
CanvasSelectionShape transformShape(
  CanvasSelectionShape shape,
  SelectionAffine affine,
) {
  return CanvasSelectionShape([
    for (final point in shape.points) affine.apply(point),
  ]);
}

/// The lifted stamp through [affine] as a RESAMPLED bitmap stamp (R19
/// pixel selection — Ctrl+T on raster truth):
///
/// - identity returns the dab untouched;
/// - a pure translation only moves the center — byte-exact, the same
///   arithmetic as a drag move;
/// - anything else resamples the stamp's straight-alpha RGBA into the
///   transformed region's axis-aligned bounding box with a Catmull-Rom
///   BICUBIC kernel (R20-D1 — the PS default-quality tier; noticeably
///   sharper than bilinear on rotate/scale). The kernel is interpolating
///   (δ at integer alignment), so axis-aligned 90° rotations stay EXACT
///   pixel permutations. Sampling is alpha-weighted so transparent
///   texels never bleed dark fringes; the negative lobes clamp at the
///   byte edge (the usual bicubic ringing contract).
BrushDab transformStampDab(BrushDab stampDab, SelectionAffine affine) {
  final stamp = stampDab.stamp;
  if (stamp == null || affine.isIdentity) {
    return stampDab;
  }
  if (affine.sx == 1 && affine.sy == 1 && affine.rotationDegrees == 0) {
    return stampDab.copyWith(
      center: CanvasPoint(
        x: stampDab.center.x + affine.tx,
        y: stampDab.center.y + affine.ty,
      ),
    );
  }

  // The stamp draws 1:1 about its center: its canvas-space source rect.
  final srcLeft = stampDab.center.x - stamp.width / 2;
  final srcTop = stampDab.center.y - stamp.height / 2;

  // Output AABB = the transformed source corners.
  final corners = [
    affine.apply(CanvasPoint(x: srcLeft, y: srcTop)),
    affine.apply(CanvasPoint(x: srcLeft + stamp.width, y: srcTop)),
    affine.apply(
      CanvasPoint(x: srcLeft + stamp.width, y: srcTop + stamp.height),
    ),
    affine.apply(CanvasPoint(x: srcLeft, y: srcTop + stamp.height)),
  ];
  var minX = corners.first.x, maxX = corners.first.x;
  var minY = corners.first.y, maxY = corners.first.y;
  for (final corner in corners.skip(1)) {
    minX = math.min(minX, corner.x);
    maxX = math.max(maxX, corner.x);
    minY = math.min(minY, corner.y);
    maxY = math.max(maxY, corner.y);
  }
  final outLeft = minX.floor();
  final outTop = minY.floor();
  final outWidth = math.max(1, maxX.ceil() - outLeft);
  final outHeight = math.max(1, maxY.ceil() - outTop);

  // Inverse mapping: q = R·S·(p − pivot) + pivot + t
  //              ⇒  p = S⁻¹·R⁻¹·(q − pivot − t) + pivot.
  final radians = affine.rotationDegrees * math.pi / 180;
  final cos = math.cos(radians);
  final sin = math.sin(radians);
  final invSx = 1 / affine.sx;
  final invSy = 1 / affine.sy;

  final source = stamp.rgba;
  final bytes = Uint8List(outWidth * outHeight * 4);
  for (var oy = 0; oy < outHeight; oy += 1) {
    final qy = outTop + oy + 0.5 - affine.pivot.y - affine.ty;
    for (var ox = 0; ox < outWidth; ox += 1) {
      final qx = outLeft + ox + 0.5 - affine.pivot.x - affine.tx;
      // R(−θ) then S⁻¹, back into stamp pixel space.
      final px = (qx * cos + qy * sin) * invSx + affine.pivot.x;
      final py = (-qx * sin + qy * cos) * invSy + affine.pivot.y;
      _bicubicSampleInto(
        bytes,
        (oy * outWidth + ox) * 4,
        source,
        stamp.width,
        stamp.height,
        px,
        py,
        srcLeft,
        srcTop,
      );
    }
  }

  return stampDab.copyWith(
    center: CanvasPoint(x: outLeft + outWidth / 2, y: outTop + outHeight / 2),
    size: math.max(outWidth, outHeight).toDouble(),
    stamp: BrushStampImage(
      id: '${stamp.id}-t${DateTime.now().microsecondsSinceEpoch}',
      width: outWidth,
      height: outHeight,
      rgba: bytes,
    ),
  );
}

/// Solves the 3×3 homography H mapping each `from[i]` onto `to[i]`
/// (4 point pairs, row-major 9 elements, h22 fixed at 1), via the
/// standard 8-unknown linear system with partial-pivot Gaussian
/// elimination. Null for degenerate quads (collinear/self-crossing
/// input) — callers refuse the warp rather than produce garbage.
Float64List? solveHomography(List<CanvasPoint> from, List<CanvasPoint> to) {
  assert(from.length == 4 && to.length == 4);
  // Rows: [x y 1 0 0 0 -x*u -y*u | u] and [0 0 0 x y 1 -x*v -y*v | v].
  final a = List.generate(8, (_) => Float64List(9));
  for (var i = 0; i < 4; i += 1) {
    final x = from[i].x, y = from[i].y;
    final u = to[i].x, v = to[i].y;
    a[i * 2]
      ..[0] = x
      ..[1] = y
      ..[2] = 1
      ..[6] = -x * u
      ..[7] = -y * u
      ..[8] = u;
    a[i * 2 + 1]
      ..[3] = x
      ..[4] = y
      ..[5] = 1
      ..[6] = -x * v
      ..[7] = -y * v
      ..[8] = v;
  }
  for (var column = 0; column < 8; column += 1) {
    var pivotRow = column;
    for (var row = column + 1; row < 8; row += 1) {
      if (a[row][column].abs() > a[pivotRow][column].abs()) {
        pivotRow = row;
      }
    }
    if (a[pivotRow][column].abs() < 1e-9) {
      return null;
    }
    final tmp = a[column];
    a[column] = a[pivotRow];
    a[pivotRow] = tmp;
    final pivot = a[column][column];
    for (var row = column + 1; row < 8; row += 1) {
      final factor = a[row][column] / pivot;
      if (factor == 0) {
        continue;
      }
      for (var k = column; k < 9; k += 1) {
        a[row][k] -= factor * a[column][k];
      }
    }
  }
  final h = Float64List(9);
  h[8] = 1;
  for (var row = 7; row >= 0; row -= 1) {
    var sum = a[row][8];
    for (var k = row + 1; k < 8; k += 1) {
      sum -= a[row][k] * h[k];
    }
    h[row] = sum / a[row][row];
  }
  return h;
}

/// The lifted stamp through a free QUAD (R20-D2 perspective transform,
/// the PS Ctrl+corner mode): [corners] are the destination positions of
/// the stamp rect's TL/TR/BR/BL corners in canvas space. Resamples with
/// the same alpha-weighted Catmull-Rom kernel as the affine path,
/// through the inverse homography. Corners exactly at the source rect =
/// untouched; a degenerate quad refuses (returns the dab unchanged).
BrushDab transformStampDabQuad(BrushDab stampDab, List<CanvasPoint> corners) {
  final stamp = stampDab.stamp;
  if (stamp == null) {
    return stampDab;
  }
  assert(corners.length == 4);
  final srcLeft = stampDab.center.x - stamp.width / 2;
  final srcTop = stampDab.center.y - stamp.height / 2;
  final base = [
    CanvasPoint(x: srcLeft, y: srcTop),
    CanvasPoint(x: srcLeft + stamp.width, y: srcTop),
    CanvasPoint(x: srcLeft + stamp.width, y: srcTop + stamp.height),
    CanvasPoint(x: srcLeft, y: srcTop + stamp.height),
  ];
  var identity = true;
  for (var i = 0; i < 4; i += 1) {
    if (corners[i].x != base[i].x || corners[i].y != base[i].y) {
      identity = false;
      break;
    }
  }
  if (identity) {
    return stampDab;
  }
  // dst → src directly: no matrix inversion, one solve.
  final h = solveHomography(corners, base);
  if (h == null) {
    return stampDab;
  }

  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final corner in corners) {
    minX = math.min(minX, corner.x);
    maxX = math.max(maxX, corner.x);
    minY = math.min(minY, corner.y);
    maxY = math.max(maxY, corner.y);
  }
  final outLeft = minX.floor();
  final outTop = minY.floor();
  final outWidth = math.max(1, maxX.ceil() - outLeft);
  final outHeight = math.max(1, maxY.ceil() - outTop);

  final source = stamp.rgba;
  final bytes = Uint8List(outWidth * outHeight * 4);
  for (var oy = 0; oy < outHeight; oy += 1) {
    final qy = outTop + oy + 0.5;
    for (var ox = 0; ox < outWidth; ox += 1) {
      final qx = outLeft + ox + 0.5;
      final w = h[6] * qx + h[7] * qy + h[8];
      if (w.abs() < 1e-12) {
        continue;
      }
      final px = (h[0] * qx + h[1] * qy + h[2]) / w;
      final py = (h[3] * qx + h[4] * qy + h[5]) / w;
      _bicubicSampleInto(
        bytes,
        (oy * outWidth + ox) * 4,
        source,
        stamp.width,
        stamp.height,
        px,
        py,
        srcLeft,
        srcTop,
      );
    }
  }

  return stampDab.copyWith(
    center: CanvasPoint(x: outLeft + outWidth / 2, y: outTop + outHeight / 2),
    size: math.max(outWidth, outHeight).toDouble(),
    stamp: BrushStampImage(
      id: '${stamp.id}-q${DateTime.now().microsecondsSinceEpoch}',
      width: outWidth,
      height: outHeight,
      rgba: bytes,
    ),
  );
}

/// The lifted stamp through a MESH warp (R20-D3): an n×m control grid
/// over the stamp rect, each cell split into two triangles with a fixed
/// diagonal; destination triangles inverse-map affinely (barycentric)
/// onto the source and sample with the same alpha-weighted Catmull-Rom
/// kernel. The preview renders the SAME triangulation, so what warps on
/// screen is what commits. [points] holds `(columns+1)*(rows+1)`
/// destination grid positions, row-major; the base grid is the stamp
/// rect subdivided uniformly. All points at base = untouched. Fold-overs
/// resolve by triangle order (first hit wins — deterministic).
BrushDab transformStampDabMesh(
  BrushDab stampDab, {
  required int columns,
  required int rows,
  required List<CanvasPoint> points,
}) {
  final stamp = stampDab.stamp;
  if (stamp == null || columns < 1 || rows < 1) {
    return stampDab;
  }
  assert(points.length == (columns + 1) * (rows + 1));
  final srcLeft = stampDab.center.x - stamp.width / 2;
  final srcTop = stampDab.center.y - stamp.height / 2;
  final cellWidth = stamp.width / columns;
  final cellHeight = stamp.height / rows;
  CanvasPoint baseAt(int column, int row) => CanvasPoint(
    x: srcLeft + column * cellWidth,
    y: srcTop + row * cellHeight,
  );

  var identity = true;
  for (var row = 0; row <= rows && identity; row += 1) {
    for (var column = 0; column <= columns; column += 1) {
      final base = baseAt(column, row);
      final point = points[row * (columns + 1) + column];
      if (point.x != base.x || point.y != base.y) {
        identity = false;
        break;
      }
    }
  }
  if (identity) {
    return stampDab;
  }

  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final point in points) {
    minX = math.min(minX, point.x);
    maxX = math.max(maxX, point.x);
    minY = math.min(minY, point.y);
    maxY = math.max(maxY, point.y);
  }
  final outLeft = minX.floor();
  final outTop = minY.floor();
  final outWidth = math.max(1, maxX.ceil() - outLeft);
  final outHeight = math.max(1, maxY.ceil() - outTop);
  final source = stamp.rgba;
  final bytes = Uint8List(outWidth * outHeight * 4);
  final covered = Uint8List(outWidth * outHeight);

  void rasterizeTriangle(
    CanvasPoint d0,
    CanvasPoint d1,
    CanvasPoint d2,
    CanvasPoint s0,
    CanvasPoint s1,
    CanvasPoint s2,
  ) {
    final denominator =
        (d1.x - d0.x) * (d2.y - d0.y) - (d2.x - d0.x) * (d1.y - d0.y);
    if (denominator.abs() < 1e-12) {
      return; // Degenerate destination triangle.
    }
    final left = math.max(
      outLeft,
      math.min(d0.x, math.min(d1.x, d2.x)).floor(),
    );
    final top = math.max(outTop, math.min(d0.y, math.min(d1.y, d2.y)).floor());
    final right = math.min(
      outLeft + outWidth,
      math.max(d0.x, math.max(d1.x, d2.x)).ceil(),
    );
    final bottom = math.min(
      outTop + outHeight,
      math.max(d0.y, math.max(d1.y, d2.y)).ceil(),
    );
    for (var y = top; y < bottom; y += 1) {
      final qy = y + 0.5;
      for (var x = left; x < right; x += 1) {
        final index = (y - outTop) * outWidth + (x - outLeft);
        if (covered[index] != 0) {
          continue;
        }
        final qx = x + 0.5;
        // Barycentric coordinates in the destination triangle.
        final w1 =
            ((qx - d0.x) * (d2.y - d0.y) - (d2.x - d0.x) * (qy - d0.y)) /
            denominator;
        final w2 =
            ((d1.x - d0.x) * (qy - d0.y) - (qx - d0.x) * (d1.y - d0.y)) /
            denominator;
        final w0 = 1.0 - w1 - w2;
        const slack = -1e-9;
        if (w0 < slack || w1 < slack || w2 < slack) {
          continue;
        }
        final px = s0.x * w0 + s1.x * w1 + s2.x * w2;
        final py = s0.y * w0 + s1.y * w1 + s2.y * w2;
        // The pixel is inside this triangle regardless of what it samples,
        // so it is covered even when the sampled color is fully transparent.
        covered[index] = 1;
        _bicubicSampleInto(
          bytes,
          index * 4,
          source,
          stamp.width,
          stamp.height,
          px,
          py,
          srcLeft,
          srcTop,
        );
      }
    }
  }

  CanvasPoint destAt(int column, int row) =>
      points[row * (columns + 1) + column];
  for (var row = 0; row < rows; row += 1) {
    for (var column = 0; column < columns; column += 1) {
      // Fixed diagonal TL–BR mirror of the preview triangulation:
      // (TL, TR, BL) and (TR, BR, BL).
      rasterizeTriangle(
        destAt(column, row),
        destAt(column + 1, row),
        destAt(column, row + 1),
        baseAt(column, row),
        baseAt(column + 1, row),
        baseAt(column, row + 1),
      );
      rasterizeTriangle(
        destAt(column + 1, row),
        destAt(column + 1, row + 1),
        destAt(column, row + 1),
        baseAt(column + 1, row),
        baseAt(column + 1, row + 1),
        baseAt(column, row + 1),
      );
    }
  }

  return stampDab.copyWith(
    center: CanvasPoint(x: outLeft + outWidth / 2, y: outTop + outHeight / 2),
    size: math.max(outWidth, outHeight).toDouble(),
    stamp: BrushStampImage(
      id: '${stamp.id}-m${DateTime.now().microsecondsSinceEpoch}',
      width: outWidth,
      height: outHeight,
      rgba: bytes,
    ),
  );
}

/// Catmull-Rom weights for taps at offsets {-1, 0, +1, +2} around the
/// floor sample, written into [out] (reused scratch — the resample loop
/// is per-pixel hot). Interpolating: f == 0 → (0, 1, 0, 0).
void _catmullRomWeights(double f, Float64List out) {
  final f2 = f * f;
  final f3 = f2 * f;
  out[0] = 0.5 * (-f3 + 2.0 * f2 - f);
  out[1] = 0.5 * (3.0 * f3 - 5.0 * f2 + 2.0);
  out[2] = 0.5 * (-3.0 * f3 + 4.0 * f2 + f);
  out[3] = 0.5 * (f3 - f2);
}

final Float64List _cubicWeightsX = Float64List(4);
final Float64List _cubicWeightsY = Float64List(4);

/// Bicubic (Catmull-Rom) resample of the stamp at source pixel [px], [py]
/// into [bytes] at [outOffset], premultiplied-weighted so transparent taps
/// never bleed. The three warp paths (affine, homography, mesh) differ only
/// in how they derive [px]/[py] — this is the sampling kernel they share,
/// byte-for-byte. Uses the shared per-pixel weight scratch; single-threaded
/// like its callers. Writes nothing when the accumulated coverage is zero.
void _bicubicSampleInto(
  Uint8List bytes,
  int outOffset,
  Uint8List source,
  int stampWidth,
  int stampHeight,
  double px,
  double py,
  double srcLeft,
  double srcTop,
) {
  final sampleX = px - srcLeft - 0.5;
  final sampleY = py - srcTop - 0.5;
  final x0 = sampleX.floor();
  final y0 = sampleY.floor();
  _catmullRomWeights(sampleX - x0, _cubicWeightsX);
  _catmullRomWeights(sampleY - y0, _cubicWeightsY);

  var alphaAcc = 0.0;
  var redAcc = 0.0, greenAcc = 0.0, blueAcc = 0.0;
  for (var tapJ = 0; tapJ < 4; tapJ += 1) {
    final tapY = y0 - 1 + tapJ;
    if (tapY < 0 || tapY >= stampHeight) {
      continue;
    }
    final weightY = _cubicWeightsY[tapJ];
    if (weightY == 0) {
      continue;
    }
    final rowOffset = tapY * stampWidth;
    for (var tapI = 0; tapI < 4; tapI += 1) {
      final tapX = x0 - 1 + tapI;
      if (tapX < 0 || tapX >= stampWidth) {
        continue;
      }
      final weight = _cubicWeightsX[tapI] * weightY;
      if (weight == 0) {
        continue;
      }
      final offset = (rowOffset + tapX) * 4;
      final alpha = source[offset + 3];
      if (alpha == 0) {
        continue;
      }
      final weightedAlpha = weight * alpha;
      alphaAcc += weightedAlpha;
      redAcc += weightedAlpha * source[offset];
      greenAcc += weightedAlpha * source[offset + 1];
      blueAcc += weightedAlpha * source[offset + 2];
    }
  }
  if (alphaAcc <= 0) {
    return;
  }
  bytes[outOffset] = (redAcc / alphaAcc).round().clamp(0, 255);
  bytes[outOffset + 1] = (greenAcc / alphaAcc).round().clamp(0, 255);
  bytes[outOffset + 2] = (blueAcc / alphaAcc).round().clamp(0, 255);
  bytes[outOffset + 3] = alphaAcc.round().clamp(0, 255);
}

/// The bitmap-lift pair (R14-④): an erase mask dab that cuts the
/// selection's pixels out of the layer at their origin, and a stamp dab
/// carrying those exact pixels — the Move tool commits the pair (origin
/// vanishes), then drags the STAMP dab alone. Both ride the ordinary
/// stroke funnel, so undo and .anicel serialization come free, and a
/// zero-move drop is byte-identical to the original by construction
/// (hard-edged mask: full erase + source-over of the same pixels).
class SelectionLiftDabs {
  const SelectionLiftDabs({required this.eraseDab, required this.stampDab});

  final BrushDab eraseDab;
  final BrushDab stampDab;
}

/// R26 (C2): optional selection-mask post-passes applied at LIFT time.
/// The DEFAULT keeps the mask hard-edged and byte-identical to the
/// classic path — the pure-move byte-preservation contract holds.
/// Grow/shrink, feather and edge anti-alias are opt-in; a soft mask
/// inherently trades exact byte preservation at the seam for the
/// softened boundary (two mul-div-255 round trips) — the same trade
/// CSP/PS make for feathered selections.
class SelectionMaskOptions {
  const SelectionMaskOptions({
    this.growPx = 0,
    this.featherPx = 0,
    this.antiAlias = false,
  });

  static const SelectionMaskOptions none = SelectionMaskOptions();

  /// Positive grows (dilates) the mask, negative shrinks (erodes) —
  /// one 4-neighbor pass per pixel, the fill expand pass's math.
  final int growPx;

  /// Inward alpha ramp width in pixels (0 = hard edge). Feathering is
  /// INWARD-only: pixels outside the selection stay unselected, so a
  /// feathered lift never grabs paint beyond the boundary.
  final double featherPx;

  /// One boundary-softening pass (the fill finish's anti-alias math).
  final bool antiAlias;

  bool get isHard => growPx == 0 && featherPx <= 0 && !antiAlias;

  SelectionMaskOptions copyWith({
    int? growPx,
    double? featherPx,
    bool? antiAlias,
  }) {
    return SelectionMaskOptions(
      growPx: growPx ?? this.growPx,
      featherPx: featherPx ?? this.featherPx,
      antiAlias: antiAlias ?? this.antiAlias,
    );
  }

  /// Extra bounding-box padding the post-passes may write into.
  int get bboxPad =>
      (growPx > 0 ? growPx : 0) + featherPx.ceil() + (antiAlias ? 1 : 0);
}

/// Grow (dilate) or shrink (erode) [mask] in place by [passes]
/// 4-neighbor generations — generation-exact like the fill expand.
void _growShrinkMask(Uint8List mask, int width, int height, int passes) {
  final grow = passes > 0;
  final count = passes.abs();
  var src = mask;
  var dst = Uint8List(mask.length);
  for (var pass = 0; pass < count; pass += 1) {
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final index = y * width + x;
        final center = src[index];
        if (grow ? center != 0 : center == 0) {
          dst[index] = center;
          continue;
        }
        final touches = grow
            ? ((x > 0 && src[index - 1] != 0) ||
                  (x < width - 1 && src[index + 1] != 0) ||
                  (y > 0 && src[index - width] != 0) ||
                  (y < height - 1 && src[index + width] != 0))
            : ((x > 0 && src[index - 1] == 0) ||
                  (x < width - 1 && src[index + 1] == 0) ||
                  (y > 0 && src[index - width] == 0) ||
                  (y < height - 1 && src[index + width] == 0) ||
                  x == 0 ||
                  x == width - 1 ||
                  y == 0 ||
                  y == height - 1);
        dst[index] = grow ? (touches ? 255 : 0) : (touches ? 0 : center);
      }
    }
    final swap = src;
    src = dst;
    dst = swap;
  }
  if (!identical(src, mask)) {
    mask.setAll(0, src);
  }
}

/// Inward feather: 3-4 chamfer distance from the OUTSIDE, alpha ramps
/// over [featherPx] (chamfer units: 3 per orthogonal pixel).
void _featherMask(Uint8List mask, int width, int height, double featherPx) {
  const infinity = 60000;
  final dist = Uint16List(width * height);
  for (var i = 0; i < mask.length; i += 1) {
    dist[i] = mask[i] == 0 ? 0 : infinity;
  }
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      final i = y * width + x;
      int best = dist[i];
      if (best == 0) continue;
      // Canvas-edge pixels ramp too (border counts as outside).
      if (x == 0 || y == 0 || x == width - 1 || y == height - 1) best = 3;
      if (x > 0 && dist[i - 1] + 3 < best) best = dist[i - 1] + 3;
      if (y > 0) {
        if (dist[i - width] + 3 < best) best = dist[i - width] + 3;
        if (x > 0 && dist[i - width - 1] + 4 < best) {
          best = dist[i - width - 1] + 4;
        }
        if (x < width - 1 && dist[i - width + 1] + 4 < best) {
          best = dist[i - width + 1] + 4;
        }
      }
      dist[i] = best > infinity ? infinity : best;
    }
  }
  for (var y = height - 1; y >= 0; y -= 1) {
    for (var x = width - 1; x >= 0; x -= 1) {
      final i = y * width + x;
      int best = dist[i];
      if (best == 0) continue;
      if (x < width - 1 && dist[i + 1] + 3 < best) best = dist[i + 1] + 3;
      if (y < height - 1) {
        if (dist[i + width] + 3 < best) best = dist[i + width] + 3;
        if (x < width - 1 && dist[i + width + 1] + 4 < best) {
          best = dist[i + width + 1] + 4;
        }
        if (x > 0 && dist[i + width - 1] + 4 < best) {
          best = dist[i + width - 1] + 4;
        }
      }
      dist[i] = best > infinity ? infinity : best;
    }
  }
  final ramp = featherPx * 3.0;
  for (var i = 0; i < mask.length; i += 1) {
    if (mask[i] == 0) continue;
    final alpha = (dist[i] / ramp * 255).round();
    mask[i] = alpha >= 255 ? 255 : alpha;
  }
}

/// One boundary soft pass — the fill finish's anti-alias math.
void _antiAliasMask(Uint8List mask, int width, int height) {
  final source = Uint8List.fromList(mask);
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      final index = y * width + x;
      final center = source[index];
      final left = x > 0 ? source[index - 1] : 0;
      final right = x < width - 1 ? source[index + 1] : 0;
      final up = y > 0 ? source[index - width] : 0;
      final down = y < height - 1 ? source[index + width] : 0;
      final sum = center + left + right + up + down;
      if (sum != center * 5) {
        mask[index] = ((center * 3 + (sum - center)) / 7).round();
      }
    }
  }
}

/// Builds the lift pair for [region] over the active layer's committed
/// [surface]. Null when the selection covers no canvas pixels. The mask is
/// HARD-EDGED (a pixel is in or out by its center, the same even-odd rule
/// as [CanvasSelectionRegion.containsPoint]) — partial coverage would make
/// erase + stamp lose paint at the seam.
SelectionLiftDabs? buildSelectionLiftDabs({
  required CanvasSelectionRegion region,
  required BitmapSurface surface,
  required String liftId,
  SelectionMaskOptions options = SelectionMaskOptions.none,
}) {
  // Pasteboard clip, not canvas — off-canvas artwork is selectable and
  // liftable (the whole point of moving things on and off the stage).
  final canvasSize = surface.canvasSize;
  final regionBounds = region.bounds;
  final minX = regionBounds.left;
  final minY = regionBounds.top;
  final maxX = regionBounds.right;
  final maxY = regionBounds.bottom;
  // R26: grow/feather/AA may write beyond the polygon's bbox.
  final pad = options.bboxPad;
  final left = math.max(canvasSize.pasteboardLeft, minX.floor() - pad);
  final top = math.max(canvasSize.pasteboardTop, minY.floor() - pad);
  final rightExclusive = math.min(
    canvasSize.pasteboardRightExclusive,
    maxX.ceil() + 1 + pad,
  );
  final bottomExclusive = math.min(
    canvasSize.pasteboardBottomExclusive,
    maxY.ceil() + 1 + pad,
  );
  if (rightExclusive <= left || bottomExclusive <= top) {
    return null;
  }
  final width = rightExclusive - left;
  final height = bottomExclusive - top;

  // Even-odd scanline mask over the bbox, folded step by step (R26 #16 —
  // the composite region's own rasterizer): O(edges × rows + pixels),
  // where the naive per-pixel ray cast made lasso lifts quadratic.
  final mask = region.maskFor(
    left: left,
    top: top,
    width: width,
    height: height,
  );

  // R26 opt-in mask post-passes (defaults leave the classic hard mask
  // byte-identical). Order: resize the region first, then soften.
  if (!options.isHard) {
    if (options.growPx != 0) {
      _growShrinkMask(mask, width, height, options.growPx);
    }
    if (options.featherPx > 0) {
      _featherMask(mask, width, height, options.featherPx);
    }
    if (options.antiAlias) {
      _antiAliasMask(mask, width, height);
    }
  }

  // Lift the surface pixels under the mask (straight alpha, byte copies —
  // tile buffers snapshot once per tile).
  final rgba = Uint8List(width * height * 4);
  final tileSize = surface.tileSize;
  var liftedAnything = false;
  final tileCache = <TileCoord, Uint8List?>{};
  for (var row = 0; row < height; row += 1) {
    final y = top + row;
    for (var col = 0; col < width; col += 1) {
      if (mask[row * width + col] == 0) {
        continue;
      }
      final x = left + col;
      // floorDiv, not ~/: pasteboard pixels sit at negative coords (Dart's
      // % already floor-mods for a positive divisor, so the local offset
      // below is correct as-is).
      final coord = TileCoord(
        x: floorDiv(x, tileSize),
        y: floorDiv(y, tileSize),
      );
      final pixels = tileCache.putIfAbsent(
        coord,
        () => surface.tiles[coord]?.pixels,
      );
      if (pixels == null) {
        continue;
      }
      final sourceOffset = ((y % tileSize) * tileSize + (x % tileSize)) * 4;
      if (pixels[sourceOffset + 3] == 0) {
        continue;
      }
      final targetOffset = (row * width + col) * 4;
      rgba[targetOffset] = pixels[sourceOffset];
      rgba[targetOffset + 1] = pixels[sourceOffset + 1];
      rgba[targetOffset + 2] = pixels[sourceOffset + 2];
      final maskValue = mask[row * width + col];
      if (maskValue == 255) {
        rgba[targetOffset + 3] = pixels[sourceOffset + 3];
      } else {
        // Soft mask (R26): the stamp carries alpha scaled by coverage,
        // matching the erase's partial removal at the same pixel —
        // Skia's mul-div-255 rounding, like the overlay pipeline.
        final product = pixels[sourceOffset + 3] * maskValue + 128;
        rgba[targetOffset + 3] = (product + (product >> 8)) >> 8;
      }
      liftedAnything = true;
    }
  }
  if (!liftedAnything) {
    return null;
  }

  // The erase rides the STAMP path too (R15-④): destination-out from the
  // exact mask bytes — tip-mask erases resample bilinearly and left a
  // half-alpha ring at the silhouette (the fringe + origin remnant).
  final eraseAlpha = Uint8List(width * height * 4);
  for (var index = 0; index < mask.length; index += 1) {
    eraseAlpha[index * 4 + 3] = mask[index];
  }
  final eraseDab = BrushDab(
    center: CanvasPoint(x: left + width / 2, y: top + height / 2),
    color: 0xFF000000,
    size: math.max(width, height).toDouble(),
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
    stamp: BrushStampImage(
      id: 'lift-erase-$liftId',
      width: width,
      height: height,
      rgba: eraseAlpha,
    ),
    erase: true,
  );
  final stampDab = BrushDab(
    center: CanvasPoint(x: left + width / 2, y: top + height / 2),
    color: 0xFF000000,
    size: math.max(width, height).toDouble(),
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 1,
    stamp: BrushStampImage(
      id: 'lift-stamp-$liftId',
      width: width,
      height: height,
      rgba: rgba,
    ),
  );
  return SelectionLiftDabs(eraseDab: eraseDab, stampDab: stampDab);
}
