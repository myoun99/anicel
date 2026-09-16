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
ui.FilterQuality filterQualityForDisplayScale(double scale) =>
    scale < 1 ? ui.FilterQuality.low : ui.FilterQuality.none;

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
/// ⚠️Impeller may not honour `isAntiAlias = false` at all. If it does not,
/// those devices keep the blended line they have today, which is no worse;
/// the phase snap does not depend on this either way.
/// 🆕2026-09-16: this stopped being unverifiable here — Impeller became the
/// default on Windows in Flutter 3.47 and this repo moved to it, so the
/// desktop now draws the edge the same engine the tablets do. ⚠️Still
/// unverified: nobody has looked at the boundary since.
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
