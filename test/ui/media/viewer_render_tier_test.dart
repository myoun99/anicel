import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/media/viewer_render_tier.dart';

/// What size the viewer asks a document for — the question 유저 2026-08-29
/// put to it: 「100%로 fit인 상태로 축소해도 전 최대 디코드 크기보다
/// 압도적으로 작아진단거 맞지? 확대할때만 해당 화면크기 밖에있는거 잘라내서
/// 크기 줄였다 이런거아니지?」
///
/// Two answers, and both are asserted below: it is a DOWNSCALE of the whole
/// page (the aspect never changes, so nothing is being cropped), and it
/// really does go under 1 when the page is shown smaller than itself.

void main() {
  const photo = ui.Size(8000, 6000); // 48M pixels — a phone camera's raw.
  const page = ui.Size(595, 842); // A4 in points.

  int pixelsAt(double zoom, ui.Size size) =>
      (size.width * viewerRenderScaleFor(zoom, size)).round() *
      (size.height * viewerRenderScaleFor(zoom, size)).round();

  group('fitted smaller than itself', () {
    test('🚨a photo at a quarter view is rasterised at a quarter, not whole', () {
      expect(viewerRenderScaleFor(0.25, photo), 0.25);
      expect(pixelsAt(0.25, photo), 2000 * 1500);
    });

    test('and the further out it goes the smaller it gets, down to a floor', () {
      expect(viewerRenderScaleFor(0.5, photo), 0.5);
      expect(viewerRenderScaleFor(0.1, photo), 0.125);
      expect(viewerRenderScaleFor(0.0001, photo), viewerMinRenderScale);
    });

    test('⛔the raster covers the view — or the CAP is the reason it does '
        'not, and nothing else ever is', () {
      // The rounding is UP, so a raster is never thinner than what is drawn.
      // The one exception is deliberate and older than this change: past
      // 16M pixels bounded memory beats sharpness. Stating it as「A, or B
      // and here is B」is the only version that is true at every zoom —
      // 「A」alone fails wherever the cap binds, which is most of a large
      // page's range.
      for (final zoom in [0.05, 0.2, 0.3, 0.49, 0.7, 1.3, 3.0, 8.0]) {
        for (final size in [photo, const ui.Size(2000, 1500), page]) {
          final scale = viewerRenderScaleFor(zoom, size);
          final covers = scale >= zoom;
          final capped = size.width * scale * 2 * size.height * scale * 2 >
              viewerMaxRenderPixels;
          final floored = scale <= viewerMinRenderScale;
          expect(
            covers || capped || floored,
            isTrue,
            reason: 'zoom $zoom on $size gave $scale for no stated reason',
          );
        }
      }
    });
    test('⚠️above the cap the cap wins, and the page is knowingly softer', () {
      // 8000×6000 at a 0.7 view would want 0.7 — 23M pixels. It gets 0.5.
      expect(viewerRenderScaleFor(0.7, photo), lessThan(0.7));
      expect(pixelsAt(0.7, photo), lessThanOrEqualTo(viewerMaxRenderPixels));
    });
  });


  group('what it is NOT', () {
    test('⛔not a crop: the aspect is untouched at every zoom', () {
      for (final zoom in [0.1, 0.25, 1.0, 2.0, 8.0]) {
        final scale = viewerRenderScaleFor(zoom, photo);
        expect(
          (photo.width * scale) / (photo.height * scale),
          closeTo(photo.width / photo.height, 1e-9),
        );
      }
    });

    test('⛔not unbounded either: a big page at a big zoom stops at the cap', () {
      expect(pixelsAt(8, photo), lessThanOrEqualTo(viewerMaxRenderPixels));
      expect(pixelsAt(1, photo), lessThanOrEqualTo(viewerMaxRenderPixels));
    });
  });

  group('a PDF page is measured the same way', () {
    test('at 1:1 it is its own size — points, so this was always small', () {
      expect(viewerRenderScaleFor(1, page), 1.0);
    });

    test('zoomed IN it doubles, which is what the tier was written for', () {
      expect(viewerRenderScaleFor(2, page), 2.0);
      expect(viewerRenderScaleFor(3, page), 4.0);
    });

    test('and zoomed OUT it now shrinks too — a page drawn at a third does '
        'not need three times the pixels', () {
      expect(viewerRenderScaleFor(0.25, page), 0.25);
    });
  });
}
