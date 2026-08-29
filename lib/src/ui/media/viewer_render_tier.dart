import 'dart:ui' as ui;

/// 1/16 of the page: past this a raster is too coarse to be worth keeping,
/// and the zoom that asks for it is on its way somewhere.
const double viewerMinRenderScale = 1 / 16;

/// One page is never rasterised above this, whatever the zoom asks.
const int viewerMaxRenderPixels = 16 * 1024 * 1024;

/// The scale to rasterise a page at, for a view showing it at [zoom].
///
/// Powers of two so a settled zoom reuses its raster, rounded UP so the
/// raster always has at least the pixels being drawn.
///
/// 🚨★★★**IT GOES BELOW 1.** A page shown at a quarter of its size does
/// not need its full pixels — and the tier used to bottom out at 1, which
/// for a PDF meant「the page at 72dpi」(small) but for an IMAGE means
/// 「every pixel the file has」.
///
/// That is how an 8000×6000 photo still decoded at 8000×6000 while sitting
/// fitted inside a panel: the pixels of the file, held to draw a fraction
/// of them. 유저 2026-08-29 asked exactly this — 「100%로 fit인 상태로
/// 축소해도 전 최대 디코드 크기보다 압도적으로 작아진단거 맞지?」 — and the
/// answer was no until this went in.
///
/// ⛔A DOWNSCALE of the whole page, never a crop. Panning draws from this
/// same raster, so a viewport-shaped one would tear on the first drag.
///
/// 🚨Pure arithmetic, and public, because it was WRONG while it lived
/// inside the widget's State where only a pumped panel could reach it —
/// and a pumped panel re-frames its own viewport, so the one input that
/// decides could not be driven from a test at all.
double viewerRenderScaleFor(double zoom, ui.Size pageSize) {
  var scale = 1.0;
  while (scale < zoom && scale < 8) {
    scale *= 2;
  }
  while (scale / 2 >= zoom && scale > viewerMinRenderScale) {
    scale /= 2;
  }
  while (scale > viewerMinRenderScale &&
      pageSize.width * scale * pageSize.height * scale > viewerMaxRenderPixels) {
    scale /= 2;
  }
  return scale;
}
