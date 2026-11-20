import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/services/cut_piece_stamp.dart';

/// A 4x4 opaque piece, red channel numbering the pixels.
CutPiece _piece({
  bool flipHorizontal = false,
  bool flipVertical = false,
  int scalePercent = 100,
}) {
  final rgba = Uint8List(4 * 4 * 4);
  for (var index = 0; index < 16; index += 1) {
    rgba[index * 4] = index + 1;
    rgba[index * 4 + 3] = 255;
  }
  return CutPiece(
    image: BrushStampImage(id: 'p', width: 4, height: 4, rgba: rgba),
    originLeft: 20,
    originTop: 30,
    flipHorizontal: flipHorizontal,
    flipVertical: flipVertical,
    scalePercent: scalePercent,
  );
}

void main() {
  group('the stamp dab', () {
    test('never inherits the brush: full by default, no pressure ramp', () {
      // 🚨The funnel MULTIPLIES by opacity, so a stamp that took the live
      // BRUSH state would silently carry whatever multiply was left over
      // from shading. That is still the thing being kept out — but the way
      // it is kept out changed (TP1/TP3): the stamp has an opacity field of
      // its own now, so the leak is structural rather than a constant, and
      // asking for nothing still means 100%.
      final dab = buildCutStampDab(
        piece: _piece(),
        center: CanvasPoint(x: 50, y: 50),
      );
      expect(dab.opacity, 1);
      expect(dab.flow, 1);
      expect(dab.hardness, 1);
      expect(dab.pressure, 1);
    });

    test('TP3: the stamp takes an opacity of its own', () {
      // 유저: "잘라내기의 스탬프는 불투명도 쓸수있게하고싶어." The 08-12
      // "100% 고정" was never the goal — it was the only way to block the
      // brush's opacity while one field served every tool.
      final dab = buildCutStampDab(
        piece: _piece(),
        center: CanvasPoint(x: 50, y: 50),
        opacity: 0.4,
      );
      expect(dab.opacity, 0.4);
      expect(
        identical(dab.stamp, _piece().image),
        isFalse,
        reason: 'a fresh piece each call — identity is asserted next door',
      );
    });

    test('carries the piece pixels and lands on the click point', () {
      final dab = buildCutStampDab(
        piece: _piece(),
        center: CanvasPoint(x: 50, y: 60),
      );
      expect(dab.stamp, isNotNull);
      expect(dab.stamp!.width, 4);
      expect(dab.stamp!.height, 4);
      // Centre-anchored: Clip Studio and TVPaint both do this.
      expect(dab.center.x, 50);
      expect(dab.center.y, 60);
    });

    test('at 100% the bytes are the piece, untouched', () {
      final piece = _piece();
      final dab = buildCutStampDab(
        piece: piece,
        center: CanvasPoint(x: 8, y: 8),
      );
      expect(identical(dab.stamp, piece.image), isTrue);
    });

    test('a flip re-orders bytes without resampling', () {
      final dab = buildCutStampDab(
        piece: _piece(flipHorizontal: true),
        center: CanvasPoint(x: 8, y: 8),
      );
      expect(dab.stamp!.width, 4);
      expect(dab.stamp!.height, 4);
      // First row was 1,2,3,4 — mirrored it reads 4,3,2,1.
      expect(dab.stamp!.rgba[0], 4);
      expect(dab.stamp!.rgba[4], 3);
    });

    test('scaling up grows the stamp', () {
      final dab = buildCutStampDab(
        piece: _piece(scalePercent: 200),
        center: CanvasPoint(x: 50, y: 50),
      );
      expect(dab.stamp!.width, greaterThan(4));
      expect(dab.stamp!.height, greaterThan(4));
    });

    test('scaling keeps the drawing two-valued', () {
      // Pick, not Blend: a smoothing kernel would invent the mid-alpha
      // edge pixels that break the fill pass on Japanese line art.
      final dab = buildCutStampDab(
        piece: _piece(scalePercent: 250),
        center: CanvasPoint(x: 50, y: 50),
      );
      final rgba = dab.stamp!.rgba;
      for (var index = 0; index < rgba.length; index += 4) {
        final alpha = rgba[index + 3];
        expect(alpha == 0 || alpha == 255, isTrue, reason: 'alpha $alpha');
      }
    });
  });

  group('the paste-at-origin dab', () {
    test('lands unposed at the cut coordinates', () {
      // The POSE is what "original picture" means, so it is deliberately
      // not applied: a paste at 200% and mirrored would reproduce nothing.
      final dab = buildCutPasteDab(
        _piece(flipHorizontal: true, scalePercent: 200),
      );
      expect(dab.stamp!.width, 4, reason: 'source size, not the posed size');
      // First row unmirrored: 1,2,3,4.
      expect(dab.stamp!.rgba[0], 1);
      expect(dab.center.x, 22, reason: 'origin 20 + half the source width');
      expect(dab.center.y, 32, reason: 'origin 30 + half the source height');
    });

    test('but it DOES take the opacity (유저 2026-08-15)', () {
      // "제자리 붙여넣기도 불투명도 반영하도록." Opacity is not part of the
      // pose — it says how hard the stamp presses, not which picture lands
      // — so grouping it with the flips was the mistake. Asking for nothing
      // still means 100%, which is what "put it back exactly" needs.
      expect(buildCutPasteDab(_piece()).opacity, 1);
      expect(buildCutPasteDab(_piece(), opacity: 0.35).opacity, 0.35);
    });
  });

  group('drag spacing', () {
    test('a drag shorter than the piece lays no extra stamps', () {
      final centers = cutStampCentersAlong(
        piece: _piece(),
        from: CanvasPoint(x: 0, y: 0),
        to: CanvasPoint(x: 2, y: 0),
        spacing: 1,
      );
      expect(centers, isEmpty);
    });

    // 🗣️a-stamp-drag-undoes-a-stamp-at-a-time-Q1 (유저 2026-11-19): 「간격
    // 지금 고정이니까 스탬프 도구설정에 간격설정도 두도록」.
    test('the spacing is a share of the piece — half a piece lays them twice '
        'as close, two pieces half as many — and never under a pixel', () {
      List<double> xs(double spacing) => [
        for (final center in cutStampCentersAlong(
          piece: _piece(),
          from: CanvasPoint(x: 0, y: 0),
          to: CanvasPoint(x: 16, y: 0),
          spacing: spacing,
        ))
          center.x,
      ];
      expect(xs(0.5), [2, 4, 6, 8, 10, 12, 14, 16]);
      expect(xs(2), [8, 16]);
      expect(xs(0.01), hasLength(16), reason: 'one a pixel, not 0.04 px');
    });

    test('at a whole piece, stamps sit one piece apart and never overlap', () {
      // 4px piece, 20px drag → 5 stamps at 4,8,12,16,20.
      final centers = cutStampCentersAlong(
        piece: _piece(),
        from: CanvasPoint(x: 0, y: 0),
        to: CanvasPoint(x: 20, y: 0),
        spacing: 1,
      );
      expect(centers.length, 5);
      expect(centers.first.x, closeTo(4, 0.001));
      expect(centers.last.x, closeTo(20, 0.001));
      for (var i = 1; i < centers.length; i += 1) {
        expect(centers[i].x - centers[i - 1].x, closeTo(4, 0.001));
      }
    });

    // Card a-stamp-drag-drops-its-last-stamp-on-an-exact-step (검증
    // 2026-11-20): ten steps of 35% of a 4 px piece, added one to the
    // next, came to more than the 14 px the hand had gone.
    test('🚨a hand that ends on a step lays that step — at a share no '
        'double holds exactly, and a rounding short of it', () {
      List<double> xs(double end, double spacing) => [
        for (final center in cutStampCentersAlong(
          piece: _piece(),
          from: CanvasPoint(x: 0, y: 0),
          to: CanvasPoint(x: end, y: 0),
          spacing: spacing,
        ))
          center.x,
      ];
      final share = xs(14, 0.35);
      expect(share, hasLength(10));
      expect(share.last, 14);
      expect(share[4], closeTo(7, 1e-9));
      final short = xs(20 - 1e-12, 1);
      expect(short, hasLength(5), reason: 'a point brought onto a row');
      expect(short.last, closeTo(20, 1e-9));
    });

    test('spacing follows the SCALED size, not the source size', () {
      // Otherwise a piece scaled to 200% would stamp over itself.
      final centers = cutStampCentersAlong(
        piece: _piece(scalePercent: 200),
        from: CanvasPoint(x: 0, y: 0),
        to: CanvasPoint(x: 24, y: 0),
        spacing: 1,
      );
      expect(centers.first.x, closeTo(8, 0.001));
    });

    test('a diagonal drag spaces along the diagonal', () {
      final centers = cutStampCentersAlong(
        piece: _piece(),
        from: CanvasPoint(x: 0, y: 0),
        to: CanvasPoint(x: 30, y: 40),
        spacing: 1,
      );
      // Length 50, spacing 4 → 12 stamps.
      expect(centers.length, 12);
      final first = centers.first;
      expect(first.x * first.x + first.y * first.y, closeTo(16, 0.01));
    });
  });
}
