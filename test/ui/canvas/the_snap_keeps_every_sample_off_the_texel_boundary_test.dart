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

  test('🚨off the exact scales the phase is never worse than the sixteenth '
      'search it replaced — a wheel notch, a pinch (review 2026-09-15)', () {
    // The search F-83 replaced, kept here as the oracle the law has to
    // match or beat: the sixteenth of a pixel with the best true margin.
    double searched(double s) {
      var best = 0.0;
      var bestMargin = -1.0;
      for (var sixteenth = 0; sixteenth < 16; sixteenth += 1) {
        final least = margin(s, sixteenth / 16);
        if (least > bestMargin + 1e-9) {
          bestMargin = least;
          best = sixteenth / 16;
        }
      }
      return best;
    }

    void neverWorse(double s, String what) {
      final chosen = margin(s, samplingPhaseFor(s));
      final old = margin(s, searched(s));
      expect(
        chosen,
        greaterThanOrEqualTo(old - 1e-12),
        reason: '$what (scale $s): phase ${samplingPhaseFor(s)} leaves a '
            'sample $chosen from a texel boundary where the search kept $old',
      );
    }

    // 39/2 − 4.1e-5: the continued fraction runs on to q = 12113, whose
    // phase (0) left a sample 2.1e-6 of a texel from a boundary; a quarter
    // pixel keeps every one about a hundredth away.
    const nextToAHalf = 19.49995872029756;
    expect(
      margin(nextToAHalf, samplingPhaseFor(nextToAHalf)),
      greaterThan(0.01),
    );
    neverWorse(nextToAHalf, 'next to 39/2');
    // An EXACT fraction whose residues outrun the measured pixels (p > 16,384):
    // not every residue lands inside them, so the denominator's phase is no
    // longer the best one and the law has to measure. Taken as exact it kept
    // half the margin the search found — measured 2026-09-15, 152 of 152
    // such fractions.
    neverWorse(16459 / 400, 'p = 16459 past the measured pixels');
    // Wheel notches (×1.1 each) from the zooms a view starts at, at the
    // monitor ratios the app meets.
    for (final ratio in const [1.0, 1.25, 1.5, 1.75, 2.0]) {
      for (final start in const [1.0, 0.5, 0.8347]) {
        var zoom = start / ratio;
        for (var notch = 1; notch <= 30; notch += 1) {
          zoom *= 1.1;
          final s = zoom * ratio;
          if (s > 1 && s <= 32) {
            neverWorse(s, '$notch notches from $start at $ratio');
          }
        }
      }
    }
    // And a spread of the scales a pinch passes through on its way.
    var s = 1.0;
    for (var step = 1; step <= 120; step += 1) {
      s *= 1.0293;
      neverWorse(s, 'pinch step $step');
    }
    // Where a convergent's phase does better than every sixteenth, the law
    // takes it: fourteen wheel notches from 100% (measured 2026-09-15 —
    // 3.43e-5 of a texel against the search's 3.36e-5).
    var notched = 1.0;
    for (var notch = 0; notch < 14; notch += 1) {
      notched *= 1.1;
    }
    expect(
      margin(notched, samplingPhaseFor(notched)),
      greaterThan(margin(notched, searched(notched)) + 1e-7),
      reason: 'the convergents are candidates for a reason',
    );
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
