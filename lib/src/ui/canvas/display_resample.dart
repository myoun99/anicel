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
/// a canvas-resolution image, [displayResidualOf] for the display buffer's
/// blit below 100%, which hands the screen a level, not the artwork.
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
/// with no chain (a `toImageSync` tile's) samples `medium` as `low` does.
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
/// (`samplingPhaseFor`), the level ([displayLevelOf]) and the scale a
/// self-rasterising group draws at — a second spelling of the product
/// anywhere is a copy.
double displayScaleOf(double zoom, double devicePixelRatio) =>
    zoom.abs() * devicePixelRatio;

/// 🚨★★★BELOW 100% THE DISPLAY IS FED FROM A LEVEL (render round,
/// 2026-09-16 — 유저 결정 통합안 + 안 1 「선명」).
///
/// One composite image, one blit, stays the law at every zoom. What
/// changes below 100% is what that image IS: not the artwork at canvas
/// resolution reduced by the whole device scale in one bilinear pass —
/// which undersamples past 2× and shimmers — but the artwork HALVED this
/// many times (each halving an exact 2×2 box), reduced by the residual
/// [displayResidualOf] in (0.5, 1]. Every level pixel then lies inside one
/// bilinear window of the screen, and the buffer is at most 4× the
/// screen's pixels (2× on average) instead of the visible canvas's.
///
/// 안 1 over 속도 우선 (a residual in (0.5, 1] over [0.5, 1)·2): the same
/// images, a third fewer buffer pixels on the other side, a few
/// milliseconds apart — 유저: 「선명이 좋은데, 애초에 메모리 딱히
/// 안커지는데?」. Levels are IMAGES only — no reduced pixel store beside
/// the tiles — so a level costs its picture and nothing else.
///
/// At or above 100% the level is 0 and the buffer's bytes are what they
/// always were (유저: 「표시배율 100%부터는 필터가 걸리면안되」).
///
/// Capped at [maxDisplayLevel]: past it the residual falls under 0.5 and
/// the blit undersamples, which is the reduction the display had
/// everywhere before levels existed — an extreme zoom-out over a giant
/// pasteboard, and no worse than the day before.
int displayLevelOf(double scale) {
  var level = 0;
  var residual = scale.abs();
  while (residual <= 0.5 && level < maxDisplayLevel) {
    residual *= 2;
    level += 1;
  }
  return level;
}

/// The deepest level the display composes at: 1/16 of the artwork.
const int maxDisplayLevel = 4;

/// The scale the display's ONE resample actually applies to what it is
/// handed: the level image ([displayLevelOf]) reduced by this residual —
/// in (0.5, 1] under [maxDisplayLevel] — or, at level 0, the
/// canvas-resolution image by the device scale itself.
///
/// This, not the device scale, is what the blit's
/// [filterQualityForDisplayScale] and [displayEdgeAntiAliased] read: at
/// exactly 50% the level-1 image lands 1:1 on device pixels and samples
/// `none`, sharp; at 45% it is reduced by 0.9 and samples `low`.
double displayResidualOf(double scale) =>
    scale.abs() * (1 << displayLevelOf(scale));

/// [bounds] grown out to whole pixels of [level] — canvas pixels at level 0,
/// 2^[level] canvas pixels below 100% — the grid the display buffer is made
/// on. A raster on this grid lands 1:1 on a level buffer's pixels whichever
/// of the two rects is larger, and a region on it halves [level] times into
/// whole level pixels. It is also what makes a carry exact: two buffers of
/// one level are offset by whole buffer pixels.
ui.Rect wholeLevelPixelsOutward(ui.Rect bounds, int level) =>
    rectOutwardOnGrid(bounds, 1.0 / (1 << level));

/// The paper under rows reduced to [level] ([displayLevelOf]) on the canvas
/// [canvasRect]: the canvas's own rect at level 0, one level pixel in below.
///
/// #15 — inside a LEVEL buffer the paper yields one buffer pixel to the
/// reduced resample: paper and ink are rasterised at level resolution
/// where the canvas's edge can fall inside a level pixel, and a paper
/// that ended on that pixel's far side would show past ink that is a
/// box-filtered half there — the 1px bright ring the device saw below
/// ~30% under the knee's scaled recording (the same mechanism, the same
/// one-buffer-pixel answer). At level 0 the canvas edge is whole and the
/// paper is the exact canvas rect.
///
/// A canvas under two level pixels a side has nothing left to yield: the
/// paper stays whole rather than vanishing.
ui.Rect paperRectAtLevel(ui.Rect canvasRect, int level) {
  if (level == 0) {
    return canvasRect;
  }
  final yielded = canvasRect.deflate((1 << level).toDouble());
  return yielded.isEmpty ? canvasRect : yielded;
}

/// [bounds] grown out to the grid of [scale] cells per canvas unit counted
/// from [origin] — the smallest rect on that grid that holds [bounds].
///
/// 🚨ONE snap for every raster grid: a display level's, the pyramid's from a
/// surface's content origin, a sub-tree image's at its device scale — three
/// copies of it once. It multiplies by the scale and divides back, which is
/// exact whenever the scale is a power of two, so every level grid lands to
/// the bit where the copy that divided by the level's step put it.
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
/// [level] is the level the image being cut was composed at
/// ([displayLevelOf]): the buffer's blit and the paper inside a level
/// buffer are reduced by the residual, not the device scale, and at
/// exactly 50% that residual is 1 — nearest, and the edge is cut on the
/// grid like any 1:1 view's. Level 0 (the default) is the device scale
/// itself: the walk, and playback's canvas-resolution composite.
///
/// An edge this answers false for is cut by moving it ONTO the grid
/// ([cutOnThePixelGrid]), not by asking the engine not to blend it.
bool displayEdgeAntiAliased(
  CanvasViewport viewport,
  double devicePixelRatio, {
  int level = 0,
}) =>
    viewport.rotationDegrees != 0 ||
    filterQualityForDisplayScale(
          displayScaleOf(viewport.zoom, devicePixelRatio) * (1 << level),
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
  final m = canvas.getTransform();
  if (m[1] != 0 || m[4] != 0 || m[3] != 0 || m[7] != 0 || m[15] != 1) {
    return rect;
  }
  final (sx, sy) = (m[0] * pixelRatio, m[5] * pixelRatio);
  final (tx, ty) = (m[12] * pixelRatio, m[13] * pixelRatio);
  if (sx == 0 || sy == 0) {
    return rect;
  }
  double cut(double value, double scale, double origin) =>
      (((value * scale + origin) - 0.5).ceilToDouble() - origin) / scale;
  return ui.Rect.fromPoints(
    ui.Offset(cut(rect.left, sx, tx), cut(rect.top, sy, ty)),
    ui.Offset(cut(rect.right, sx, tx), cut(rect.bottom, sy, ty)),
  );
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
/// handed: one composed at [level] ([displayLevelOf]) — 0 for one at
/// canvas resolution — of the world [viewport] shows on a screen of
/// [devicePixelRatio], under the canvas's transform. It samples by the
/// scale the draw resamples it by ([filterQualityForDisplayScale]) and cuts
/// its edge by the same law ([displayEdgeAntiAliased]).
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
  int level = 0,
  ui.BlendMode blendMode = ui.BlendMode.srcOver,
}) {
  final filterQuality = filterQualityForDisplayScale(
    displayScaleOf(viewport.zoom, devicePixelRatio) * (1 << level),
  );
  // The image's edge IS the canvas's edge on screen, cut by the same law
  // as the paper's (F-67-paper-edge): under nearest on an axis-aligned
  // view it is one more texel boundary, decided by pixel centres, not a
  // blended line.
  if (displayEdgeAntiAliased(viewport, devicePixelRatio, level: level)) {
    canvas.drawImageRect(
      image,
      src,
      dst,
      ui.Paint()
        ..filterQuality = filterQuality
        ..blendMode = blendMode,
    );
  } else {
    drawImageRectOnThePixelGrid(
      canvas,
      image,
      src,
      dst,
      filterQuality: filterQuality,
      pixelRatio: devicePixelRatio,
      blendMode: blendMode,
    );
  }
}

/// [image]'s [src] laid over [dst] as `drawImageRect` lays it — each pixel
/// shows what its centre falls on — with the edge cut on the grid
/// ([cutOnThePixelGrid]): the texels ride a shader mapped [src] → [dst],
/// and only the rect it fills is cut, so moving the edge moves no texel.
/// Every pixel inside the cut rect has its centre inside [dst], so nothing
/// past the image is ever shown.
void drawImageRectOnThePixelGrid(
  ui.Canvas canvas,
  ui.Image image,
  ui.Rect src,
  ui.Rect dst, {
  required ui.FilterQuality filterQuality,
  required double pixelRatio,
  ui.BlendMode blendMode = ui.BlendMode.srcOver,
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
    canvas.drawRect(
      cutOnThePixelGrid(canvas, dst, pixelRatio),
      ui.Paint()
        ..shader = shader
        ..isAntiAlias = false
        ..blendMode = blendMode,
    );
  } finally {
    // The drawing holds the shader from the draw on, as it holds an image.
    shader.dispose();
  }
}
