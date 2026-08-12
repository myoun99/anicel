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
    test('never inherits the brush: opacity 1, no pressure ramp', () {
      // 🚨The funnel MULTIPLIES by opacity, so a stamp that took the live
      // brush state would silently carry whatever multiply was left over
      // from shading. This is the assertion that keeps that out.
      final dab = buildCutStampDab(
        piece: _piece(),
        center: CanvasPoint(x: 50, y: 50),
      );
      expect(dab.opacity, 1);
      expect(dab.flow, 1);
      expect(dab.hardness, 1);
      expect(dab.pressure, 1);
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

  group('drag spacing', () {
    test('a drag shorter than the piece lays no extra stamps', () {
      final centers = cutStampCentersAlong(
        piece: _piece(),
        from: CanvasPoint(x: 0, y: 0),
        to: CanvasPoint(x: 2, y: 0),
      );
      expect(centers, isEmpty);
    });

    test('stamps sit one whole piece apart, so they never overlap', () {
      // 4px piece, 20px drag → 5 stamps at 4,8,12,16,20.
      final centers = cutStampCentersAlong(
        piece: _piece(),
        from: CanvasPoint(x: 0, y: 0),
        to: CanvasPoint(x: 20, y: 0),
      );
      expect(centers.length, 5);
      expect(centers.first.x, closeTo(4, 0.001));
      expect(centers.last.x, closeTo(20, 0.001));
      for (var i = 1; i < centers.length; i += 1) {
        expect(centers[i].x - centers[i - 1].x, closeTo(4, 0.001));
      }
    });

    test('spacing follows the SCALED size, not the source size', () {
      // Otherwise a piece scaled to 200% would stamp over itself.
      final centers = cutStampCentersAlong(
        piece: _piece(scalePercent: 200),
        from: CanvasPoint(x: 0, y: 0),
        to: CanvasPoint(x: 24, y: 0),
      );
      expect(centers.first.x, closeTo(8, 0.001));
    });

    test('a diagonal drag spaces along the diagonal', () {
      final centers = cutStampCentersAlong(
        piece: _piece(),
        from: CanvasPoint(x: 0, y: 0),
        to: CanvasPoint(x: 30, y: 40),
      );
      // Length 50, spacing 4 → 12 stamps.
      expect(centers.length, 12);
      final first = centers.first;
      expect(first.x * first.x + first.y * first.y, closeTo(16, 0.01));
    });
  });
}
