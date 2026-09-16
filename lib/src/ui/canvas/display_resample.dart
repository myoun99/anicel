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
/// ⚠️This only MEANS anything if there is one resample to apply it to.
/// Applied per layer it would still be N resamples that merely agree with
/// each other; the composite buffer is what turns it into the law
/// ([[editing-canvas-composite-cache-program]] stage 2).
ui.FilterQuality filterQualityForDisplayScale(double scale) =>
    scale < 1 ? ui.FilterQuality.low : ui.FilterQuality.none;

/// The scale a canvas-space image is actually resampled by on screen.
///
/// Rotation and flips do not change how many artwork pixels land on a
/// screen pixel — only the zoom does — so the law reads the zoom and
/// nothing else. Taken from the viewport rather than from the CTM because
/// the CTM at paint time also carries the device pixel ratio, and a 2× DPR
/// screen at 100% zoom is still 1:1 artwork-to-canvas: the buffer is at
/// canvas resolution, so it is the canvas-to-view scale that decides.
double displayScaleOf(double zoom) => zoom.abs();

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
/// ⚠️Impeller may not honour `isAntiAlias = false` at all. If it does not,
/// those devices keep the blended line they have today, which is no worse;
/// the phase snap does not depend on this either way.
/// 🆕2026-09-16: this stopped being unverifiable here — Impeller became the
/// default on Windows in Flutter 3.47 and this repo moved to it, so the
/// desktop now draws the edge the same engine the tablets do. ⚠️Still
/// unverified: nobody has looked at the boundary since.
bool displayEdgeAntiAliased(CanvasViewport viewport) =>
    viewport.rotationDegrees != 0 ||
    filterQualityForDisplayScale(displayScaleOf(viewport.zoom)) !=
        ui.FilterQuality.none;
