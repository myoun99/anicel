// The first stroke compiles the executor and the stroke's kernels: 40 s on
// a machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/services/brush_dab_tip_geometry.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';

/// 🚨H60 (유저 I-86 2026-11-15 「팁이 소재면 aa off하면 소재 팁 그대로인거고
/// 거기서 aa추가하면 추가로 aa 적용되는거고」 · H60-Q2 (a) 「연산은 하나, 자리는
/// 클튜대로」): each step past 없음 smooths a picture tip by a round tip's
/// width, in canvas pixels, about the picture's own contour — its ink as it
/// was, its half-coverage line where it was, its edge softer at every step
/// and as soft each way — on the engine and on the tile kernel alike.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvas = CanvasSize(width: 256, height: 256);
  const steps = [
    BrushAntiAlias.low,
    BrushAntiAlias.medium,
    BrushAntiAlias.high,
  ];

  /// A tip of [side] texels, opaque on the half in the middle each way.
  BrushTipMask blockOf(int side) => BrushTipMask(
    id: 'block $side',
    size: side,
    alpha: Uint8List.fromList([
      for (var y = 0; y < side; y += 1)
        for (var x = 0; x < side; x += 1)
          x >= side ~/ 4 && x < side * 3 ~/ 4 && y >= side ~/ 4 &&
                  y < side * 3 ~/ 4
              ? 255
              : 0,
    ]),
  );
  final block = blockOf(32);

  /// One black dab of [tip] at [step] — at the sizes here a texel a pixel
  /// down, each pixel on a texel's centre: 없음 lays those texels as they
  /// are.
  BrushDab aDab(
    BrushAntiAlias step, {
    BrushTipMask? tip,
    double size = 32,
    double roundness = 1,
  }) => BrushDab(
    center: CanvasPoint(x: 100, y: 100),
    color: 0xFF000000,
    size: size,
    opacity: 1,
    flow: 1,
    hardness: 1,
    pressure: 1,
    sequence: 0,
    tipShape: BrushTipShape.round,
    tipMask: tip ?? block,
    roundness: roundness,
    antiAlias: step,
  );

  /// The alphas [dab] lays, on 0..1, row after row of the canvas's pixels
  /// 60..139 each way, on the engine (a 128 tile) or the tile kernel (any
  /// other).
  List<List<double>> laid(BrushDab dab, {required int tileSize}) {
    final rasterizer = BrushLiveStrokeRasterizer(
      pasteboard: canvas.pasteboardAt(PasteboardReach.whole),
      tileSize: tileSize,
    );
    addTearDown(rasterizer.clear);
    rasterizer.blendFrom([dab], from: 0);
    final bounds = rasterizer.strokeBounds!;
    final pixels = rasterizer.strokePixelsWithinBounds()!;
    final width = bounds.rightExclusive - bounds.left;
    double alphaAt(int x, int y) {
      final (column, row) = (x - bounds.left, y - bounds.top);
      if (column < 0 || row < 0 || column >= width) return 0;
      final at = (row * width + column) * 4 + 3;
      return at < pixels.length ? pixels[at] / 255 : 0;
    }

    return [
      for (var y = 60; y < 140; y += 1)
        [for (var x = 60; x < 140; x += 1) alphaAt(x, y)],
    ];
  }

  /// The row and the column through the dab's centre.
  List<double> rowOf(List<List<double>> alphas) => alphas[40];
  List<double> columnOf(List<List<double>> alphas) => [
    for (final row in alphas) row[40],
  ];

  double ink(List<List<double>> alphas) =>
      alphas.expand((row) => row).fold(0.0, (sum, alpha) => sum + alpha);

  /// How soft [line]'s edges are: what of each pixel is neither in nor out.
  double softness(List<double> line) =>
      line.fold(0.0, (sum, alpha) => sum + alpha * (1 - alpha));

  /// Where [line]'s first edge crosses half coverage — between the two
  /// pixels it falls between.
  double halfLine(List<double> line) {
    for (var x = 1; x < line.length; x += 1) {
      if (line[x - 1] < 0.5 && line[x] >= 0.5) {
        return x - 1 + (0.5 - line[x - 1]) / (line[x] - line[x - 1]);
      }
    }
    throw StateError('no half line');
  }

  for (final (where, tileSize) in [
    ('the engine', 128),
    ('the tile kernel', 64),
  ]) {
    test('on $where each step lays the picture softer, its ink and its '
        'half line as 없음 lays them', () {
      final none = laid(aDab(BrushAntiAlias.none), tileSize: tileSize);
      expect(
        softness(rowOf(none)),
        0,
        reason: 'premise: the texels as they are',
      );
      var softer = 0.0;
      for (final step in steps) {
        final alphas = laid(aDab(step), tileSize: tileSize);
        expect(softness(rowOf(alphas)), greaterThan(softer), reason: '$step');
        softer = softness(rowOf(alphas));
        expect(
          ink(alphas),
          closeTo(ink(none), ink(none) * 0.01),
          reason: '$step: about its contour, as far out as in',
        );
        expect(
          halfLine(rowOf(alphas)),
          closeTo(halfLine(rowOf(none)), 0.1),
          reason: '$step',
        );
      }
    });

    test('on $where a step smooths a picture as much down as across', () {
      for (final step in steps) {
        final alphas = laid(aDab(step), tileSize: tileSize);
        final (row, column) = (rowOf(alphas), columnOf(alphas));
        for (var at = 0; at < row.length; at += 1) {
          expect(
            column[at],
            closeTo(row[at], 1.5 / 255),
            reason: '$step at $at',
          );
        }
      }
    });

    test('on $where a squeezed picture is smoothed by the same canvas width '
        'down its minor axis', () {
      // Two tips a texel a pixel down at one radius: one pressed to half
      // its height, one twice its texels drawn whole. The first is laid
      // whole first: the same width across, another down.
      for (final step in steps) {
        laid(aDab(step, size: 64), tileSize: tileSize);
        final squeezed = laid(
          aDab(step, size: 64, roundness: 0.5),
          tileSize: tileSize,
        );
        final whole = laid(
          aDab(step, tip: blockOf(64), size: 64),
          tileSize: tileSize,
        );
        final soft = softness(columnOf(whole));
        expect(soft, greaterThan(0), reason: 'premise: $step smooths it');
        expect(
          softness(columnOf(squeezed)),
          closeTo(soft, soft * 0.02),
          reason: '$step',
        );
      }
    });
  }

  test('the engine and the tile kernel lay a step\'s picture alike', () {
    for (final step in BrushAntiAlias.values) {
      final engine = laid(aDab(step), tileSize: 128);
      final kernel = laid(aDab(step), tileSize: 64);
      for (var y = 0; y < engine.length; y += 1) {
        for (var x = 0; x < engine[y].length; x += 1) {
          expect(
            engine[y][x],
            closeTo(kernel[y][x], 1.5 / 255),
            reason: '$step at (${x + 60}, ${y + 60})',
          );
        }
      }
    }
  });

  test('없음 reads the picture itself, and a step one smoothing of it for '
      'every dab that asks it', () {
    final none = brushDabTipGeometry(aDab(BrushAntiAlias.none)).tipMask;
    expect(none, same(block));
    final high = brushDabTipGeometry(aDab(BrushAntiAlias.high)).tipMask;
    expect(high, isNot(same(block)));
    expect(
      brushDabTipGeometry(aDab(BrushAntiAlias.high)).tipMask,
      same(high),
      reason: 'one texture for the engine to keep',
    );
  });
}
