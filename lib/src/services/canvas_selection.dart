import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import '../core/point_bounds.dart';
import '../models/pasteboard_bounds.dart';
import '../models/brush_dab.dart';
import '../models/brush_stamp_image.dart';
import '../models/canvas_point.dart';
import '../native/engine_stamp_pictures.dart';
import 'canvas_selection_region.dart';
import 'canvas_selection_shape.dart';
import 'guide_geometry.dart' show GuideTransform;
import 'mask_morphology.dart';
import 'mask_soft_edge.dart';
import 'resample/resample_kernel.dart';
import 'resample/selection_resample.dart';
import 'selection_affine.dart';

export 'canvas_selection_shape.dart';
export 'selection_affine.dart';

/// The integer canvas rect a warp lands in: the bounding box of [points]
/// ([pointsBounds]), snapped outward.
///
/// Shared by all three warps so their geometry cannot drift apart — they
/// each had their own copy of this loop, and three copies of a bounding
/// box is three chances for one of them to snap the wrong way.
({int left, int top, int width, int height}) selectionWarpOutputRect(
  List<CanvasPoint> points,
) {
  final bounds = pointsBounds([
    for (final point in points) Offset(point.x, point.y),
  ]);
  final left = bounds.left.floor();
  final top = bounds.top.floor();
  return (
    left: left,
    top: top,
    width: math.max(1, bounds.right.ceil() - left),
    height: math.max(1, bounds.bottom.ceil() - top),
  );
}

/// A canvas-space rectangle a PREVIEW only has to cover.
typedef SelectionVisibleRect = ({
  double left,
  double top,
  double right,
  double bottom,
});

/// Where a stamp's picture stands on the canvas.
typedef StampRect = ({double left, double top, double width, double height});

/// [stampDab]'s picture's rect — null when it carries none.
StampRect? stampRectOf(BrushDab stampDab) {
  final stamp = stampDab.stamp;
  if (stamp == null) {
    return null;
  }
  return (
    left: stampDab.center.x - stamp.width / 2,
    top: stampDab.center.y - stamp.height / 2,
    width: stamp.width.toDouble(),
    height: stamp.height.toDouble(),
  );
}

/// A MESH AT REST: the nodes of a `columns × rows` grid laid evenly over
/// [base], row-major — a mesh's BASE, as [stampCornersOf] is a quad's.
/// Points left where these are make the mesh transform exactly the
/// identity, and points all moved from them by one delta are a whole drag.
///
/// ⛔ONE SPELLING. The layer's handles, the transform's source triangles
/// and the carry's whole-drag check each laid this grid out, and two of the
/// three multiplied before dividing where the third divided first — a last
/// bit apart on the default 3×3, which is all it takes for 「moved by one
/// delta」 to read false (2026-10-06).
List<CanvasPoint> meshRestGrid(
  StampRect base, {
  required int columns,
  required int rows,
}) {
  final cellWidth = base.width / columns;
  final cellHeight = base.height / rows;
  return [
    for (var row = 0; row <= rows; row += 1)
      for (var column = 0; column <= columns; column += 1)
        CanvasPoint(
          x: base.left + column * cellWidth,
          y: base.top + row * cellHeight,
        ),
  ];
}

/// That rect's corners, TL · TR · BR · BL — a quad's BASE: corners left
/// where these are make the quad transform exactly the identity.
List<CanvasPoint>? stampCornersOf(BrushDab stampDab) {
  final rect = stampRectOf(stampDab);
  return rect == null ? null : cornersOfStampRect(rect);
}

/// [rect]'s corners, TL · TR · BR · BL.
List<CanvasPoint> cornersOfStampRect(StampRect rect) {
  final right = rect.left + rect.width;
  final bottom = rect.top + rect.height;
  return [
    CanvasPoint(x: rect.left, y: rect.top),
    CanvasPoint(x: right, y: rect.top),
    CanvasPoint(x: right, y: bottom),
    CanvasPoint(x: rect.left, y: bottom),
  ];
}

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
}) => _stampThrough(
  stampDab,
  identity: affine.isIdentity,
  move: affine.isPureTranslation
      ? (dx: affine.appliedTx, dy: affine.appliedTy)
      : null,
  apply: affine.apply,
  fold: (srcLeft, srcTop, out) => selectionAffineResampleTransform(
    affine: affine,
    srcLeft: srcLeft,
    srcTop: srcTop,
    outLeft: out.left,
    outTop: out.top,
  ),
  resampled: (stamp, out, transform) => _carriedOnEngine(
    stampDab: stampDab,
    stamp: stamp,
    out: out,
    window: selectionPreviewWindow(out: out, visible: visible),
    transform: transform,
    mode: mode,
  ),
);

/// The lifted stamp through the plane affine [to] — a row's PLACEMENT, or
/// the way back through one, [from] being the other direction — carried
/// exactly as [transformStampDab] carries one through the box's affine:
/// the same three answers, out of the same body.
///
/// 🗣️F-256-Q1 (유저 2026-10-06): 「가른다 — AE 처럼 Scale X · Y」. A placement
/// is any affine — a folder stretched along one axis over a turned row
/// SHEARS it — and the box's affine is a scale about a pivot and then a
/// turn, which can say neither a shear nor the way BACK through a row
/// scaled an axis apiece (S⁻¹·R⁻¹ is not an R·S).
///
/// 🚨ITS RESAMPLE IS THE ENGINE'S ([_carriedOnEngine], gpu-canonical-store
/// ⑪, 2026-11-11). A float carried over a posed row shows as its landing at
/// every step of the hand (🗣️유저 2026-09-17: 「보이는 중이랑 결과랑 절대로
/// 다르면 안 되」, `SelectionFloatPaint.shownOn`), so the crossing back into
/// the row runs at every step: 🔬on the CPU, a 26.7 MB stamp was 55–68 ms
/// of resample and 32–44 ms of handing the bytes up again, a step (main
/// PC), and the Surface Pro 11 dragged it at 220–250 ms a frame where
/// master — which showed the float itself there, sharper than it landed —
/// took 142–146. The box's own warps (the affine above, the quad, the
/// mesh) are the engine's as well (float-warp-resamples-in-the-c-engine,
/// 2026-11-11): one R1 for every warp a float takes, its window or whole.
BrushDab carryStampDab(
  BrushDab stampDab, {
  required GuideTransform to,
  required GuideTransform from,
  ResampleMode mode = ResampleMode.blend,
}) => _stampThrough(
  stampDab,
  identity: to.isIdentity,
  move: to.isPureTranslation ? (dx: to.tx, dy: to.ty) : null,
  apply: to.apply,
  fold: (srcLeft, srcTop, out) => planeResampleTransform(
    toSource: from,
    srcLeft: srcLeft,
    srcTop: srcTop,
    outLeft: out.left,
    outTop: out.top,
  ),
  resampled: (stamp, out, transform) => _carriedOnEngine(
    stampDab: stampDab,
    stamp: stamp,
    out: out,
    transform: transform,
    mode: mode,
  ),
);

/// One stamp through one map of the plane ([apply]): [identity] hands the
/// dab back, a pure [move] only moves its centre, and anything else is ONE
/// resample into the bounding box of the stamp's mapped corners, through
/// the destination-to-source [fold] of that same map — made as [resampled]
/// makes it.
BrushDab _stampThrough(
  BrushDab stampDab, {
  required bool identity,
  required ({double dx, double dy})? move,
  required CanvasPoint Function(CanvasPoint point) apply,
  required ResampleTransform Function(
    double srcLeft,
    double srcTop,
    ({int left, int top, int width, int height}) out,
  )
  fold,
  required BrushDab Function(
    BrushStampImage stamp,
    ({int left, int top, int width, int height}) out,
    ResampleTransform transform,
  )
  resampled,
}) {
  final stamp = stampDab.stamp;
  if (stamp == null || identity) {
    return stampDab;
  }
  if (move != null) {
    return stampDab.copyWith(
      center: CanvasPoint(
        x: stampDab.center.x + move.dx,
        y: stampDab.center.y + move.dy,
      ),
    );
  }

  // The stamp draws 1:1 about its center: its canvas-space source rect.
  final srcLeft = stampDab.center.x - stamp.width / 2;
  final srcTop = stampDab.center.y - stamp.height / 2;

  // Output AABB = the transformed source corners.
  final corners = [
    apply(CanvasPoint(x: srcLeft, y: srcTop)),
    apply(CanvasPoint(x: srcLeft + stamp.width, y: srcTop)),
    apply(CanvasPoint(x: srcLeft + stamp.width, y: srcTop + stamp.height)),
    apply(CanvasPoint(x: srcLeft, y: srcTop + stamp.height)),
  ];
  final out = selectionWarpOutputRect(corners);

  // The FULL rect's matrix, always. A window keeps the whole rect's pixel
  // grid and says where it sits; folding the offset into the origin instead
  // is the version that is equal in arithmetic and not in doubles — see
  // ABI 26.
  return resampled(stamp, out, fold(srcLeft, srcTop, out));
}

/// One resample of [stamp] into [window] of [out] (or all of [out] when
/// window is null), made on the engine, wrapped as a dab positioned at what
/// it covers: the stamp it wraps is the engine's picture
/// (`EngineStampPictures.carried`, R1 in [mode] with the same radius
/// floor), so it lands without a byte of it coming here, and what does ask
/// for its bytes reads them from there.
///
/// ⚠️ A WINDOWED result is a PREVIEW. It holds only the pixels asked for,
/// so committing it would land a rectangle of the picture and drop the
/// rest. The one caller that clips keys its cache on the window, so the
/// commit — which asks for no window — cannot be handed one by mistake.
BrushDab _carriedOnEngine({
  required BrushDab stampDab,
  required BrushStampImage stamp,
  required ({int left, int top, int width, int height}) out,
  ({int x, int y, int width, int height})? window,
  required ResampleTransform transform,
  required ResampleMode mode,
  String idPrefix = 't',
}) => _resampledDab(
  stampDab,
  at: (left: out.left + (window?.x ?? 0), top: out.top + (window?.y ?? 0)),
  made: EngineStampPictures.carried(
    stamp,
    id: _resampledId(stamp, idPrefix),
    inverse: resampleTransformElements(transform),
    radiusFloor: kSelectionResampleRadiusFloor,
    sampling: resampleSampling(mode),
    width: out.width,
    height: out.height,
    window: window == null
        ? null
        : (window.x, window.y, window.width, window.height),
  ),
);

/// [stampDab] as the dab of [made], a resample of its stamp whose first
/// pixel lies [at] on the canvas: centred on what it covers.
BrushDab _resampledDab(
  BrushDab stampDab, {
  required ({int left, int top}) at,
  required BrushStampImage made,
}) => stampDab.copyWith(
  center: CanvasPoint(
    x: at.left + made.width / 2,
    y: at.top + made.height / 2,
  ),
  size: math.max(made.width, made.height).toDouble(),
  stamp: made,
);

/// A name for a resample of [stamp], no two alike.
String _resampledId(BrushStampImage stamp, String prefix) =>
    '${stamp.id}-$prefix${DateTime.now().microsecondsSinceEpoch}';

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
    final x = from[i].x;
    final y = from[i].y;
    final u = to[i].x;
    final v = to[i].y;
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

/// The dab a warp answers with when every control point moved by the SAME
/// delta — or null when the warp is a real one.
///
/// ⛔BOTH WARP PATHS SHORT-CIRCUIT HERE, AND NOT FOR SPEED. Dragging the
/// whole quad, or the whole grid, is reachable — and without this it would
/// run the per-pixel vote: solveHomography's elimination leaves a ~1e-15
/// residue, so the kernel's own whole-pixel-translation circuit never
/// fires here no matter how exactly the user dragged.
BrushDab? stampDabMovedWholesale(
  BrushDab stampDab,
  List<CanvasPoint> base,
  List<CanvasPoint> moved,
) {
  final deltaX = moved[0].x - base[0].x;
  final deltaY = moved[0].y - base[0].y;
  for (var i = 1; i < base.length; i += 1) {
    if (moved[i].x - base[i].x != deltaX || moved[i].y - base[i].y != deltaY) {
      return null;
    }
  }
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
  final moved = stampDabMovedWholesale(stampDab, base, corners);
  if (moved != null) {
    return moved;
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
  return _carriedOnEngine(
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
/// function of the destination point, so each triangle is one map of R1,
/// in [mode]; which triangle paints a pixel is the engine's too (R3,
/// `EngineStampPictures.meshed`), so the mesh is one picture made there.
///
/// [base] is the rect the grid stands on — the stamp's own unless another
/// is given: a stamp carried through a box that stands on a different one
/// (`MeshCarry`, the other cels of a range). The picture is read where it
/// is either way; a node whose source lies off the stamp reads nothing.
BrushDab transformStampDabMesh(
  BrushDab stampDab, {
  required int columns,
  required int rows,
  required List<CanvasPoint> points,
  StampRect? base,
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
  final baseGrid = meshRestGrid(
    base ?? stampRectOf(stampDab)!,
    columns: columns,
    rows: rows,
  );
  final moved = stampDabMovedWholesale(stampDab, baseGrid, points);
  if (moved != null) {
    return moved;
  }

  // 🚨THE PICTURE IS THE WINDOW'S, not the whole output rect's — the law
  // the affine and the quad keep too ([_carriedOnEngine]): nothing is made
  // past what was asked for (C-ipad-crash, 2026-09-11). A grid carried on
  // past its box (`MeshCarry`, a range's other cels) can reach a long way
  // past the wall.
  final out = selectionWarpOutputRect(points);
  final window = selectionPreviewWindow(out: out, visible: visible);
  final left = out.left + (window?.x ?? 0);
  final top = out.top + (window?.y ?? 0);
  // Each pixel by the map of the triangle that paints it, the first in the
  // grid's order where they fold over — row, column, then (TL, TR, BL)
  // before (TR, BR, BL) — and nothing where none does: R3 on the engine.
  return _resampledDab(
    stampDab,
    at: (left: left, top: top),
    made: EngineStampPictures.meshed(
      stamp,
      id: _resampledId(stamp, 'm'),
      at: (srcLeft, srcTop),
      columns: columns,
      rows: rows,
      source: _coordinatesOf(baseGrid),
      destination: _coordinatesOf(points),
      radiusFloor: kSelectionResampleRadiusFloor,
      sampling: resampleSampling(mode),
      window: (
        left,
        top,
        window?.width ?? out.width,
        window?.height ?? out.height,
      ),
    ),
  );
}

/// [points]' x and y, one after the other.
List<double> _coordinatesOf(List<CanvasPoint> points) => [
  for (final point in points) ...[point.x, point.y],
];

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

  /// How far from a pixel the post-passes read to decide it. ⚠️Not
  /// [bboxPad]: a shrink writes nothing past the outline, and it reads as
  /// far as a grow does.
  int get neighbourReach =>
      growPx.abs() + featherPx.ceil() + (antiAlias ? 1 : 0);
}

/// Inward feather: 3-4 chamfer distance from the OUTSIDE, alpha ramps
/// over [featherPx] (chamfer units: 3 per orthogonal pixel).
void _featherMask(Uint8List mask, int width, int height, double featherPx) {
  const infinity = 60000;
  final dist = Uint16List(width * height);
  chamferDistance34(
    dist,
    from: mask,
    zeroWhen: 0,
    width: width,
    height: height,
    infinity: infinity,
    // Canvas-edge pixels ramp too (border counts as outside).
    borderDistance: 3,
  );
  final ramp = featherPx * 3.0;
  for (var i = 0; i < mask.length; i += 1) {
    if (mask[i] == 0) continue;
    final alpha = (dist[i] / ramp * 255).round();
    mask[i] = alpha >= 255 ? 255 : alpha;
  }
}

/// One boundary soft pass, CLAMPED INSIDE THE OUTLINE.
///
/// 🚨★★★THE RAMP LIVES INSIDE THE OUTLINE. 유저 2026-08-27, after looking at
/// TVPaint: 「애초 tvp 보니까 **선택의 aa가 선택 바깥에 걸리는게 아니라 선택
/// 안쪽에 걸고있는거같거든**? 그렇게 하면 해결인가?」.
///
/// It is, and the clamp is the whole of it. A plain blur spreads both ways,
/// so every anti-aliased selection used to carry a one-pixel skirt of mask
/// OUTSIDE its own outline — and since #1288 a pixel the mask touches at all
/// travels whole, that skirt is a ring of the neighbour's artwork lifted
/// along with the selection and erased from where it was. That is the 「선택
/// 바깥에 픽셀이 남는다」 report, arriving from the opposite direction to the
/// one it looked like.
///
/// ⛔Not a wider `bboxPad`, and not a special case at the lift: the mask is
/// what every verb reads (the pixel verbs share it), so a selection that
/// means "these pixels" has to say so here or the meanings drift apart.
///
/// ⛔THE ARITHMETIC IS NOT OURS TO KEEP A COPY OF. It is the fill finish's,
/// and it used to be written out here — where it
/// promptly diverged, because the clamp above was added to this copy alone.
/// [softenMaskBoundary] holds the formula; this line holds the meaning.
void _antiAliasMask(Uint8List mask, int width, int height) {
  softenMaskBoundary(
    mask,
    width: width,
    height: height,
    insideOutlineOnly: true,
  );
}

/// The coverage [region] has over `[left, left+width) x [top, top+height)`,
/// with the selection tool's mask knobs applied.
///
/// Even-odd scanline rasterization folded step by step (R26 #16 — the
/// composite region's own rasterizer): O(edges × rows + pixels), where the
/// naive per-pixel ray cast made lasso lifts quadratic. The R26 post-passes
/// are opt-in and leave the classic hard mask byte-identical; their order
/// is resize the region first, then soften.
///
/// Shared with the PIXEL verbs (색 변환 / 픽셀 비우기) so a selection means
/// the same pixels whichever verb reads it. ⚠️Callers that rasterize the
/// mask in pieces must pad each piece by
/// [SelectionMaskOptions.neighbourReach] and keep only the middle, as
/// `SelectionClip` does: the post-passes read neighbours, so a piece
/// rasterized without padding softens against its own edge and leaves a
/// seam where the pieces meet.
Uint8List buildSelectionMask({
  required CanvasSelectionRegion region,
  required SelectionMaskOptions options,
  required int left,
  required int top,
  required int width,
  required int height,
}) {
  final mask = region.maskFor(
    left: left,
    top: top,
    width: width,
    height: height,
  );
  if (!options.isHard) {
    // The sign of growPx picks the operator; the kernels carry no mode.
    if (options.growPx > 0) {
      dilateMask4(mask, width: width, height: height, passes: options.growPx);
    } else if (options.growPx < 0) {
      erodeMask4(mask, width: width, height: height, passes: -options.growPx);
    }
    if (options.featherPx > 0) {
      _featherMask(mask, width, height, options.featherPx);
    }
    if (options.antiAlias) {
      _antiAliasMask(mask, width, height);
    }
  }
  return mask;
}

/// A selection's mask over the box it covers — nothing is selected outside
/// [box].
typedef SelectionMaskReading = ({
  Uint8List mask,
  ({int left, int top, int width, int height}) box,
});

/// A selection READ the way every pixel reader reads one: [region]
/// rasterized at [options] ([buildSelectionMask]) over its own box —
/// coverage, padded for the post-passes, inside the pasteboard [wall]
/// ([CanvasSelectionRegion.pixelBoxWithin]). Null when that
/// box is empty.
///
/// ⛔ONE READING. The move's lift, the pixel verbs' walk, the copy and the
/// paste (I-55) each computed this box and then this mask; four copies of
/// two steps is how a selection comes to mean two things.
///
/// ⚠️The lift — the move's, the cut's, the copy's — and the pixel verbs'
/// walk read through their `SelectionClip` since 2026-11-14 (L1b-2 · 3):
/// the same box and the same bytes, made on the engine. Only tests read
/// this now, the reference a clip's windows are held to; it goes with the
/// CPU's mask (L2, board
/// `a-selection-mask-is-built-on-the-cpu-at-every-move`).
SelectionMaskReading? selectionMaskOnPasteboard(
  CanvasSelectionRegion region, {
  required PasteboardWall wall,
  SelectionMaskOptions options = SelectionMaskOptions.none,
}) {
  final box = region.pixelBoxWithin(
    wall.region,
    pad: options.bboxPad,
  );
  if (box == null) {
    return null;
  }
  return (
    mask: buildSelectionMask(
      region: region,
      options: options,
      left: box.left,
      top: box.top,
      width: box.width,
      height: box.height,
    ),
    box: box,
  );
}
