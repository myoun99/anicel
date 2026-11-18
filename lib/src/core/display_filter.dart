import 'dart:ui' as ui;

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
/// [scale] is the scale of the resample in question: `displayScaleOf`
/// (`ui/canvas/display_resample.dart`) for a canvas-resolution image —
/// every image the display is handed.
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
///
/// 📍Here, under `core/`, and not beside the display's other laws in
/// `ui/canvas/display_resample.dart`, because a lay that is no display
/// asks it too (🗣️I-120-Q26, 유저 2026-11-07 「굽기를 화면에 맞춘다」 —
/// `raster_cel_import.dart`, a service, which may not reach into `ui/`).
/// The engine's screen reads this answer, not a threshold of its own
/// (brush/rendering, I-120 11-08 00:00: `none` is its Nearest, the rest
/// its Blend).
ui.FilterQuality filterQualityForDisplayScale(double scale) => scale <= 0.5
    ? ui.FilterQuality.medium
    : scale < 1
    ? ui.FilterQuality.low
    : ui.FilterQuality.none;
