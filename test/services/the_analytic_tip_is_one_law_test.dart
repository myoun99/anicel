import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/services/brush_dab_tip_geometry.dart';

/// 🚨★★★ONE LAW FOR EVERY ROUTE THAT EVALUATES THE ANALYTIC TIP.
///
/// Three routes evaluated it: the coverage list (the commit oracle and the
/// brush preview), the tile kernel, and the stamp cache that rendered a tip
/// ONCE into a mask — so a falloff changed in one place made the same brush
/// paint two different edges depending on what happened to be cached. The
/// coverage list and the tile kernel call this law — ↩️the tile kernel
/// wrote it out a fourth time until 2026-10-23 (board
/// `the-brush-kernel-turns-a-pixel-into-tip-space-in-two-places`) — and
/// ↩️the stamp cache baked a round tip with it until 2026-10-25: a round
/// tip is its profile now (`RoundTipProfile`), whose tables the C kernel
/// reads too. The commit parity suite pins it byte-exact against the
/// oracle.
void main() {
  BrushTipNumbers round({
    double size = 20,
    double hardness = 1,
    double roundness = 1,
    double angleDegrees = 0,
    BrushTipMask? tipMask,
    BrushTipEdge edge = (
      width: 0.0,
      widthPerRadius: 0.0,
      inset: 0.0,
      insetReach: 1.0,
    ),
  }) => (
    size: size,
    hardness: hardness,
    roundness: roundness,
    angleDegrees: angleDegrees,
    tipShape: BrushTipShape.round,
    tipMask: tipMask,
    edge: edge,
  );

  /// An edge [width] wide at every radius.
  BrushTipEdge flat(
    double width, {
    double inset = 0.0,
    double insetReach = 1.0,
  }) => (
    width: width,
    widthPerRadius: 0.0,
    inset: inset,
    insetReach: insetReach,
  );

  group('what the geometry decides once, before the pixel loop', () {
    test('a plain round tip is not an ellipse', () {
      final tip = brushTipGeometry(round());
      expect(tip.radius, 10);
      expect(tip.isRound, isTrue);
      expect(tip.isEllipse, isFalse);
      expect(
        tip.tipCos,
        1.0,
        reason:
            'the rotation terms stay identity when nothing rotates — the '
            'pixel loop reads them either way',
      );
      expect(tip.tipSin, 0.0);
      expect(tip.inverseRoundness, 1.0);
    });

    test('a quarter-turned tip turns by the table — exactly, no 6e-17', () {
      // The C kernel takes these same two numbers, so a residue here would
      // be a 90° tip that misses its lattice on both engines alike — the
      // parity suites cannot see it.
      final mask = BrushTipMask(id: 't', size: 2, alpha: Uint8List(4));
      for (final (degrees, cos, sin) in [
        (90.0, 0.0, 1.0),
        (180.0, -1.0, 0.0),
        (270.0, 0.0, -1.0),
      ]) {
        for (final tip in [
          brushTipGeometry(round(roundness: 0.5, angleDegrees: degrees)),
          brushTipGeometry(round(tipMask: mask, angleDegrees: degrees)),
        ]) {
          expect(tip.tipCos, cos, reason: '$degrees°');
          expect(tip.tipSin, sin, reason: '$degrees°');
        }
      }
    });

    test('roundness below one makes it an ellipse, and the minor radius '
        'follows the roundness', () {
      final tip = brushTipGeometry(round(roundness: 0.5));
      expect(tip.isEllipse, isTrue);
      expect(tip.minorRadius, closeTo(5, 1e-12));
      expect(tip.inverseRoundness, closeTo(2, 1e-12));
    });

    test(
      'a RASTER tip is never an ellipse — the mask carries its own shape',
      () {
        final mask = BrushTipMask(id: 't', size: 2, alpha: Uint8List(4));
        final tip = brushTipGeometry(round(roundness: 0.5, tipMask: mask));
        expect(tip.isEllipse, isFalse);
        expect(
          tip.inverseRoundness,
          closeTo(2, 1e-12),
          reason: 'the sampler still needs the roundness term to un-squash',
        );
      },
    );
  });

  // A round tip is two ramps and a pixel's square, read along its radius
  // (board a-one-pixel-dab-drops-out-by-where-it-lies Q4, 2026-10-25).
  group('the analytic round coverage', () {
    test('a HARD tip is full inside, half at its rim, and nothing half a '
        'pixel past it', () {
      final tip = brushTipGeometry(round());
      expect(tipCoverageAt(tip, 0, 0), 1.0);
      expect(tipCoverageAt(tip, 9.5, 0), 1.0);
      expect(
        tipCoverageAt(tip, 10, 0),
        closeTo(0.5, 1e-12),
        reason: 'the square of a pixel on the rim lies half inside',
      );
      expect(tipCoverageAt(tip, 10.25, 0), closeTo(0.25, 1e-12));
      expect(
        tipCoverageAt(tip, 10.5, 0),
        0.0,
        reason:
            'past the reach the tip lays nothing — callers skip on <= 0, '
            'which is how the cascade always ended',
      );
    });

    test('a SOFT tip falls off linearly from the hard radius to the rim, '
        'as a pixel\'s square covers the ramp', () {
      final tip = brushTipGeometry(round(hardness: 0));
      // The ramp runs from the centre to 10 — halfway out is half covered.
      expect(tipCoverageAt(tip, 5, 0), closeTo(0.5, 1e-12));
      expect(
        tipCoverageAt(tip, 0, 0),
        closeTo(0.975, 1e-12),
        reason: 'the centre pixel\'s square reaches half a pixel down the ramp',
      );
      expect(tipCoverageAt(tip, 10, 0), closeTo(0.0125, 1e-12));
    });

    test('an ELLIPSE reaches further along its major axis than its minor', () {
      final tip = brushTipGeometry(round(roundness: 0.5));
      expect(
        tipCoverageAt(tip, 9, 0),
        greaterThan(0),
        reason: 'the major axis is the radius',
      );
      expect(
        tipCoverageAt(tip, 0, 9),
        0.0,
        reason: 'the minor axis is squashed by the roundness',
      );
    });

    test('a 90 degree ellipse swaps the axes', () {
      final tip = brushTipGeometry(round(roundness: 0.5, angleDegrees: 90));
      expect(tipCoverageAt(tip, 0, 9), greaterThan(0));
      expect(tipCoverageAt(tip, 9, 0), 0.0);
    });

    test('a zero-width ramp is a step under the square, not a divide by '
        'zero', () {
      // hardness 1 and no edge: both ramps are zero wide.
      final tip = brushTipGeometry(round());
      final atRim = tipCoverageAt(tip, 10, 0);
      expect(atRim.isFinite, isTrue);
      expect(atRim, closeTo(0.5, 1e-12));
    });
  });

  // I-50 (유저 2026-09-30 「경도와 따로 — 단계마다 고정 폭」): the anti-alias
  // step gives a round tip an edge its width wide, INSIDE the rim — and
  // where the hardness ramp is lower, that one.
  group('the anti-alias edge', () {
    test('it falls inside the rim and leaves the radius where it was', () {
      final tip = brushTipGeometry(round(edge: flat(2.0)));
      expect(tip.radius, 10, reason: 'the rim is the thickness that holds');
      expect(tipCoverageAt(tip, 7.5, 0), 1.0);
      expect(tipCoverageAt(tip, 9, 0), closeTo(0.5, 1e-12));
      expect(tipCoverageAt(tip, 10.5, 0), 0.0);
    });

    test('its inset pulls its rim in — in full from its reach up, by the '
        'radius below it', () {
      final edge = flat(0.0, inset: 0.5, insetReach: 2.0);
      final large = brushTipGeometry(round(edge: edge));
      expect(tipCoverageAt(large, 9.5, 0), closeTo(0.5, 1e-12));
      final small = brushTipGeometry(round(size: 2, edge: edge));
      expect(
        tipCoverageAt(small, 0.75, 0),
        closeTo(0.5, 1e-12),
        reason: 'a radius of 1 is half the reach: half the inset',
      );
    });

    test('it widens with the radius as far as the samples reach, and no '
        'further', () {
      // Clip Studio's edge is wider on a bigger nib (Q4's fit); past the
      // largest sample it holds (Q5).
      const edge = (
        width: 1.0,
        widthPerRadius: 0.04,
        inset: 0.0,
        insetReach: 1.0,
      );
      double halfway(double radius) {
        // A hard nib's edge is a straight ramp, so its half-coverage point
        // is halfway down it: the rim less half the width.
        final tip = brushTipGeometry(round(size: radius * 2, edge: edge));
        var lo = 0.0;
        var hi = radius + 0.5;
        for (var i = 0; i < 60; i += 1) {
          final mid = (lo + hi) / 2;
          if (tipCoverageAt(tip, mid, 0) > 0.5) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        return radius - lo;
      }

      expect(halfway(5), closeTo((1.0 + 0.04 * 5) / 2, 1e-6));
      expect(halfway(25), closeTo((1.0 + 0.04 * 25) / 2, 1e-6));
      expect(
        halfway(100),
        closeTo(halfway(25), 1e-6),
        reason: 'past edgeSampledRadius the width holds',
      );
      expect(edgeSampledRadius, 25.0);
    });

    test('a hardness ramp lower than the step stands to the bit', () {
      final plain = brushTipGeometry(round(hardness: 0.5));
      final stepped = brushTipGeometry(round(hardness: 0.5, edge: flat(2.75)));
      for (var d = 0.0; d <= 10.5; d += 0.25) {
        expect(
          tipCoverageAt(stepped, d, 0),
          tipCoverageAt(plain, d, 0),
          reason: 'at $d',
        );
      }
    });

    test('it moves continuously with hardness — no jump where the two '
        'ramps trade places', () {
      final edge = flat(2.75);
      const distances = [7.0, 8.0, 9.0, 9.5, 10.0];
      List<double> at(double h) => [
        for (final d in distances)
          tipCoverageAt(brushTipGeometry(round(hardness: h, edge: edge)), d, 0),
      ];
      var previous = at(0.5);
      for (var h = 0.501; h <= 1.0; h += 0.001) {
        final next = at(h);
        for (var i = 0; i < distances.length; i += 1) {
          expect(
            (next[i] - previous[i]).abs(),
            lessThan(0.01),
            reason: 'at hardness $h, ${distances[i]}px out',
          );
        }
        previous = next;
      }
    });

    test('a tip smaller than its edge is all edge, a cone to its rim', () {
      final tip = brushTipGeometry(round(size: 4, edge: flat(2.75)));
      expect(tipCoverageAt(tip, 0, 0), closeTo(0.875, 1e-12));
      expect(tipCoverageAt(tip, 1, 0), closeTo(0.5, 1e-12));
      expect(tipCoverageAt(tip, 2.5, 0), 0.0);
    });
  });

  // What of the coverage piles where dabs overlap (유저 2026-10-25 「AA
  // 가장자리는 쌓이지 않는다」): the hardness alone — the rest is edge.
  group('the pile', () {
    test('a hard tip\'s whole reach piles, its edge included', () {
      final tip = brushTipGeometry(round(edge: BrushAntiAlias.high.edge));
      for (var d = 0.0; d < 10.5; d += 0.25) {
        expect(tipPileAt(tip, d, 0), 1.0, reason: 'at $d');
      }
      expect(
        tipCoverageAt(tip, 9.5, 0),
        lessThan(1.0),
        reason: 'premise: the edge covers less than it piles',
      );
    });

    test('a soft tip piles its hardness as the square\'s nearest point '
        'reads it', () {
      final tip = brushTipGeometry(round(hardness: 0));
      expect(tipPileAt(tip, 5, 0), closeTo(0.55, 1e-12));
      expect(tipPileAt(tip, 0.25, 0), 1.0);
    });

    test('it is never under the coverage — so the edge\'s ceiling is never '
        'over one', () {
      for (final size in [1.0, 1.5, 3.0, 10.0, 50.0]) {
        for (final hardness in [0.0, 0.5, 1.0]) {
          for (final step in BrushAntiAlias.values) {
            final tip = brushTipGeometry(
              round(size: size, hardness: hardness, edge: step.edge),
            );
            for (var d = 0.0; d < size / 2 + 0.5; d += 0.0625) {
              expect(
                tipPileAt(tip, d, 0),
                greaterThanOrEqualTo(tipCoverageAt(tip, d, 0) - 1e-12),
                reason: 'size $size, hardness $hardness, $step, at $d',
              );
            }
          }
        }
      }
    });

    test('a raster tip and a square pile all they cover, and hold no edge',
        () {
      final mask = BrushTipMask(
        id: 'ramp',
        size: 4,
        alpha: Uint8List.fromList([for (var i = 0; i < 16; i += 1) i * 16]),
      );
      final raster = brushTipGeometry(round(tipMask: mask, size: 8));
      final square = brushTipGeometry((
        size: 8,
        hardness: 0,
        roundness: 1,
        angleDegrees: 0,
        tipShape: BrushTipShape.square,
        tipMask: null,
        edge: BrushAntiAlias.high.edge,
      ));
      const law = (threshold: false, contrast: 1.0);
      for (final tip in [raster, square]) {
        expect(tipHoldsAnEdge(tip, law), isFalse);
        for (var d = -4.0; d <= 4.0; d += 0.5) {
          expect(tipPileAt(tip, d, d / 2), tipCoverageAt(tip, d, d / 2));
        }
      }
    });

    test('an analytic round tip holds its edge under every step but 없음', () {
      final tip = brushTipGeometry(round(edge: BrushAntiAlias.low.edge));
      expect(tipHoldsAnEdge(tip, (threshold: false, contrast: 1.0)), isTrue);
      expect(tipHoldsAnEdge(tip, (threshold: true, contrast: 1.0)), isFalse);
    });
  });

  group('the rotated raster tip', () {
    BrushTipMask solid(int size) => BrushTipMask(
      id: 'solid',
      size: size,
      alpha: Uint8List(size * size)..fillRange(0, size * size, 255),
    );

    test('a solid mask covers the middle and stops at its own square', () {
      final mask = solid(8);
      final tip = brushTipGeometry(round(tipMask: mask));
      expect(tipCoverageAt(tip, 0, 0), greaterThan(0.9));
      expect(
        tipCoverageAt(tip, 11, 0),
        0.0,
        reason:
            'outside the mask square the sampler is not even asked — the '
            'skip the callers already made',
      );
    });

    test('an EMPTY mask covers nothing, so a caller skips', () {
      final mask = BrushTipMask(id: 'empty', size: 8, alpha: Uint8List(64));
      final tip = brushTipGeometry(round(tipMask: mask));
      expect(tipCoverageAt(tip, 0, 0), 0.0);
    });
  });

  test('a square tip covers its whole square — its bounds are its edge', () {
    final tip = brushTipGeometry((
      size: 20,
      hardness: 0,
      roundness: 1,
      angleDegrees: 0,
      tipShape: BrushTipShape.square,
      tipMask: null,
      edge: BrushAntiAlias.high.edge,
    ));
    expect(tipCoverageAt(tip, 0, 0), 1.0);
    expect(
      tipCoverageAt(tip, 9.9, 9.9),
      1.0,
      reason: 'a corner a round tip would not reach',
    );
  });
}
