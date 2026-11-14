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
/// width, about the picture's own contour — its ink as it was, its
/// half-coverage line where it was, its edge softer at every step — on the
/// engine and on the tile kernel alike.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvas = CanvasSize(width: 256, height: 256);

  /// A tip of 32 texels, opaque on the 16 in the middle each way.
  final block = BrushTipMask(
    id: 'block',
    size: 32,
    alpha: Uint8List.fromList([
      for (var y = 0; y < 32; y += 1)
        for (var x = 0; x < 32; x += 1)
          x >= 8 && x < 24 && y >= 8 && y < 24 ? 255 : 0,
    ]),
  );

  /// One black dab of [block] at [step], a texel a pixel and each pixel on
  /// a texel's centre — 없음 lays the texels as they are.
  BrushDab aDab(BrushAntiAlias step) => BrushDab(
    center: CanvasPoint(x: 100, y: 100),
    color: 0xFF000000,
    size: 32,
    opacity: 1,
    flow: 1,
    hardness: 1,
    pressure: 1,
    sequence: 0,
    tipShape: BrushTipShape.round,
    tipMask: block,
    antiAlias: step,
  );

  /// The alphas [step]'s dab lays, on 0..1, row after row of the canvas's
  /// pixels 80..119 each way, on the engine (a 128 tile) or the tile
  /// kernel (any other).
  List<List<double>> laid(BrushAntiAlias step, {required int tileSize}) {
    final rasterizer = BrushLiveStrokeRasterizer(
      pasteboard: canvas.pasteboardAt(PasteboardReach.whole),
      tileSize: tileSize,
    );
    addTearDown(rasterizer.clear);
    rasterizer.blendFrom([aDab(step)], from: 0);
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
      for (var y = 80; y < 120; y += 1)
        [for (var x = 80; x < 120; x += 1) alphaAt(x, y)],
    ];
  }

  double ink(List<List<double>> alphas) =>
      alphas.expand((row) => row).fold(0.0, (sum, alpha) => sum + alpha);

  /// How soft the edge is: what of each pixel is neither in nor out.
  double softness(List<List<double>> alphas) => alphas
      .expand((row) => row)
      .fold(0.0, (sum, alpha) => sum + alpha * (1 - alpha));

  /// Where, along the middle row, the left edge crosses half coverage —
  /// between the two pixels it falls between.
  double halfLine(List<List<double>> alphas) {
    final row = alphas[20];
    for (var x = 1; x < row.length; x += 1) {
      if (row[x - 1] < 0.5 && row[x] >= 0.5) {
        return x - 1 + (0.5 - row[x - 1]) / (row[x] - row[x - 1]);
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
      final none = laid(BrushAntiAlias.none, tileSize: tileSize);
      expect(softness(none), 0, reason: 'premise: the texels as they are');
      var softer = 0.0;
      for (final step in [
        BrushAntiAlias.low,
        BrushAntiAlias.medium,
        BrushAntiAlias.high,
      ]) {
        final alphas = laid(step, tileSize: tileSize);
        expect(softness(alphas), greaterThan(softer), reason: '$step');
        softer = softness(alphas);
        expect(
          ink(alphas),
          closeTo(ink(none), ink(none) * 0.01),
          reason: '$step: about its contour, as far out as in',
        );
        expect(
          halfLine(alphas),
          closeTo(halfLine(none), 0.1),
          reason: '$step',
        );
      }
    });
  }

  test('the engine and the tile kernel lay a step\'s picture alike', () {
    for (final step in BrushAntiAlias.values) {
      final engine = laid(step, tileSize: 128);
      final kernel = laid(step, tileSize: 64);
      for (var y = 0; y < engine.length; y += 1) {
        for (var x = 0; x < engine[y].length; x += 1) {
          expect(
            engine[y][x],
            closeTo(kernel[y][x], 1.5 / 255),
            reason: '$step at (${x + 80}, ${y + 80})',
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
