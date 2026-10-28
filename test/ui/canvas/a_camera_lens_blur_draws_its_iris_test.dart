@Tags(['impeller'])
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/core/draw_space.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/services/camera_lens_blur_passes.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';
import 'package:anicel/src/services/shaded_passes.dart';
import 'package:anicel/src/ui/canvas/iris_blur_shader.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';

/// 🗣️I-132-Q3 (유저 2026-10-27): AE's Camera Lens Blur; 🗣️I-132-Q15 a
/// (10-28): 「모든 모양을 정확히 — 행 누적합」 — every pixel the mean of the
/// pixels about it its iris covers, read out of row sums laid in floats.
///
/// The truth is the mean worked out on the CPU, pixel by pixel, over the
/// pixels the iris covers ([irisSpans], held exact by
/// `an_iris_covers_its_shape_test`). ⛔ON IMPELLER: a row sum runs past 1,
/// and Skia rasters a float target as bytes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(IrisBlurShader.load);

  ResolvedLayerEffect lens({
    required double radius,
    int shape = 3,
    double roundness = 0,
    double aspect = 1,
    double rotation = 0,
    double fringe = 0,
    bool repeats = false,
  }) => ResolvedLayerEffect(
    kind: EffectKind.cameraLensBlur,
    values: [
      radius,
      shape.toDouble(),
      roundness,
      aspect,
      rotation,
      fringe,
      if (repeats) 1 else 0,
    ],
  );

  /// The iris [effect] gathers over a raster [width] wide.
  IrisGatherPass irisOf(ResolvedLayerEffect effect, int width, Rect paper) =>
      shadedPassesOf(
            effect,
            DrawSpace.canvas,
            paper: paper,
            rasterWidth: width,
          ).last
          as IrisGatherPass;

  Future<ui.Image> imageOf(
    WidgetTester tester,
    Uint8List rgba,
    int width,
    int height,
  ) async {
    final image = (await tester.runAsync(() async {
      final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      return (await codec.getNextFrame()).image;
    }))!;
    addTearDown(image.dispose);
    return image;
  }

  Future<Uint8List> bytesOf(WidgetTester tester, ui.Image image) async =>
      (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!.buffer.asUint8List();

  /// [source] through [effect] on the chain's own road, [paper] where the
  /// paper lies on it.
  Future<Uint8List> blurred(
    WidgetTester tester,
    ui.Image source,
    ResolvedLayerEffect effect, {
    Rect? paper,
  }) async {
    final whole = Rect.fromLTWH(
      0,
      0,
      source.width.toDouble(),
      source.height.toDouble(),
    );
    final on = paper ?? whole;
    final out = steppedForChain(
      image: source,
      plan: resolveCompositeEffectPlan([effect], paper: on),
      extent: whole,
      paper: on,
    );
    if (!identical(out, source)) {
      addTearDown(out.dispose);
    }
    return bytesOf(tester, out);
  }

  /// The mean [iris] makes of [input], a [width] wide raster, worked out
  /// pixel by pixel: past the raster nothing, or — where the iris repeats
  /// the paper's edge — the paper's edge pixel, and nothing drawn off it.
  List<double> truth(Uint8List input, int width, IrisGatherPass iris) {
    final height = input.length ~/ (4 * width);
    final paper = iris.paper;
    final (left, top, right, bottom) = paper == null
        ? (0, 0, width - 1, height - 1)
        : (
            math.max(paper.left.toInt(), 0),
            math.max(paper.top.toInt(), 0),
            math.min(paper.right.toInt(), width) - 1,
            math.min(paper.bottom.toInt(), height) - 1,
          );
    final out = List<double>.filled(input.length, 0);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        if (paper != null &&
            (x < left || x > right || y < top || y > bottom)) {
          continue;
        }
        for (var c = 0; c < 4; c += 1) {
          var sum = 0.0;
          void add(List<IrisSpan> rows, double weight) {
            for (var row = 0; row < rows.length; row += 1) {
              for (var dx = rows[row].left; dx <= rows[row].right; dx += 1) {
                var (u, v) = (x + dx, y + row - iris.reach);
                if (paper != null) {
                  (u, v) = (u.clamp(left, right), v.clamp(top, bottom));
                } else if (u < 0 || v < 0 || u >= width || v >= height) {
                  continue;
                }
                sum += input[(v * width + u) * 4 + c] * weight;
              }
            }
          }

          add(iris.outline, 1);
          if (iris.fringe > 0) {
            add(iris.core, -iris.fringe);
          }
          out[(y * width + x) * 4 + c] = sum / iris.weight;
        }
      }
    }
    return out;
  }

  void expectWithinOne(Uint8List got, List<double> want, {String? reason}) {
    var worst = 0.0;
    var at = -1;
    for (var i = 0; i < got.length; i += 1) {
      final off = (got[i] - want[i]).abs();
      if (off > worst) {
        (worst, at) = (off, i);
      }
    }
    expect(worst, lessThanOrEqualTo(1), reason: '${reason ?? ''} at $at');
  }

  /// A white dot at ([x], [y]) on a clear picture [width] × [height].
  Uint8List dotPicture(int width, int height, int x, int y) {
    final at = (y * width + x) * 4;
    return Uint8List(width * height * 4)..fillRange(at, at + 4, 255);
  }

  Uint8List randomPicture(int width, int height, {int seed = 7}) {
    final random = math.Random(seed);
    final bytes = Uint8List(width * height * 4);
    for (var i = 0; i < bytes.length; i += 4) {
      // Premultiplied, as a raster is: no channel past its alpha.
      final alpha = random.nextInt(256);
      for (var c = 0; c < 3; c += 1) {
        bytes[i + c] = random.nextInt(alpha + 1);
      }
      bytes[i + 3] = alpha;
    }
    return bytes;
  }

  testWidgets('a dot becomes its iris, turned about it', (tester) async {
    final (width, height, dotX, dotY) = (80, 60, 40, 30);
    final source = await imageOf(
      tester,
      dotPicture(width, height, dotX, dotY),
      width,
      height,
    );
    final effect = lens(
      radius: 9,
      roundness: 30,
      aspect: 1.4,
      rotation: 25,
    );
    final got = await blurred(tester, source, effect);
    final iris = irisOf(effect, width, const Rect.fromLTWH(0, 0, 80, 60));

    // A pixel reads the dot where the dot lies in its iris: the iris
    // turned a half turn about the dot.
    final lit = <(int, int)>{
      for (final (row, span) in iris.outline.indexed)
        for (var dx = span.left; dx <= span.right; dx += 1)
          (dotX - dx, dotY - (row - iris.reach)),
    };
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final alpha = got[(y * width + x) * 4 + 3];
        expect(
          alpha,
          lit.contains((x, y))
              ? closeTo(255 / iris.weight, 1)
              : 0,
          reason: '($x, $y)',
        );
      }
    }
    expect(lit.length, iris.weight, reason: 'every pixel it covers, once');
  });

  testWidgets('a picture blurs to the mean of each iris, pixel for pixel — '
      'its rows summed in two passes', (tester) async {
    final (width, height) = (150, 40);
    final bytes = randomPicture(width, height);
    final source = await imageOf(tester, bytes, width, height);
    final input = await bytesOf(tester, source);
    for (final effect in [
      lens(radius: 7.5, shape: 0, roundness: 0, rotation: 40),
      lens(radius: 11, shape: 5, roundness: 60, aspect: 0.4, rotation: -70),
      lens(radius: 6, shape: 3, roundness: 100),
    ]) {
      final paper = Rect.fromLTWH(0, 0, width * 1.0, height * 1.0);
      expect(
        shadedPassesOf(
          effect,
          DrawSpace.canvas,
          paper: paper,
          rasterWidth: width,
        ).whereType<RowSumPass>(),
        hasLength(2),
        reason: 'fixture: 150 wide is two passes of sums',
      );
      expectWithinOne(
        await blurred(tester, source, effect),
        truth(input, width, irisOf(effect, width, paper)),
        reason: '$effect',
      );
    }
  });

  testWidgets('Repeat Edge Pixels reads the paper\'s edge past it, and draws '
      'on the paper alone', (tester) async {
    final (width, height) = (120, 50);
    final bytes = randomPicture(width, height, seed: 11);
    final source = await imageOf(tester, bytes, width, height);
    final input = await bytesOf(tester, source);
    const paper = Rect.fromLTWH(20.4, 9.6, 70, 30);
    final effect = lens(radius: 8, shape: 1, roundness: 20, repeats: true);
    final iris = irisOf(effect, width, paper);

    expect(iris.paper, const Rect.fromLTRB(20, 10, 90, 40), reason: 'whole');
    final got = await blurred(tester, source, effect, paper: paper);
    expectWithinOne(got, truth(input, width, iris));
  });

  testWidgets('a fringe of 500 pushes all the light out to the iris\'s '
      'edge', (tester) async {
    final (width, height, dotX, dotY) = (60, 60, 30, 30);
    final source = await imageOf(
      tester,
      dotPicture(width, height, dotX, dotY),
      width,
      height,
    );
    final effect = lens(radius: 12, shape: 5, fringe: 500);
    final got = await blurred(tester, source, effect);

    expect(got[(dotY * width + dotX) * 4 + 3], 0, reason: 'the core is dark');
    final iris = irisOf(effect, width, const Rect.fromLTWH(0, 0, 60, 60));
    final edge = iris.outline[iris.reach];
    expect(
      got[(dotY * width + dotX - edge.left) * 4 + 3],
      closeTo(255 / iris.weight, 1),
      reason: 'the ring is lit',
    );
  });

  testWidgets('a raster past 4096 wide sums its rows in three passes', (
    tester,
  ) async {
    final (width, height) = (4100, 3);
    final bytes = randomPicture(width, height, seed: 3);
    final source = await imageOf(tester, bytes, width, height);
    final input = await bytesOf(tester, source);
    final effect = lens(radius: 1.5);
    const paper = Rect.fromLTWH(0, 0, 4100, 3);

    expect(
      shadedPassesOf(
        effect,
        DrawSpace.canvas,
        paper: paper,
        rasterWidth: width,
      ).whereType<RowSumPass>(),
      hasLength(3),
    );
    expectWithinOne(
      await blurred(tester, source, effect),
      truth(input, width, irisOf(effect, width, paper)),
    );
  });

  group('the plan', () {
    const paper = Rect.fromLTWH(0, 0, 64, 64);

    test('no radius is no step, whatever the iris', () {
      final plan = resolveCompositeEffectPlan([
        lens(radius: 0, shape: 0, roundness: 50, fringe: 300),
      ], paper: paper);
      expect(plan.isSingleDraw, isTrue);
      expect(plan.finalPaint.isEmpty, isTrue);
    });

    test('it reaches its radius past its input', () {
      expect(
        resolveCompositeEffectPlan([lens(radius: 37.5)], paper: paper)
            .outsetPixels,
        37.5,
      );
    });
  });
}
