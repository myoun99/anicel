import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/fill_gradient.dart';

/// I-160: a held range laid under a gradient — its colours, its two shapes
/// (Q4 「직선 + 원형」) and its two ends (Q3 「메인 → 서브」 · 「메인 → 투명」,
/// 「반전」), pixel by pixel as the stamp carries them.
void main() {
  FillGradient gradient(
    FillGradientShape shape, {
    required CanvasPoint from,
    required CanvasPoint to,
    int start = 0xFF000000,
    int end = 0xFFFFFFFF,
  }) => FillGradient(
    shape: shape,
    from: from,
    to: to,
    startColor: start,
    endColor: end,
  );

  group('where a point lies along it', () {
    test('a line: the projection, held to its two ends', () {
      final line = gradient(
        FillGradientShape.linear,
        from: CanvasPoint(x: 0, y: 0),
        to: CanvasPoint(x: 10, y: 0),
      );
      expect(line.at(0, 0), 0);
      expect(line.at(5, 3), 0.5, reason: 'across the line, the same');
      expect(line.at(-4, 0), 0, reason: 'behind the start: the start');
      expect(line.at(20, 9), 1, reason: 'past the end: the end');
    });

    test('a circle: the distance over the radius, the end beyond it', () {
      final circle = gradient(
        FillGradientShape.radial,
        from: CanvasPoint(x: 0, y: 0),
        to: CanvasPoint(x: 10, y: 0),
      );
      expect(circle.at(0, 6), closeTo(0.6, 1e-9));
      expect(circle.at(-6, 0), closeTo(0.6, 1e-9), reason: 'any way round');
      expect(circle.at(8, 6), 1);
      expect(circle.at(30, 0), 1);
    });

    test('🚨I-160-Q5: a press that never moved lays the start colour, '
        'whatever the shape', () {
      for (final shape in FillGradientShape.values) {
        final still = gradient(
          shape,
          from: CanvasPoint(x: 4, y: 4),
          to: CanvasPoint(x: 4, y: 4),
        );
        expect(still.at(4, 4), 0, reason: '$shape');
        expect(still.at(40, -9), 0, reason: '$shape');
      }
    });
  });

  test('the colour between: each straight channel, rounded', () {
    final ramp = gradient(
      FillGradientShape.linear,
      from: CanvasPoint(x: 0, y: 0),
      to: CanvasPoint(x: 1, y: 0),
      start: 0xFF102030,
      end: 0x00F0E0D0,
    );
    expect(ramp.colorAt(0), 0xFF102030);
    expect(ramp.colorAt(1), 0x00F0E0D0);
    expect(ramp.colorAt(0.5), 0x80808080);
    expect(ramp.stops(3), [0xFF102030, 0x80808080, 0x00F0E0D0]);
  });

  group('I-160-Q3: the two ends and the swap', () {
    final from = CanvasPoint(x: 0, y: 0);
    final to = CanvasPoint(x: 9, y: 0);
    const main = 0xFFCC3311;
    const sub = 0xFF22AA44;

    test('main to sub', () {
      final laid = const FillGradientOptions(
        enabled: true,
      ).between(from, to, main: main, sub: sub);
      expect((laid.startColor, laid.endColor), (main, sub));
      expect((laid.from, laid.to), (from, to));
    });

    test('main to clear — the main colour at no alpha, not black', () {
      final laid = const FillGradientOptions(
        enabled: true,
        end: FillGradientEnd.transparent,
      ).between(from, to, main: main, sub: sub);
      expect((laid.startColor, laid.endColor), (main, 0x00CC3311));
    });

    test('reversed: the same two, the other way', () {
      for (final end in FillGradientEnd.values) {
        final ahead = FillGradientOptions(
          enabled: true,
          end: end,
        ).between(from, to, main: main, sub: sub);
        final back = FillGradientOptions(
          enabled: true,
          end: end,
          reversed: true,
        ).between(from, to, main: main, sub: sub);
        expect(
          (back.startColor, back.endColor),
          (ahead.endColor, ahead.startColor),
          reason: '$end',
        );
      }
    });

    test('the shape is the one in hand', () {
      final laid = const FillGradientOptions(
        enabled: true,
        shape: FillGradientShape.radial,
      ).between(from, to, main: main, sub: sub);
      expect(laid.shape, FillGradientShape.radial);
    });
  });

  group('a range laid under it', () {
    FillRange row(List<int> coverage, {int left = 0, int top = 0}) =>
        FillRange.over(
          FloodFillRegion(
            left: left,
            top: top,
            width: coverage.length,
            height: 1,
            mask: Uint8List.fromList(coverage),
          ),
        );

    List<int> pixels(Iterable<BrushDab> pieces) {
      final stamp = pieces.single.stamp!;
      return [
        for (var i = 0; i < stamp.width * stamp.height; i += 1)
          stamp.rgba[i * 4] << 24 |
              stamp.rgba[i * 4 + 1] << 16 |
              stamp.rgba[i * 4 + 2] << 8 |
              stamp.rgba[i * 4 + 3],
      ];
    }

    test('each pixel the colour at its centre', () {
      final laid = row([255, 255, 255, 255], left: 20).piecesUnder(
        gradient(
          FillGradientShape.linear,
          from: CanvasPoint(x: 20.5, y: 0.5),
          to: CanvasPoint(x: 23.5, y: 0.5),
        ),
      );
      expect(pixels(laid), [
        0x000000FF,
        0x555555FF,
        0xAAAAAAFF,
        0xFFFFFFFF,
      ], reason: 'r g b a: a third, two thirds');
    });

    test('the halfway pixel the halfway colour — the table spans the ramp',
        () {
      final laid = row([255, 255, 255]).piecesUnder(
        gradient(
          FillGradientShape.linear,
          from: CanvasPoint(x: 0.5, y: 0.5),
          to: CanvasPoint(x: 2.5, y: 0.5),
        ),
      );
      expect(pixels(laid), [0x000000FF, 0x808080FF, 0xFFFFFFFF]);
    });

    test('its alpha under the coverage — a soft edge stays soft', () {
      final laid = row([255, 128, 0]).piecesUnder(
        gradient(
          FillGradientShape.linear,
          from: CanvasPoint(x: 0, y: 0),
          to: CanvasPoint(x: 0, y: 0),
          start: 0x80336699,
        ),
      );
      expect(pixels(laid), [0x33669980, 0x33669940, 0x00000000]);
    });

    test('pieces made afresh at each ask — a shape area asks again', () {
      final range = row([255, 255]);
      final under = gradient(
        FillGradientShape.radial,
        from: CanvasPoint(x: 0, y: 0),
        to: CanvasPoint(x: 4, y: 0),
      );
      expect(pixels(range.piecesUnder(under)),
          pixels(range.piecesUnder(under)));
    });
  });
}
