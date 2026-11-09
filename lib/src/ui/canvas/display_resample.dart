import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/display_filter.dart';
import '../../models/canvas_viewport.dart';

/// The scale a canvas-space image is actually resampled by on screen:
/// DEVICE pixels per artwork pixel, `|zoom| × devicePixelRatio`.
///
/// Rotation and flips do not change how many artwork pixels land on a
/// device pixel — only the zoom and the ratio do — so the law reads those
/// two and nothing else. The image is at canvas resolution, so the whole
/// CTM resamples it, and the CTM is the zoom times the ratio.
///
/// 🚨★★★THE ZOOM ALONE WAS THE WRONG QUANTITY (2026-09-16). Until then this
/// returned `|zoom|`, reasoning that "a 2× DPR screen at 100% zoom is still
/// 1:1 artwork-to-canvas". True of the render zoom, and beside the point:
/// what the user calls 100% is the DEVICE zoom — the readout
/// (`CanvasZoomScale.toDevice`: "the device zoom IS the percentage the user
/// reads") — and at device 100% on a ratio-2 tablet the render zoom is
/// 0.5, so the zoom-alone law filtered a 1:1 view and kept filtering up to
/// device 200%: an iPad at 140% on screen got `low`, mush on a magnified
/// view. 유저 09-16: 「표시배율 100%부터는 필터가 걸리면안되」. One quantity,
/// `zoom × ratio`, now decides the filter, the edge, the sampling phase
/// (`samplingPhaseFor`) and the scale a
/// self-rasterising group draws at — a second spelling of the product
/// anywhere is a copy.
double displayScaleOf(double zoom, double devicePixelRatio) =>
    zoom.abs() * devicePixelRatio;

// ↩️🚨★★★BELOW 100% THE DISPLAY WAS FED FROM A LEVEL (render round,
// 2026-09-16 — 유저 결정 통합안 + 안 1 「선명」, 유저 「선명이 좋은데,
// 애초에 메모리 딱히 안커지는데?」): the artwork halved, each halving an exact
// 2×2 box, reduced by a residual in (0.5, 1], so every level pixel lay
// inside one bilinear window of the screen. It went with every picture
// made per zoom (one-picture-per-frame ②-5a · ②-5b, 유저 D7-2-Q2 「배율이
// 어떻든 항상 원본 한장」): a picture's own mip chain IS those halvings —
// 🔬0 bytes apart at 1/2, 1/4 and 1/8 on the Surface Pro 11 — so the
// screen reduces the one picture at canvas resolution
// ([filterQualityForDisplayScale]) and no level is made.

/// [bounds] grown out to whole texels of mip [level] — canvas pixels at
/// level 0, 2^[level] canvas pixels at [level] — the grid a picture's chain
/// is made on: a region on it holds whole texels of every level down to
/// [level], so a patch widened to it halves exactly (`FramePictureStore`).
/// At level 0 it is the canvas's own pixel grid.
///
/// ↩️It was the grid the display buffer was made on below 100%, a level's,
/// until one-picture-per-frame ②-5b.
ui.Rect wholeLevelPixelsOutward(ui.Rect bounds, int level) =>
    rectOutwardOnGrid(bounds, 1.0 / (1 << level));

/// [bounds] grown out to the grid of [scale] cells per canvas unit counted
/// from [origin] — the smallest rect on that grid that holds [bounds].
///
/// 🚨ONE snap for every raster grid: a mip level's
/// ([wholeLevelPixelsOutward]), a sub-tree image's at its device scale, a
/// tile's — copies of it once (↩️a display level's and the pyramid's from a
/// surface's content origin among them, until one-picture-per-frame ②-5b).
/// It multiplies by the scale and divides back, which is exact whenever the
/// scale is a power of two, so every level grid lands to the bit where the
/// copy that divided by the level's step put it.
///
/// [noise] is how far, in cells, a side may lie past a grid line and still
/// be on it: a line reached through other operands — a box's logical
/// pixels, a raster's device ones — lands a few ulps off it. Zero: a side
/// is on a line only to the bit.
ui.Rect rectOutwardOnGrid(
  ui.Rect bounds,
  double scale, {
  ui.Offset origin = ui.Offset.zero,
  double noise = 0,
}) {
  double down(double value, double start) =>
      start + ((value - start) * scale + noise).floorToDouble() / scale;
  double up(double value, double start) =>
      start + ((value - start) * scale - noise).ceilToDouble() / scale;
  return ui.Rect.fromLTRB(
    down(bounds.left, origin.dx),
    down(bounds.top, origin.dy),
    up(bounds.right, origin.dx),
    up(bounds.bottom, origin.dy),
  );
}

/// How many levels of a picture's mip chain a draw at [displayScale] —
/// device pixels per canvas pixel ([displayScaleOf]) — reads: none where it
/// is not reduced, and otherwise down to the one past the level its
/// reduction lands at, the two a sampler blends between.
///
/// ⚠️Down to one level at any reduction, `low` included, though `low`
/// reads none (`FramePicture.readAt`): what is laid by this comes out wider
/// than `low` needs, and a bilinear read does reach past a rect. ↩️It said
/// Impeller on Vulkan reads a picture's chain under `low` too
/// (one-picture-per-frame ②-5b-2 착지 줄의 🔬): the engine does not, nor did
/// the tester's Vulkan measured 2026-10-31.
int levelsReadAt(double displayScale) => displayScale >= 1
    ? 0
    : (math.log(1 / displayScale) / math.ln2).floor() + 1;

/// Whether the OUTER EDGE of what lands on the display — the display
/// buffer's blit, the paper rect under it, the playback composite that
/// stands in for both during a scrub — is anti-aliased.
///
/// 🚨★★★THE EDGE IS ONE MORE TEXEL BOUNDARY (F-67-paper-edge, 2026-09-11).
/// Under nearest sampling every boundary INSIDE the image is decided per
/// device pixel by where its centre falls: a pixel shows one texel or the
/// next, never a blend. The image's outer edge — and the paper rect that
/// shares it — was the one boundary the engine cut differently: with
/// anti-aliasing a fractional edge covers its pixel partly, which is a
/// blended line one pixel wide along the canvas that nothing inside the
/// canvas has. The render snap's phase (F-67) put that edge a quarter
/// pixel in at 110%, and the line showed: 75% paper over the backdrop.
/// 유저 09-11: 「고칠 수 있다면 고치자」.
///
/// So on an axis-aligned view under `none` the edge is NOT anti-aliased:
/// it lands where the pixel centres say, the same rule the texels inside
/// follow, and every route that draws the boundary cuts it on the same
/// pixel, and
/// the leftmost texel keeps its column (an edge ROUNDED inward would have
/// dropped it). Bilinear (reduced) blends the boundaries inside too, and a
/// rotated view's edges are diagonals, so anti-aliasing stays there. A
/// flip is axis-aligned and changes nothing.
///
/// The image being cut is at canvas resolution — every one the display is
/// handed — so the scale it is reduced by is the device scale itself.
/// ↩️An image composed at a level was reduced by the residual instead, and
/// at exactly 50% that residual was 1 — nearest, the edge cut on the grid
/// like any 1:1 view's — until one-picture-per-frame ②-5b.
///
/// An edge this answers false for is cut by moving it ONTO the grid
/// ([cutOnThePixelGrid]), not by asking the engine not to blend it.
bool displayEdgeAntiAliased(
  CanvasViewport viewport,
  double devicePixelRatio,
) =>
    viewport.rotationDegrees != 0 ||
    filterQualityForDisplayScale(
          displayScaleOf(viewport.zoom, devicePixelRatio),
        ) !=
        ui.FilterQuality.none;

/// [rect] — in the space [canvas] draws in now — with each edge moved onto
/// the pixel boundary the pixel centres decide: a pixel is inside exactly
/// when its centre is, `ceil(e − ½)` on every edge, as a nearest sample
/// decides every boundary inside the image ([displayEdgeAntiAliased]).
/// [pixelRatio] carries the canvas's space to its pixels past the canvas's
/// own transform: the screen's device pixel ratio on screen, 1 in a raster
/// whose transform lands on its pixels already.
///
/// 🚨WHAT CUTS THE EDGE ON THE GRID, ON EVERY ENGINE. Impeller does not
/// honour `isAntiAlias = false`: its MSAA covers a pixel by the samples
/// that fall inside, so an edge at 9.45 lit two of pixel 9's four —
/// measured under `--enable-impeller`, 2026-10-24: paper at 50% one pixel
/// past the canvas, the line F-67-paper-edge took away, back on every
/// device since the move to Impeller (09-16). An edge ON a pixel boundary
/// is covered wholly or not at all, whatever the engine.
///
/// A turned or projected space has no edge on the grid: [rect] comes back
/// as it is.
ui.Rect cutOnThePixelGrid(ui.Canvas canvas, ui.Rect rect, double pixelRatio) {
  final grid = _pixelGridOf(canvas, pixelRatio);
  if (grid == null) {
    return rect;
  }
  final (:sx, :sy, :tx, :ty) = grid;
  double cut(double value, double scale, double origin) =>
      (((value * scale + origin) - 0.5).ceilToDouble() - origin) / scale;
  return ui.Rect.fromPoints(
    ui.Offset(cut(rect.left, sx, tx), cut(rect.top, sy, ty)),
    ui.Offset(cut(rect.right, sx, tx), cut(rect.bottom, sy, ty)),
  );
}

/// Whether an edge of a grid of [cell]-wide squares from the origin of
/// [canvas]'s space falls inside a pixel — where an engine that blends every
/// edge it is handed blends it, and [cutOnThePixelGrid] would move it — with
/// [pixelRatio] as there. A turned or projected space has no edge on the
/// grid to fall off: false.
bool cellsFallOffThePixelGrid(
  ui.Canvas canvas,
  double cell,
  double pixelRatio,
) {
  final grid = _pixelGridOf(canvas, pixelRatio);
  if (grid == null) {
    return false;
  }
  final (:sx, :sy, :tx, :ty) = grid;
  bool off(double pixels) => pixels != pixels.roundToDouble();
  return off(tx) || off(ty) || off(sx * cell) || off(sy * cell);
}

/// The point of [canvas]'s space nearest its origin where the edges of its
/// pixels cross, for a raster of [scale] pixels to a unit of the space laid
/// on it 1:1 — the scale that says how many of the canvas's pixels a unit
/// covers past its transform, the screen's ratio on the screen and 1 in a
/// raster. A grid counted from here ([rectOutwardOnGrid]'s `origin`) is the
/// canvas's pixels; a turned or projected space has no edge on the grid,
/// and its grid is counted from the origin.
ui.Offset pixelGridOriginAt(ui.Canvas canvas, double scale) {
  final space = _pixelGridOf(canvas, 1);
  if (space == null) {
    return ui.Offset.zero;
  }
  final (:sx, :sy, :tx, :ty) = space;
  double from(double translation, double unit) {
    final pixels = translation * scale / unit.abs();
    return (pixels.roundToDouble() - pixels) / (unit.sign * scale);
  }

  return ui.Offset(from(tx, sx), from(ty, sy));
}

/// [canvas]'s space on its pixels — each axis's scale and origin, carried
/// past the canvas's own transform by [pixelRatio] — or null where the space
/// is turned, projected or flat and has no edge on the grid.
({double sx, double sy, double tx, double ty})? _pixelGridOf(
  ui.Canvas canvas,
  double pixelRatio,
) {
  final m = canvas.getTransform();
  if (m[1] != 0 || m[4] != 0 || m[3] != 0 || m[7] != 0 || m[15] != 1) {
    return null;
  }
  final (sx, sy) = (m[0] * pixelRatio, m[5] * pixelRatio);
  if (sx == 0 || sy == 0) {
    return null;
  }
  return (sx: sx, sy: sy, tx: m[12] * pixelRatio, ty: m[13] * pixelRatio);
}

/// [rect] with its edge cut as the display law says: as it is where the
/// edge is [antiAlias]ed — the engine blends it — and on the grid of
/// [pixelRatio] everywhere else ([cutOnThePixelGrid]).
ui.Rect displayEdgeRect(
  ui.Canvas canvas,
  ui.Rect rect, {
  required bool antiAlias,
  required double pixelRatio,
}) => antiAlias ? rect : cutOnThePixelGrid(canvas, rect, pixelRatio);

/// [canvas] clipped to [rect], its edge cut as the display law says
/// ([displayEdgeRect]) — a wall, or where a frame ends, cuts what lies on
/// both sides of it where the display cuts the canvas's own edge
/// (the-walk-family-cuts-the-rest-on-the-grid).
void clipToTheDisplayEdge(
  ui.Canvas canvas,
  ui.Rect rect, {
  required bool antiAlias,
  required double pixelRatio,
}) => canvas.clipRect(
  displayEdgeRect(canvas, rect, antiAlias: antiAlias, pixelRatio: pixelRatio),
  doAntiAlias: antiAlias,
);

/// [image]'s [src] laid over [dst] as `drawImageRect` lays it — each pixel
/// shows what its centre falls on — with the edge cut on the grid
/// ([cutOnThePixelGrid]): the texels ride a shader mapped [src] → [dst],
/// and only what it fills is cut ([drawShadedRect]), so moving the edge
/// moves no texel. Every pixel inside the cut rect has its centre inside
/// [dst], so nothing past the image is ever shown.
///
/// [paint] is what else the image is laid with — a layer's opacity, blend
/// and colour riding the draw — as `drawImageRect` would take it; the image
/// is its shader for the draw, and no edge of it is anti-aliased.
void drawImageRectOnThePixelGrid(
  ui.Canvas canvas,
  ui.Image image,
  ui.Rect src,
  ui.Rect dst, {
  required ui.FilterQuality filterQuality,
  required double pixelRatio,
  ui.Paint? paint,
}) {
  final sx = dst.width / src.width;
  final sy = dst.height / src.height;
  final shader = ui.ImageShader(
    image,
    ui.TileMode.clamp,
    ui.TileMode.clamp,
    Float64List(16)
      ..[0] = sx
      ..[5] = sy
      ..[10] = 1
      ..[12] = dst.left - src.left * sx
      ..[13] = dst.top - src.top * sy
      ..[15] = 1,
    filterQuality: filterQuality,
  );
  try {
    drawShadedRect(
      canvas,
      cutOnThePixelGrid(canvas, dst, pixelRatio),
      (paint == null ? ui.Paint() : ui.Paint.from(paint))
        ..shader = shader
        ..isAntiAlias = false,
    );
  } finally {
    // The drawing holds the shader from the draw on, as it holds an image.
    shader.dispose();
  }
}

/// [paint] — an image's shader — over [rect], where [canvas] can show it:
/// [rect] is the clip, and the paint fills the clip. Its edge is [paint]'s
/// anti-aliasing, as a rect's would be.
///
/// 🚨A SHADED RECT IS DRAWN NO LARGER THAN WHAT SHOWS
/// (deep-zoom-blanks-the-canvas). 🔬On the Windows app (Impeller, profile,
/// 10-27) a rect an image's shader fills cost the GPU by its whole extent
/// on the device, not by what of it shows — a 2432×1654 picture on a
/// 1600×1000 view took 9 · 16 · 34 ms at 1 · 3 · 6× — and past 16384 device
/// pixels a side it filled WHITE: the canvas showed its picture at 670% on
/// a 2340 page and went white at 675% (2432 × 6.75, the Surface's verify).
///
/// ⛔NOT THE RECT CUT TO THE VIEW. There (`6d3aa1172`) the Windows app laid
/// no texel where its shader maps it: a patterned 2432×1654 picture on a
/// 400×300 view showed the same texel at the same pixel at every scale and
/// pan, all 120,000 pixels apart from `drawImageRect` at 1 · 1.54 · 3 · 7×
/// (a rect at the shader's origin was right, so a whole image's rect was) —
/// and the Surface's canvas stopped following the zoom past 154% (10-27,
/// verify). The test runner's Vulkan maps it right, so no pixel test there
/// sees it. Clipped and painted, the same picture was 0 pixels apart at
/// each scale with the pan on whole pixels, in 7–12 ms; with it a fraction
/// off, laid through [drawImageRectOnThePixelGrid], 0 apart from that rect
/// uncut — the canvas before `6d3aa1172` — where the page's middle showed
/// at 1 · 1.52 · 1.54 · 3×, and where its corner showed 0 · 322 · 324 · 0
/// of the 120,000.
void drawShadedRect(ui.Canvas canvas, ui.Rect rect, ui.Paint paint) {
  canvas
    ..save()
    ..clipRect(rect, doAntiAlias: paint.isAntiAlias)
    ..drawPaint(paint)
    ..restore();
}
