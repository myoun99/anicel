import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../models/canvas_viewport.dart';

/// 🚨★★★ SAMPLING IS A PROPERTY OF THE DISPLAY, NOT OF THE LAYER.
///
/// 유저 확정 (T21, 2026-08-13): 「**줌이 정한다** — 확대는 `none`, 축소는
/// 필터, **액티브인지는 안 묻는다**」.
///
/// ⛔What this replaces asked the wrong question. The editing stack drew the
/// ACTIVE layer's tiles at [ui.FilterQuality.none] and every other layer at
/// [ui.FilterQuality.low], so *becoming* the active layer changed how a
/// layer was sampled: the artwork visibly changed every time the user
/// switched rows, and at a reduced zoom exactly one layer on screen was
/// aliased. 유저 2026-08-15: 「왜 비액티브레이어는 aa걸려있고 액티브레이어는
/// aa없어서 전환할때마다 그림 바뀌지?」
///
/// The law is one line because the answer never depended on the layer:
///
///  * **Magnified** (scale > 1) — the artist is looking at pixels, so show
///    pixels. Interpolating here invents detail the drawing does not have
///    and makes a hard 2치 edge mushy.
///  * **Reduced** (scale < 1) — more artwork pixels than screen pixels, so
///    point-sampling throws most of them away and the line work crawls and
///    shimmers. Filtering is what makes a reduced view honest.
///  * **1:1** — no resampling happens at all; `none` avoids a pointless
///    filter pass.
///
/// [scale] is the scale of the resample in question: [displayScaleOf] for
/// a canvas-resolution image — every image the display is handed.
/// ↩️Below 100% the display buffer's blit handed the screen a level, read
/// by the residual it was reduced by, until one-picture-per-frame ②-5b.
///
/// ⚠️This only MEANS anything if there is one resample to apply it to.
/// Applied per layer it would still be N resamples that merely agree with
/// each other; the composite buffer is what turns it into the law
/// ([[editing-canvas-composite-cache-program]] stage 2).
///
/// 🔁AT OR UNDER HALF, THE IMAGE'S OWN MIP CHAIN — `medium` (D7-2,
/// one-picture-per-frame; 유저 10-24 「항상 원본 한장으로」): a frame's one
/// picture is at canvas resolution at every zoom, and the engine gives every
/// `toImage` picture a whole chain (`mipLevelCount` 11 at 3840², measured).
/// Measured on the Surface Pro 11 against the display's own levels (each a
/// 2×2 box, then the residual at `low`): 0 bytes apart at 1/2, 1/4 and 1/8,
/// at most 2 between them — the engine's chain IS the halvings — at the
/// cost of any image draw. Over half a bilinear window still holds every
/// texel, and `medium` would only blend in the level under it. An image
/// with no chain samples `medium` as `low` does — 🔬not a `toImageSync`
/// render, which carries one (2026-10-25), but a door's upload: a tile's
/// picture drawn reduced is drawn from one remade with its chain
/// (`chained_picture.dart`).
ui.FilterQuality filterQualityForDisplayScale(double scale) => scale <= 0.5
    ? ui.FilterQuality.medium
    : scale < 1
    ? ui.FilterQuality.low
    : ui.FilterQuality.none;

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
ui.Rect rectOutwardOnGrid(
  ui.Rect bounds,
  double scale, {
  ui.Offset origin = ui.Offset.zero,
}) {
  double down(double value, double start) =>
      start + ((value - start) * scale).floorToDouble() / scale;
  double up(double value, double start) =>
      start + ((value - start) * scale).ceilToDouble() / scale;
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
/// ⚠️Down to one level at any reduction, `low` included: Impeller on
/// Vulkan reads a picture's chain under `low` too (GLES does not —
/// one-picture-per-frame ②-5b-2 착지 줄의 🔬).
int levelsReadAt(double displayScale) => displayScale >= 1
    ? 0
    : (math.log(1 / displayScale) / math.ln2).floor() + 1;

/// The deepest level of a frame's picture's chain a canvas reads: at its
/// least zoom on a screen of one device pixel a canvas pixel
/// ([levelsReadAt]).
final int deepestLevelACanvasReads = levelsReadAt(CanvasViewport.minZoom);

/// [extent] out to whole texels of [deepestLevelACanvasReads] — the grid a
/// frame's picture lies on (`FramePictureStore`), and the display buffer
/// that draws the frame as it stands in its place.
///
/// 🔬Still so with nothing drawn beside the picture (F-465, 2026-10-26):
/// the screen draws a frame as it stands until its picture is there, and
/// wherever no patch can follow a change, and goes back and forth between
/// the two — off this grid they were apart by up to 15/255 at 25%, 20%,
/// 15% and 10% where the view cuts the page or shows its corner, and
/// turned at 33% (Impeller tester).
///
/// 🚨★ONE GRID FOR EVERY IMAGE OF A FRAME THE DISPLAY READS A CHAIN OF
/// (F-465 again, 유저 실기 Windows 2026-10-25: 「10%에서 발생하는거 확인 …
/// 소수점배율에서 발생할거같아서 저번 고칠때랑 데자뷰」): a level is the
/// canvas's grid halved, exactly, only where the image holds whole texels
/// of it — one of fewer texels stretches over the image — and two images
/// of one frame show alike past where their content ends only where they
/// end at one edge: each samples its own edge again past it. ↩️The picture
/// lay on the grid of the levels its patches write, as deep as a 1920 page
/// is read above 12.5% — its 1080 rows were 67.5 texels of the level 10%
/// reads — and the buffer beside it on the grid of the level the display
/// read: 🔬a page of 270 rows apart from its picture down its edge at 6%,
/// and at 10% once the picture alone was widened (Impeller tester).
///
/// 🔬What it costs: a picture is at most 2^[deepestLevelACanvasReads] − 1
/// texels a side larger — a 1920×1080 page's 1920×1152.
ui.Rect frameGridOutward(ui.Rect extent) =>
    wholeLevelPixelsOutward(extent, deepestLevelACanvasReads);

/// [rect] grown by what a display at [displayScale] reads past it — a
/// texel of the deepest level it reads ([levelsReadAt]) — out to whole
/// texels of that level ([wholeLevelPixelsOutward]): a picture of the
/// frame over it holds, at every level the display reads, the texels the
/// frame's one picture holds there, and a device pixel inside [rect] reads
/// nothing past it.
///
/// 🚨What lets a frame drawn as it stands show, at the view's edge, what
/// its one picture shows — the screen goes back and forth between the two
/// ([frameGridOutward]). ↩️It grew a stroke's step drawn as it stood under
/// its patch's clip (F-465, 유저 2026-10-25: 「줌 75%에서는 발생
/// 안하는거같고, 50%에서는 매번」 — a stroke's step at 50% framed in a grey
/// line for a frame), until the step was written into the picture: cut at
/// the clip, the buffer's edge was a texel boundary the picture does not
/// have, its pixel half covered over what lies under the view, and the
/// pixels inside it sampled off a chain laid on another grid.
///
/// ⛔Not grown where the display reads no level (100% and up): nothing
/// past [rect] is read there, and 🔬a canvas pixel more laid a line of
/// what lies under the view along a stroke's patch at 150% on the
/// Impeller tester, where there was none (2026-10-25).
ui.Rect rectTheDisplayReads(ui.Rect rect, double displayScale) {
  final levels = levelsReadAt(displayScale);
  return wholeLevelPixelsOutward(
    levels == 0 ? rect : rect.inflate((1 << levels).toDouble()),
    levels,
  );
}

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
/// follow, and every route that draws the boundary — cached or live,
/// buffer or walk, editing or playback — cuts it on the same pixel, and
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

/// [image]'s [src] laid over [dst] as the display lays an image it is
/// handed: one at canvas resolution of the world [viewport] shows on a
/// screen of [devicePixelRatio], under the canvas's transform. It samples
/// by the scale the draw resamples it by ([filterQualityForDisplayScale])
/// and cuts its edge by the same law ([displayEdgeAntiAliased]).
///
/// 🚨ONE BLIT for every image the display lays over the view — the
/// canvas's display buffer, and a frame's one picture (`FramePictureView`):
/// two spellings of it would be two answers to how a frame is shown.
void drawOnTheDisplay(
  ui.Canvas canvas,
  ui.Image image,
  ui.Rect src,
  ui.Rect dst, {
  required CanvasViewport viewport,
  required double devicePixelRatio,
}) {
  final filterQuality = filterQualityForDisplayScale(
    displayScaleOf(viewport.zoom, devicePixelRatio),
  );
  // The image's edge IS the canvas's edge on screen, cut by the same law
  // as the paper's (F-67-paper-edge): under nearest on an axis-aligned
  // view it is one more texel boundary, decided by pixel centres, not a
  // blended line.
  if (displayEdgeAntiAliased(viewport, devicePixelRatio)) {
    canvas.drawImageRect(
      image,
      src,
      dst,
      ui.Paint()..filterQuality = filterQuality,
    );
  } else {
    drawImageRectOnThePixelGrid(
      canvas,
      image,
      src,
      dst,
      filterQuality: filterQuality,
      pixelRatio: devicePixelRatio,
    );
  }
}

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
