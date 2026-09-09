import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/services/brush_dab_tip_geometry.dart';

/// 🚨★★★THE STAMP CACHE **BAKES** THIS LAW, AND A STROKE PICKS THE BAKED
/// ROUTE OR THE DIRECT ONE BY CACHE STATE ALONE.
///
/// Three routes evaluated the analytic tip: the coverage list (the commit
/// oracle and the brush preview), the tile kernel, and the stamp cache that
/// renders a tip ONCE into a mask. So a falloff changed in one place made
/// the same brush paint two different edges depending on what happened to
/// be cached. The coverage list and the cache call this law now; the tile
/// kernel keeps writing it out on purpose (its own decision comment:
/// nothing in the per-pixel loop becomes indirect, because nothing inlines
/// in a debug build) and the commit parity suite pins it byte-exact
/// against the oracle.
void main() {
  BrushTipNumbers round({
    double size = 20,
    double hardness = 1,
    double roundness = 1,
    double angleDegrees = 0,
    BrushTipMask? tipMask,
  }) => (
    size: size,
    hardness: hardness,
    roundness: roundness,
    angleDegrees: angleDegrees,
    tipShape: BrushTipShape.round,
    tipMask: tipMask,
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

  group('the analytic round coverage', () {
    test('a HARD tip is full inside and nothing outside', () {
      final tip = brushTipGeometry(round());
      expect(analyticRoundTipCoverage(tip, 0, 0), 1.0);
      expect(analyticRoundTipCoverage(tip, 9.5, 0), 1.0);
      expect(
        analyticRoundTipCoverage(tip, 10.5, 0),
        0.0,
        reason:
            'past the radius the tip does not reach — callers skip on <= 0, '
            'which is how the cascade always ended',
      );
    });

    test('a SOFT tip falls off linearly from the hard radius to the rim', () {
      final tip = brushTipGeometry(round(hardness: 0));
      // hardRadius 0, radius 10 — halfway out is half covered.
      expect(analyticRoundTipCoverage(tip, 5, 0), closeTo(0.5, 1e-12));
      expect(analyticRoundTipCoverage(tip, 0, 0), 1.0);
      expect(analyticRoundTipCoverage(tip, 10, 0), closeTo(0, 1e-12));
    });

    test('an ELLIPSE reaches further along its major axis than its minor', () {
      final tip = brushTipGeometry(round(roundness: 0.5));
      expect(
        analyticRoundTipCoverage(tip, 9, 0),
        greaterThan(0),
        reason: 'the major axis is the radius',
      );
      expect(
        analyticRoundTipCoverage(tip, 0, 9),
        0.0,
        reason: 'the minor axis is squashed by the roundness',
      );
    });

    test('a 90 degree ellipse swaps the axes', () {
      final tip = brushTipGeometry(round(roundness: 0.5, angleDegrees: 90));
      expect(analyticRoundTipCoverage(tip, 0, 9), greaterThan(0));
      expect(analyticRoundTipCoverage(tip, 9, 0), 0.0);
    });

    test('a zero-width falloff band is FULL, not a divide by zero', () {
      // hardness 1 makes hardRadius == radius, so the band is empty.
      final tip = brushTipGeometry(round());
      final atRim = analyticRoundTipCoverage(tip, 10, 0);
      expect(atRim, 1.0);
      expect(atRim.isFinite, isTrue);
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
      expect(rotatedTipMaskCoverage(tip, mask, 0, 0), greaterThan(0.9));
      expect(
        rotatedTipMaskCoverage(tip, mask, 11, 0),
        0.0,
        reason:
            'outside the mask square the sampler is not even asked — the '
            'skip the callers already made',
      );
    });

    test('an EMPTY mask covers nothing, so a caller skips', () {
      final mask = BrushTipMask(id: 'empty', size: 8, alpha: Uint8List(64));
      final tip = brushTipGeometry(round(tipMask: mask));
      expect(rotatedTipMaskCoverage(tip, mask, 0, 0), 0.0);
    });
  });
}
