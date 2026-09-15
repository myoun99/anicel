import 'package:anicel/src/models/app_ui_scale.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-67 (유저 2026-09-10, confirmed 09-11): 「일부 정해진 픽셀이 반픽셀
/// 움직였다가 돌아오는」 at pen-down/up, tool change and pan — at
/// 105·110·115·125·130·135·150·175·250% and at NO whole or 120/140/160/
/// 180% zoom. Above 1 the display samples at `FilterQuality.none`, so
/// device pixel i reads texel `floor((i + 0.5 - t) / s)`; with the render
/// translation t snapped to whole device pixels, a scale s = p/q with p odd
/// and q even puts one column in every q EXACTLY on a texel boundary, and
/// float rounding — different on the engine's cached and live paths —
/// decides which texel it shows. The hands-on pattern is exactly the
/// p-odd/q-even set.
///
/// The snap now chooses the sub-pixel phase that keeps every visible
/// sample point as far from a boundary as the scale allows. These are the
/// numbers.
void main() {
  /// The smallest distance from a texel boundary any device pixel centre
  /// within 8192 px of the origin samples at, for translation [phase] and
  /// scale [s].
  double margin(double s, double phase) {
    var least = 0.5;
    for (var j = -8192; j < 8192; j += 1) {
      final u = (j + 0.5 - phase) / s;
      final d = (u - u.roundToDouble()).abs();
      if (d < least) {
        least = d;
      }
    }
    return least;
  }

  test('whole pixels put a column on the boundary at every hop zoom, and '
      'at none of the zooms that did not hop', () {
    // p odd, q even: exact ties under a whole-pixel translation.
    for (final zoom in <double>[1.05, 1.1, 1.15, 1.25, 1.3, 1.35, 1.5, 1.75, 2.5]) {
      expect(
        margin(zoom, 0),
        lessThan(1e-9),
        reason: '$zoom: a whole-pixel snap must produce exact ties here — '
            'that is the mechanism this file pins',
      );
    }
    // The zooms the hands-on found clean: no exact tie under whole pixels.
    for (final zoom in <double>[1.2, 1.4, 1.6, 1.8, 2.0, 3.0, 4.0]) {
      expect(
        margin(zoom, 0),
        greaterThan(1e-3),
        reason: '$zoom: whole pixels keep every sample off the boundary',
      );
    }
  });

  test('the chosen phase keeps every sample at least 1/(2p) of a texel off '
      'the boundary at every 1%-step zoom from 101% to 400%', () {
    // For s = p/q the sample residues step through every multiple of q
    // modulo p, so the best any phase can do is put them on the half:
    // 1/(2p) of a texel, with p at most the percentage itself.
    for (var percent = 101; percent <= 400; percent += 1) {
      final s = percent / 100;
      final phase = samplingPhaseFor(s);
      expect(
        margin(s, phase),
        greaterThanOrEqualTo(1 / (2 * percent) - 1e-9),
        reason: '$percent%: phase $phase leaves a sample '
            '${margin(s, phase)} from a texel boundary',
      );
    }
    // And the two the hands-on named, with room to spare.
    expect(margin(1.1, samplingPhaseFor(1.1)), closeTo(1 / 22, 1e-9));
    expect(margin(1.25, samplingPhaseFor(1.25)), closeTo(1 / 10, 1e-9));
    expect(margin(1.5, samplingPhaseFor(1.5)), closeTo(1 / 6, 1e-9));
  });

  test('🚨F-83: the same holds under every display scale factor — Windows '
      '125% and 175%, and every stop of the app\'s UI-scale ladder', () {
    // 유저 2026-09-11: 「1의자리 배율에서 발생하는게 남아있는거같음」. A
    // monitor ratio multiplies the zoom's denominator: 125% is 5/4 and 175%
    // is 7/4, so a 1%-step zoom there carries 2⁴ — and a search over
    // sixteenths of a pixel found NO phase for any odd percent (150 zooms
    // each, measured 2026-09-15), and 225 at a 125% monitor under the 110%
    // UI stop.
    int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
    // Monitor ratios times EVERY stop of the app's own UI-scale ladder: the
    // product is the effective ratio the pan snap divides by
    // (`EffectiveDevicePixelRatio`). Hundredths each, so p stays exact.
    for (final monitor in const <int>[125, 150, 175, 200, 250]) {
      for (final stop in AppUiScale.ladder) {
        final ui = (stop * 100).round();
        for (var percent = 101; percent <= 400; percent += 1) {
          final numerator = percent * monitor * ui;
          const denominator = 1000000;
          final s = numerator / denominator;
          if (s <= 1) {
            // A reduction samples filtered; the law keeps whole pixels
            // there by design and claims nothing about ties.
            continue;
          }
          final p = numerator ~/ gcd(numerator, denominator);
          final phase = samplingPhaseFor(s);
          final least = margin(s, phase);
          expect(
            least,
            greaterThanOrEqualTo(1 / (2 * p) - 1e-9),
            reason: '$percent% at a $monitor% monitor and $ui% UI: phase '
                '$phase leaves a sample $least from a texel boundary',
          );
        }
      }
    }
  });

  test('1:1, every whole zoom and every reduction keep phase 0 — their '
      'bytes are what they always were', () {
    for (final s in <double>[0.25, 0.5, 0.8, 0.9, 1.0, 2.0, 3.0, 4.0, 8.0]) {
      expect(samplingPhaseFor(s), 0, reason: 'scale $s');
    }
    // The clean 1%-step zooms keep it too: whole pixels already serve them.
    for (final s in <double>[1.2, 1.4, 1.6, 1.8]) {
      expect(samplingPhaseFor(s), 0, reason: 'scale $s');
    }
  });

  test('the snapped translation is within half a device pixel of the '
      'stored pan, and lands on whole + phase', () {
    for (final (zoom, ratio) in <(double, double)>[
      (1.1, 1.0),
      (1.25, 1.25),
      (1.5, 2.0),
      (1.0, 1.25),
      (2.0, 1.5),
    ]) {
      final s = zoom * ratio;
      final phase = samplingPhaseFor(s);
      final stored = CanvasViewport(zoom: zoom, panX: 10.37, panY: -3.71);
      final snapped = renderSnappedViewport(stored, ratio);
      for (final (before, after) in <(double, double)>[
        (stored.panX, snapped.panX),
        (stored.panY, snapped.panY),
      ]) {
        final device = after * ratio;
        expect(
          ((device - phase) - (device - phase).roundToDouble()).abs(),
          lessThan(1e-9),
          reason: 'zoom $zoom at $ratio: $device is not whole + $phase',
        );
        expect(
          ((after - before) * ratio).abs(),
          lessThanOrEqualTo(0.5 + 1e-9),
          reason: 'the snap\'s budget is half a device pixel',
        );
      }
    }
  });

  test('a rotated view is left alone, as before', () {
    final stored = CanvasViewport(
      zoom: 1.1,
      panX: 10.37,
      panY: 3.71,
      rotationDegrees: 15,
    );
    expect(identical(renderSnappedViewport(stored, 1.0), stored), isTrue);
  });
}
