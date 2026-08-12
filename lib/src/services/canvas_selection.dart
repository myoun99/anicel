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
import 'resample/resample_kernel.dart';
import 'resample/selection_resample.dart';

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

  /// The ellipse inscribed in the drag's box, as a polygon.
  ///
  /// A polygon because that is the only thing the region model knows how to
  /// be — membership is an even-odd ray cast and the mask is a scanline
  /// fill, and both of those are already exact for a polygon of any size.
  /// So the question is not "curve or polygon" but how many sides, and the
  /// answer comes from the RADIUS: [_ellipseSegments] picks the smallest
  /// count whose chord sags less than half a canvas pixel. A small ellipse
  /// gets a dozen sides and a huge one gets hundreds, and neither pays for
  /// the other.
  ///
  /// Segments are canvas-space, not screen-space, deliberately: the mask is
  /// rasterized in canvas space, so a zoomed-in view shows more of the same
  /// polygon rather than a smoother one. Anything else would make the
  /// committed pixels depend on the zoom they were committed at.
  factory CanvasSelectionShape.ellipse({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    final centerX = (left + right) / 2;
    final centerY = (top + bottom) / 2;
    final radiusX = (right - left).abs() / 2;
    final radiusY = (bottom - top).abs() / 2;
    final segments = _ellipseSegments(math.max(radiusX, radiusY));
    return CanvasSelectionShape([
      for (var i = 0; i < segments; i += 1)
        () {
          final angle = 2 * math.pi * i / segments;
          return CanvasPoint(
            x: centerX + radiusX * math.cos(angle),
            y: centerY + radiusY * math.sin(angle),
          );
        }(),
    ]);
  }

  /// Sides enough that the chord sags less than [_ellipseSagPx] from the
  /// true arc: for radius r and n sides the sag is `r · (1 − cos(π/n))`,
  /// solved for n. Clamped at both ends — the floor keeps a tiny ellipse
  /// from degenerating into a triangle, and the ceiling keeps a huge one
  /// from turning a selection into a point cloud.
  static int _ellipseSegments(double radius) {
    if (radius <= _ellipseSagPx) {
      return _ellipseMinSegments;
    }
    final exact = math.pi / math.acos(1 - _ellipseSagPx / radius);
    return exact.ceil().clamp(_ellipseMinSegments, _ellipseMaxSegments);
  }

  static const double _ellipseSagPx = 0.5;
  static const int _ellipseMinSegments = 12;
  static const int _ellipseMaxSegments = 512;

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
    if (other is! CanvasSelectionShape ||
        other.points.length != points.length) {
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

  /// The rotation's cosine and sine, EXACT at the quarter turns.
  ///
  /// `math.cos(pi / 2)` is 6.1e-17, not zero, and that residue is enough to
  /// make a quarter turn miss the resampler's lattice: destination pixel
  /// centres land a hair off source pixel centres, the footprint reaches a
  /// neighbour it should not, and "rotating by 90° gives back the same
  /// pixels" becomes a rounding accident rather than a guarantee. Reading
  /// the table for exact multiples of 90 makes it structural.
  ///
  /// Both the geometry ([apply], which moves the selection outline) and the
  /// pixels (the resample fold) read these, so the ants and the picture can
  /// never disagree about where the rotation went.
  double get cosTheta {
    final quarter = _exactQuarterTurn;
    return quarter == null ? math.cos(_radians) : _quarterCos[quarter];
  }

  double get sinTheta {
    final quarter = _exactQuarterTurn;
    return quarter == null ? math.sin(_radians) : _quarterSin[quarter];
  }

  /// 0/1/2/3 for an exact 0/90/180/270, null for anything in between.
  int? get _exactQuarterTurn {
    if (rotationDegrees % 90 != 0 || !rotationDegrees.isFinite) {
      return null;
    }
    final quarter = (rotationDegrees ~/ 90) % 4;
    return quarter < 0 ? quarter + 4 : quarter;
  }

  static const List<double> _quarterCos = <double>[1, 0, -1, 0];
  static const List<double> _quarterSin = <double>[0, 1, 0, -1];

  CanvasPoint apply(CanvasPoint point) {
    final lx = (point.x - pivot.x) * sx;
    final ly = (point.y - pivot.y) * sy;
    final cos = cosTheta;
    final sin = sinTheta;
    return CanvasPoint(
      x: lx * cos - ly * sin + pivot.x + tx,
      y: lx * sin + ly * cos + pivot.y + ty,
    );
  }

  /// [apply] run backwards: the pre-image of a canvas point.
  ///
  /// The perspective and mesh modes hold their control points as
  /// displacements in the box's OWN frame, so that rotating or scaling the
  /// box carries the warp with it instead of leaving it behind. Turning a
  /// pointer position into one of those displacements is this function.
  ///
  /// The scales cannot be zero — every writer clamps them away from it —
  /// so there is no degenerate case to guard.
  CanvasPoint applyInverse(CanvasPoint point) {
    final ux = point.x - pivot.x - tx;
    final uy = point.y - pivot.y - ty;
    final cos = cosTheta;
    final sin = sinTheta;
    final lx = ux * cos + uy * sin;
    final ly = -ux * sin + uy * cos;
    return CanvasPoint(x: lx / sx + pivot.x, y: ly / sy + pivot.y);
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

/// The integer canvas rect a warp lands in: the bounding box of [points],
/// snapped outward.
///
/// Shared by all three warps so their geometry cannot drift apart — they
/// each had their own copy of this loop, and three copies of a bounding
/// box is three chances for one of them to snap the wrong way.
({int left, int top, int width, int height}) selectionWarpOutputRect(
  List<CanvasPoint> points,
) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final point in points) {
    minX = math.min(minX, point.x);
    maxX = math.max(maxX, point.x);
    minY = math.min(minY, point.y);
    maxY = math.max(maxY, point.y);
  }
  final left = minX.floor();
  final top = minY.floor();
  return (
    left: left,
    top: top,
    width: math.max(1, maxX.ceil() - left),
    height: math.max(1, maxY.ceil() - top),
  );
}

/// A canvas-space rectangle a PREVIEW only has to cover.
typedef SelectionVisibleRect = ({
  double left,
  double top,
  double right,
  double bottom,
});

/// Which part of [out] a preview actually has to compute, in
/// output-pixel coordinates relative to `out.left`/`out.top` — or null
/// when the answer is "all of it".
///
/// A whole-picture transform is millions of pixels and a viewport is
/// under one, so a preview that resamples the whole rect spends most of
/// a pointer move on pixels nobody can see. Returning null for the cases
/// that ARE fully visible matters as much as clipping the ones that are
/// not: an unclipped result is the one the commit can reuse, and most
/// selections are small enough to stay on that path.
///
/// Never empty. A transform dragged entirely off screen still yields one
/// pixel rather than a zero-sized buffer, because "nothing to draw" is
/// the caller's business and a degenerate allocation is nobody's.
({int x, int y, int width, int height})? selectionPreviewWindow({
  required ({int left, int top, int width, int height}) out,
  required SelectionVisibleRect? visible,
}) {
  if (visible == null) {
    return null;
  }
  final x = math.max(0, visible.left.floor() - out.left);
  final y = math.max(0, visible.top.floor() - out.top);
  final right = math.min(out.width, visible.right.ceil() - out.left);
  final bottom = math.min(out.height, visible.bottom.ceil() - out.top);
  if (x == 0 && y == 0 && right >= out.width && bottom >= out.height) {
    return null;
  }
  return (
    x: math.min(x, out.width - 1),
    y: math.min(y, out.height - 1),
    width: math.max(1, right - x),
    height: math.max(1, bottom - y),
  );
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
///   transformed region's axis-aligned bounding box through the shared
///   kernel (P3a), in [mode]: a tent mean, or the coverage argmax that
///   copies source words through untouched.
///
/// The kernel replaced a Catmull-Rom bicubic. A cubic has negative lobes,
/// and a negative lobe beside a dark line emits a pixel BRIGHTER than
/// anything in its own footprint — the pale halo that made free transform
/// unusable on line art. A tent is a convex combination, so the halo cannot
/// exist by construction.
///
/// The returned center is `outLeft + outWidth / 2` with both terms
/// integers, so it rounds back to exactly `outLeft` where the stamp lands
/// (`bitmap_surface_brush_commit.dart`). That is what makes byte identity
/// between what the preview showed and what Enter writes reachable at all:
/// the resampled buffer travels to the surface without a second resample.
///
/// ⚠️ There is NO `clip` parameter, and there was not one when this
/// paragraph described it. The clipped preview was added and then reverted
/// inside its own branch — a sweep found 241 of 400 transforms where a
/// clipped resample differs from the same region of an unclipped one, so
/// the byte identity the paragraph claimed was false. The orphan text
/// outlived the code by long enough to send a rendering investigation
/// hunting a mechanism that does not exist.
BrushDab transformStampDab(
  BrushDab stampDab,
  SelectionAffine affine, {
  ResampleMode mode = ResampleMode.blend,
  SelectionVisibleRect? visible,
}) {
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
  final out = selectionWarpOutputRect(corners);
  final window = selectionPreviewWindow(out: out, visible: visible);

  return _resampleIntoWindow(
    stampDab: stampDab,
    stamp: stamp,
    out: out,
    window: window,
    // The FULL rect's matrix, always. A window keeps the whole rect's
    // pixel grid and says where it sits; folding the offset into the
    // origin instead is the version that is equal in arithmetic and not
    // in doubles — see ABI 26.
    transform: selectionAffineResampleTransform(
      affine: affine,
      srcLeft: srcLeft,
      srcTop: srcTop,
      outLeft: out.left,
      outTop: out.top,
    ),
    mode: mode,
  );
}

/// Runs one resample into [window] of [out] (or all of [out] when window
/// is null) and wraps the result as a dab positioned at what it covers.
///
/// ⚠️ A WINDOWED result is a PREVIEW. It holds only the pixels asked for,
/// so committing it would land a rectangle of the picture and drop the
/// rest. The one caller that clips keys its cache on the window, so the
/// commit — which asks for no window — cannot be handed one by mistake.
BrushDab _resampleIntoWindow({
  required BrushDab stampDab,
  required BrushStampImage stamp,
  required ({int left, int top, int width, int height}) out,
  required ({int x, int y, int width, int height})? window,
  required ResampleTransform transform,
  required ResampleMode mode,
  String idPrefix = 't',
}) {
  final clipX = window?.x ?? 0;
  final clipY = window?.y ?? 0;
  final dstWidth = window?.width ?? out.width;
  final dstHeight = window?.height ?? out.height;
  final bytes = Uint8List(dstWidth * dstHeight * 4);
  resampleSelectionInto(
    src: stamp.rgba,
    srcWidth: stamp.width,
    srcHeight: stamp.height,
    dst: bytes,
    dstWidth: dstWidth,
    dstHeight: dstHeight,
    transform: transform,
    mode: mode,
    clipX: clipX,
    clipY: clipY,
  );
  return stampDab.copyWith(
    center: CanvasPoint(
      x: out.left + clipX + dstWidth / 2,
      y: out.top + clipY + dstHeight / 2,
    ),
    size: math.max(dstWidth, dstHeight).toDouble(),
    stamp: BrushStampImage(
      id: '${stamp.id}-$idPrefix${DateTime.now().microsecondsSinceEpoch}',
      width: dstWidth,
      height: dstHeight,
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
/// the stamp rect's TL/TR/BR/BL corners in canvas space. Resamples through
/// the inverse homography with the same shared kernel and [mode] the affine
/// path uses. Corners exactly at the source rect = untouched; every corner
/// moved by the SAME delta is a pure translation and travels byte-exact; a
/// degenerate quad refuses (returns the dab unchanged).
BrushDab transformStampDabQuad(
  BrushDab stampDab,
  List<CanvasPoint> corners, {
  ResampleMode mode = ResampleMode.blend,
  SelectionVisibleRect? visible,
}) {
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
  // Identity, and the pure translation that the affine path short-circuits
  // at the top. Dragging the whole quad is reachable, and without this it
  // would run the per-pixel vote: solveHomography's elimination leaves a
  // ~1e-15 residue, so the kernel's own whole-pixel-translation circuit
  // never fires here no matter how exactly the user dragged.
  final deltaX = corners[0].x - base[0].x;
  final deltaY = corners[0].y - base[0].y;
  var translationOnly = true;
  for (var i = 1; i < 4; i += 1) {
    if (corners[i].x - base[i].x != deltaX ||
        corners[i].y - base[i].y != deltaY) {
      translationOnly = false;
      break;
    }
  }
  if (translationOnly) {
    if (deltaX == 0 && deltaY == 0) {
      return stampDab;
    }
    return stampDab.copyWith(
      center: CanvasPoint(
        x: stampDab.center.x + deltaX,
        y: stampDab.center.y + deltaY,
      ),
    );
  }
  // dst → src directly: no matrix inversion, one solve.
  final h = solveHomography(corners, base);
  if (h == null) {
    return stampDab;
  }

  final out = selectionWarpOutputRect(corners);
  // The per-pixel `w ≈ 0` guard the old loop carried lives in the kernel
  // now, along with a non-finite check the old one did not have. Both write
  // the outside token where this used to leave the pixel untouched, which
  // is the same thing on a freshly allocated buffer.
  return _resampleIntoWindow(
    stampDab: stampDab,
    stamp: stamp,
    out: out,
    window: selectionPreviewWindow(out: out, visible: visible),
    transform: selectionQuadResampleTransform(
      h: h,
      srcLeft: srcLeft,
      srcTop: srcTop,
      outLeft: out.left,
      outTop: out.top,
    ),
    mode: mode,
    idPrefix: 'q',
  );
}

/// The lifted stamp through a MESH warp (R20-D3): an n×m control grid
/// over the stamp rect, each cell split into two triangles with a fixed
/// diagonal. [points] holds `(columns+1)*(rows+1)` destination grid
/// positions, row-major; the base grid is the stamp rect subdivided
/// uniformly. All points at base = untouched, all points moved by one
/// delta = a pure translation. Fold-overs resolve by triangle order (first
/// hit wins — deterministic).
///
/// Barycentric interpolation of the three source corners is an AFFINE
/// function of the destination point, so each triangle is one ordinary
/// call into the shared kernel over its clipped bounding box, in [mode].
/// What stays in Dart is the triangle's insideness test and the `covered`
/// map: the kernel has no notion of a clip or of coverage and writes EVERY
/// pixel of the rectangle it is given, so a single whole-output call would
/// erase each triangle with the next one and lose fold-over resolution
/// entirely.
BrushDab transformStampDabMesh(
  BrushDab stampDab, {
  required int columns,
  required int rows,
  required List<CanvasPoint> points,
  ResampleMode mode = ResampleMode.blend,
  SelectionVisibleRect? visible,
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

  // Identity and pure translation, for the same reason the quad path has
  // both: dragging the whole grid is reachable and must not resample.
  final deltaX = points[0].x - baseAt(0, 0).x;
  final deltaY = points[0].y - baseAt(0, 0).y;
  var translationOnly = true;
  for (var row = 0; row <= rows && translationOnly; row += 1) {
    for (var column = 0; column <= columns; column += 1) {
      final base = baseAt(column, row);
      final point = points[row * (columns + 1) + column];
      if (point.x - base.x != deltaX || point.y - base.y != deltaY) {
        translationOnly = false;
        break;
      }
    }
  }
  if (translationOnly) {
    if (deltaX == 0 && deltaY == 0) {
      return stampDab;
    }
    return stampDab.copyWith(
      center: CanvasPoint(
        x: stampDab.center.x + deltaX,
        y: stampDab.center.y + deltaY,
      ),
    );
  }

  final out = selectionWarpOutputRect(points);
  final outLeft = out.left;
  final outTop = out.top;
  final outWidth = out.width;
  final outHeight = out.height;
  final bytes = Uint8List(outWidth * outHeight * 4);
  final covered = Uint8List(outWidth * outHeight);
  // One scratch grown across the triangles of THIS call — not a
  // module-level buffer. The Catmull-Rom this replaced kept its weights in
  // top-level mutable state shared by all three warp paths, which is
  // exactly the thing that stops being safe the moment anything runs off
  // the main isolate.
  var scratch = Uint8List(0);

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
    // The mesh clips per TRIANGLE rather than per output buffer: each one
    // already resamples only its own bounding box, so narrowing that box
    // to what is on screen skips the off-screen work without disturbing
    // the shared `bytes`/`covered` indexing. A preview asks for the
    // visible rect; a commit asks for nothing and gets the whole mesh.
    final left = math.max(
      visible == null ? outLeft : math.max(outLeft, visible.left.floor()),
      math.min(d0.x, math.min(d1.x, d2.x)).floor(),
    );
    final top = math.max(
      visible == null ? outTop : math.max(outTop, visible.top.floor()),
      math.min(d0.y, math.min(d1.y, d2.y)).floor(),
    );
    final right = math.min(
      visible == null
          ? outLeft + outWidth
          : math.min(outLeft + outWidth, visible.right.ceil()),
      math.max(d0.x, math.max(d1.x, d2.x)).ceil(),
    );
    final bottom = math.min(
      visible == null
          ? outTop + outHeight
          : math.min(outTop + outHeight, visible.bottom.ceil()),
      math.max(d0.y, math.max(d1.y, d2.y)).ceil(),
    );
    final tileWidth = right - left;
    final tileHeight = bottom - top;
    if (tileWidth <= 0 || tileHeight <= 0) {
      return;
    }
    // Resample the triangle's whole bounding box, then keep only the
    // pixels inside it. The kernel reads the WHOLE source stamp, never a
    // per-triangle crop, so a footprint straddling a source-triangle edge
    // picks up its neighbour's texels exactly as the bicubic taps did —
    // seam continuity for free.
    final needed = tileWidth * tileHeight * 4;
    if (scratch.length < needed) {
      scratch = Uint8List(needed);
    }
    resampleSelectionInto(
      src: stamp.rgba,
      srcWidth: stamp.width,
      srcHeight: stamp.height,
      dst: scratch,
      dstWidth: tileWidth,
      dstHeight: tileHeight,
      transform: selectionTriangleResampleTransform(
        d0: d0,
        d1: d1,
        d2: d2,
        s0: s0,
        s1: s1,
        s2: s2,
        denominator: denominator,
        left: left,
        top: top,
        srcLeft: srcLeft,
        srcTop: srcTop,
      ),
      mode: mode,
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
        // The pixel is inside this triangle regardless of what it samples,
        // so it is covered even when the sampled color is fully transparent.
        covered[index] = 1;
        final from = ((y - top) * tileWidth + (x - left)) * 4;
        final to = index * 4;
        bytes[to] = scratch[from];
        bytes[to + 1] = scratch[from + 1];
        bytes[to + 2] = scratch[from + 2];
        bytes[to + 3] = scratch[from + 3];
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

/// Copies the surface's pixels under [mask] into a `width x height`
/// straight-alpha RGBA buffer, scaling alpha by the mask where it is
/// partial. `liftedAnything` is false when the mask found nothing.
///
/// TILE-MAJOR, and the walk order is the whole cost of a lift. Going by
/// destination rows meant asking which tile every single pixel belonged
/// to: a [TileCoord] allocation and a map lookup per pixel of the bbox —
/// 3.9 million of them for a whole-picture lift on the shipping canvas —
/// and behind that map, `surface.tiles[coord]?.pixels`, which is a copy
/// of the cel's ENTIRE tile map followed by a 256 KB defensive copy of
/// the tile. Grabbing a handle to start a transform froze for 263-283 ms
/// on a realistic character cel and about 78% of it was here. Walking the
/// tiles, and the pixels inside them, makes the question free: measured
/// 251.9 ms -> 29.6 ms in canvas, 314.2 -> 49.9 with a pasteboard
/// overhang.
///
/// The result is byte-identical by construction rather than by hope:
/// every destination pixel belongs to exactly one tile, so this writes
/// the same bytes to the same places in a different order, and
/// `liftedAnything` is an OR. Pulled out of [buildSelectionLiftDabs] so a
/// test can hold it against a per-pixel reference across bboxes that
/// straddle tile edges — the axis the rewrite changed and the one the
/// lift's existing tests do not exercise.
({Uint8List rgba, bool liftedAnything}) gatherMaskedSurfacePixels({
  required BitmapSurface surface,
  required Uint8List mask,
  required int left,
  required int top,
  required int width,
  required int height,
}) {
  final rgba = Uint8List(width * height * 4);
  final tileSize = surface.tileSize;
  final rightExclusive = left + width;
  final bottomExclusive = top + height;
  var liftedAnything = false;
  // floorDiv, not ~/: pasteboard tiles sit at negative coordinates.
  final firstTileX = floorDiv(left, tileSize);
  final lastTileX = floorDiv(rightExclusive - 1, tileSize);
  final lastTileY = floorDiv(bottomExclusive - 1, tileSize);
  for (var ty = floorDiv(top, tileSize); ty <= lastTileY; ty += 1) {
    final tileTop = ty * tileSize;
    final y0 = math.max(top, tileTop);
    final y1 = math.min(bottomExclusive, tileTop + tileSize);
    for (var tx = firstTileX; tx <= lastTileX; tx += 1) {
      final tile = surface.tileAt(TileCoord(x: tx, y: ty));
      if (tile == null) {
        continue;
      }
      final tileLeft = tx * tileSize;
      final x0 = math.max(left, tileLeft);
      final x1 = math.min(rightExclusive, tileLeft + tileSize);
      // `readPixels`, so the tile's bytes are read in place and the view
      // never leaves the callback — that is the lifetime rule, and the
      // `pixels` getter it replaces was the 256 KB copy.
      tile.readPixels((_, pixels) {
        for (var y = y0; y < y1; y += 1) {
          final rowBase = (y - top) * width;
          final sourceRowBase = (y - tileTop) * tileSize;
          for (var x = x0; x < x1; x += 1) {
            final col = x - left;
            final maskValue = mask[rowBase + col];
            if (maskValue == 0) {
              continue;
            }
            final sourceOffset = (sourceRowBase + (x - tileLeft)) * 4;
            final sourceAlpha = pixels[sourceOffset + 3];
            if (sourceAlpha == 0) {
              continue;
            }
            final targetOffset = (rowBase + col) * 4;
            rgba[targetOffset] = pixels[sourceOffset];
            rgba[targetOffset + 1] = pixels[sourceOffset + 1];
            rgba[targetOffset + 2] = pixels[sourceOffset + 2];
            if (maskValue == 255) {
              rgba[targetOffset + 3] = sourceAlpha;
            } else {
              // Soft mask (R26): the stamp carries alpha scaled by
              // coverage, matching the erase's partial removal at the
              // same pixel — Skia's mul-div-255 rounding, like the
              // overlay pipeline.
              final product = sourceAlpha * maskValue + 128;
              rgba[targetOffset + 3] = (product + (product >> 8)) >> 8;
            }
            liftedAnything = true;
          }
        }
      });
    }
  }
  return (rgba: rgba, liftedAnything: liftedAnything);
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
  // Coverage, not the tight fold: the mask box must hold every pixel a
  // step could have added, and `maskFor` zeroes what a 삭제 took back.
  final regionBounds = region.coverageBounds;
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

  // Lift the surface pixels under the mask (straight alpha, byte copies).
  final gathered = gatherMaskedSurfacePixels(
    surface: surface,
    mask: mask,
    left: left,
    top: top,
    width: width,
    height: height,
  );
  final rgba = gathered.rgba;
  final liftedAnything = gathered.liftedAnything;
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
