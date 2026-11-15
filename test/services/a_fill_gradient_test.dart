import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuMask;
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/native/engine_stamp_pictures.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/fill_gradient.dart';

import '../helpers/engine_pixels.dart';
import '../helpers/fill_pieces.dart';

/// I-160: a held range laid under a gradient — its colours, its two shapes
/// (Q4 「직선 + 원형」) and its two ends (Q3 「메인 → 서브」 · 「메인 → 투명」,
/// 「반전」), pixel by pixel as the engine paints them. Where a pixel's
/// centre lies along a gradient, and each stop's colour, are the engine's
/// alone (rust/src/kernels/dab/stamp_tests.rs): here, that the fill hands
/// it the gradient in hand.
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
    FillRange rows(List<List<int>> coverage, {int left = 0, int top = 0}) =>
        FillRange.over(
          FloodFillRegion(
            left: left,
            top: top,
            width: coverage.first.length,
            height: coverage.length,
            mask: Uint8List.fromList([for (final row in coverage) ...row]),
          ),
        );

    /// What [pieces] lay over [width] × [height] from ([left], [top]), as
    /// the engine paints them: a pixel's straight RGBA, R in the high byte.
    List<int> pixels(
      Iterable<BrushDab> pieces, {
      required int width,
      int height = 1,
      int left = 0,
      int top = 0,
    }) {
      final laid = pieces.toList();
      return [
        for (var y = top; y < top + height; y += 1)
          for (var x = left; x < left + width; x += 1)
            piecesRgbaAt(laid, x, y).fold(0, (word, byte) => word << 8 | byte),
      ];
    }

    test('each pixel the colour at its centre', () {
      final laid = rows([
        [255, 255, 255, 255],
      ], left: 20).piecesUnder(
        gradient(
          FillGradientShape.linear,
          from: CanvasPoint(x: 20.5, y: 0.5),
          to: CanvasPoint(x: 23.5, y: 0.5),
        ),
      );
      expect(pixels(laid, left: 20, width: 4), [
        0x000000FF,
        0x555555FF,
        0xAAAAAAFF,
        0xFFFFFFFF,
      ], reason: 'r g b a: a third, two thirds');
    });

    test('the halfway pixel the halfway colour — the table spans the ramp',
        () {
      final laid = rows([
        [255, 255, 255],
      ]).piecesUnder(
        gradient(
          FillGradientShape.linear,
          from: CanvasPoint(x: 0.5, y: 0.5),
          to: CanvasPoint(x: 2.5, y: 0.5),
        ),
      );
      expect(pixels(laid, width: 3), [0x000000FF, 0x808080FF, 0xFFFFFFFF]);
    });

    test('Q4: a line lays the same across it, a circle by the distance', () {
      final range = rows([
        [255],
        [255],
      ]);
      List<int> under(FillGradientShape shape) => pixels(
        range.piecesUnder(
          gradient(
            shape,
            from: CanvasPoint(x: 0.5, y: 0.5),
            to: CanvasPoint(x: 3.5, y: 0.5),
          ),
        ),
        width: 1,
        height: 2,
      );
      expect(
        under(FillGradientShape.linear),
        [0x000000FF, 0x000000FF],
        reason: 'below the start of a line: its start',
      );
      expect(
        under(FillGradientShape.radial),
        [0x000000FF, 0x555555FF],
        reason: 'a pixel below the centre of a circle: a third of its radius',
      );
    });

    test('its alpha under the coverage — a soft edge stays soft', () {
      final laid = rows([
        [255, 128, 0],
      ]).piecesUnder(
        gradient(
          FillGradientShape.linear,
          from: CanvasPoint(x: 0, y: 0),
          to: CanvasPoint(x: 0, y: 0),
          start: 0x80336699,
        ),
      );
      Uint8List bytesOf(List<int> words) => Uint8List.fromList([
        for (final word in words)
          for (final shift in [24, 16, 8, 0]) word >> shift & 0xFF,
      ]);
      expectSamePixels(
        bytesOf([0x33669980, 0x33669940, 0x00000000]),
        bytesOf(pixels(laid, width: 3)),
      );
    });

    test('a range dragged under new ends moves its coverage to the engine '
        'once — a frame is the gradient\'s ends, not the range', () {
      final range = rows([
        [255, 255],
      ]);
      GpuMask coverageOf(Iterable<BrushDab> pieces) =>
          EngineStampPictures.madeOfMask(pieces.single.stamp!)!.coverage();
      final first = coverageOf(
        range.piecesUnder(
          gradient(
            FillGradientShape.radial,
            from: CanvasPoint(x: 0, y: 0),
            to: CanvasPoint(x: 4, y: 0),
          ),
        ),
      );
      final next = coverageOf(
        range.piecesUnder(
          gradient(
            FillGradientShape.linear,
            from: CanvasPoint(x: 1, y: 0),
            to: CanvasPoint(x: 2, y: 0),
          ),
        ),
      );
      expect(identical(first, next), isTrue);
      expect(identical(first, coverageOf(range.dabsIn(0xFF336699))), isTrue);
    });
  });
}
