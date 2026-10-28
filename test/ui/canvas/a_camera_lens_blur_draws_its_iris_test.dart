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
import 'package:anicel/src/ui/canvas/raster_picture.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';

import '../../helpers/iris_truth.dart';

/// 🗣️I-132-Q3 (유저 2026-10-27): AE's Camera Lens Blur; 🗣️I-132-Q15 a
/// (10-28): 「모든 모양을 정확히 — 행 누적합」 — every pixel the mean of the
/// pixels about it its iris covers, read out of row sums laid in floats.
///
/// The truth is the mean worked out on the CPU, pixel by pixel, over the
/// pixels the iris's table lays ([irisLaidCoverOf] — the table held to the
/// shape by `an_iris_table_covers_its_shape_test`), at each pixel's level
/// where a blur map names it — of the light each gives where the blur
/// reads it through its Highlight and Use Linear Working Space
/// ([LensLight]). ⛔ON IMPELLER: a row sum runs past 1, and Skia rasters a
/// float target as bytes.
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
    double gain = 0,
    double threshold = 255,
    double saturation = 0,
    bool repeats = false,
    bool linear = false,
  }) => ResolvedLayerEffect(
    kind: EffectKind.cameraLensBlur,
    values: [
      radius,
      shape.toDouble(),
      roundness,
      aspect,
      rotation,
      fringe,
      gain,
      threshold,
      saturation,
      if (repeats) 1 else 0,
      if (linear) 1 else 0,
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

  double linearOf(double stored) => stored < 0.04045
      ? stored / 12.92
      : math.pow((stored + 0.055) / 1.055, 2.4).toDouble();

  double storedOf(double linear) {
    final light = math.max(linear, 0.0);
    return light < 0.0031308
        ? light * 12.92
        : 1.055 * math.pow(light, 1 / 2.4) - 0.055;
  }

  /// A premultiplied [pixel] (0…1) as the sums read it through [light]:
  /// `lens_light.glsl`'s `lit`, worked out on the CPU.
  List<double> litOf(List<double> pixel, LensLight light) {
    final alpha = pixel[3];
    var colour = [
      for (var c = 0; c < 3; c += 1)
        if (alpha > 0) pixel[c] / alpha else 0.0,
    ];
    if (light.linear) {
      colour = [for (final c in colour) linearOf(c)];
    }
    final luma = 0.2126 * colour[0] + 0.7152 * colour[1] + 0.0722 * colour[2];
    final boost = luma * light.gain * math.max(luma - light.threshold, 0);
    return [
      for (final c in colour)
        (c + boost * (1 + (c / math.max(luma, 1e-6) - 1) * light.saturation)) *
            alpha,
      alpha,
    ];
  }

  /// What the iris gathered, [mean], put back as stored: its `stored`.
  List<double> storedPixelOf(List<double> mean, LensLight light) {
    final rgb = [for (var c = 0; c < 3; c += 1) math.max(mean[c], 0.0)];
    final alpha = math.max(mean[3], rgb.reduce(math.max)).clamp(0.0, 1.0);
    return [
      for (final c in rgb)
        (alpha > 0 ? (light.linear ? storedOf(c / alpha) : c / alpha) : 0.0)
                .clamp(0.0, 1.0) *
            alpha,
      alpha,
    ];
  }

  /// The level of its table [iris] blurs pixel [pixel] at: the first, or —
  /// where it reads a blur map ([IrisGatherPass.map]) — the one [map]'s
  /// value there names through its channel.
  int levelAt(IrisGatherPass iris, Uint8List? map, int pixel) {
    final named = iris.map;
    if (named == null) {
      return 0;
    }
    final IrisMapChannel(:r, :g, :b, :a) = named.channel;
    final at = pixel * 4;
    final value =
        r * map![at] + g * map[at + 1] + b * map[at + 2] + a * map[at + 3];
    return value.round().clamp(0, 255);
  }

  /// The mean [iris] makes of [input], a [width] wide raster, worked out
  /// pixel by pixel over the rows its table lays, each at its own level
  /// ([levelAt]) where [map] names it: past the raster nothing, or — where
  /// the iris repeats the paper's edge — the paper's edge pixel, and
  /// nothing drawn off it; every pixel read through the iris's light, and
  /// put back as stored.
  Future<List<double>> truth(
    WidgetTester tester,
    Uint8List input,
    int width,
    IrisGatherPass iris, {
    Uint8List? map,
  }) async {
    final table = await irisTableOf(tester, iris);
    final height = input.length ~/ (4 * width);
    final paper = iris.paper;
    final light = iris.light;
    final covers = <int, IrisCover>{};
    final pixels = [
      for (var i = 0; i < input.length; i += 4)
        [for (var c = 0; c < 4; c += 1) input[i + c] / 255],
    ];
    final read = light == null
        ? pixels
        : [for (final pixel in pixels) litOf(pixel, light)];
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
        final level = levelAt(iris, map, y * width + x);
        final cover = covers.putIfAbsent(
          level,
          () => irisLaidCoverOf(table, iris, level: level),
        );
        final sum = List<double>.filled(4, 0);
        void add(List<IrisRow> rows, double weight) {
          for (var row = 0; row < rows.length; row += 1) {
            var (left: from, right: to) = rows[row];
            if (paper == null) {
              // Past the raster nothing: only the columns on it.
              final v = y + row - cover.reach;
              if (v < 0 || v >= height) {
                continue;
              }
              (from, to) = (math.max(from, -x), math.min(to, width - 1 - x));
            }
            for (var dx = from; dx <= to; dx += 1) {
              var (u, v) = (x + dx, y + row - cover.reach);
              if (paper != null) {
                (u, v) = (u.clamp(left, right), v.clamp(top, bottom));
              } else if (u < 0 || v < 0 || u >= width || v >= height) {
                continue;
              }
              for (var c = 0; c < 4; c += 1) {
                sum[c] += read[v * width + u][c] * weight;
              }
            }
          }
        }

        add(cover.outline, 1);
        add(cover.core, -cover.pushed);
        final mean = cover.weight > 0
            ? [for (final each in sum) each / cover.weight]
            : read[y * width + x];
        final pixel = light == null ? mean : storedPixelOf(mean, light);
        for (var c = 0; c < 4; c += 1) {
          out[(y * width + x) * 4 + c] = pixel[c] * 255;
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

  /// The pixels that read a dot at ([dotX], [dotY]) through [cover]: those
  /// whose iris holds the dot — the iris turned a half turn about it.
  Set<(int, int)> litBy(IrisCover cover, int dotX, int dotY) => {
    for (final (row, span) in cover.outline.indexed)
      for (var dx = span.left; dx <= span.right; dx += 1)
        (dotX - dx, dotY - (row - cover.reach)),
  };

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
    final cover = irisLaidCoverOf(await irisTableOf(tester, iris), iris);

    final lit = litBy(cover, dotX, dotY);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final alpha = got[(y * width + x) * 4 + 3];
        expect(
          alpha,
          lit.contains((x, y)) ? closeTo(255 / cover.weight, 1) : 0,
          reason: '($x, $y)',
        );
      }
    }
    expect(lit.length, cover.weight, reason: 'every pixel it covers, once');
  });

  testWidgets('a fringe with no edge to push the light out to leaves it '
      'where it is: an iris whose core covers all it does blurs as one with '
      'none', (tester) async {
    final (width, height, dotX, dotY) = (9, 9, 4, 4);
    final source = await imageOf(
      tester,
      dotPicture(width, height, dotX, dotY),
      width,
      height,
    );
    final pushing = lens(radius: 1.3, roundness: 100, fringe: 500);
    final iris = irisOf(pushing, width, const Rect.fromLTWH(0, 0, 9, 9));
    final cover = irisLaidCoverOf(await irisTableOf(tester, iris), iris);
    expect(
      (coveredBy(cover.outline), coveredBy(cover.core)),
      (5, 5),
      reason: 'fixture: its core covers all its outline does',
    );
    final got = await blurred(tester, source, pushing);
    expect(got[(dotY * width + dotX) * 4 + 3], closeTo(255 / 5, 1));
    expect(
      got,
      await blurred(tester, source, lens(radius: 1.3, roundness: 100)),
    );
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
        await truth(tester, input, width, irisOf(effect, width, paper)),
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
    // As stored, and through a light: the edge pixels are read as the sums
    // read every other.
    for (final effect in [
      lens(radius: 8, shape: 1, roundness: 20, repeats: true),
      lens(radius: 8, shape: 1, gain: 50, threshold: 120, repeats: true),
    ]) {
      final iris = irisOf(effect, width, paper);

      expect(iris.paper, const Rect.fromLTRB(20, 10, 90, 40), reason: 'whole');
      final got = await blurred(tester, source, effect, paper: paper);
      expectWithinOne(
        got,
        await truth(tester, input, width, iris),
        reason: '$effect',
      );
    }
  });

  testWidgets('through its light — highlights boosted, in linear light or '
      'as stored — a picture blurs to the mean of the light each pixel '
      'gives, put back as stored', (tester) async {
    final (width, height) = (150, 40);
    final bytes = randomPicture(width, height, seed: 5);
    final source = await imageOf(tester, bytes, width, height);
    final input = await bytesOf(tester, source);
    final paper = Rect.fromLTWH(0, 0, width * 1.0, height * 1.0);
    for (final effect in [
      lens(radius: 6, shape: 3, gain: 30, threshold: 150),
      lens(
        radius: 9,
        shape: 5,
        roundness: 40,
        gain: 60,
        threshold: 60,
        saturation: 100,
        linear: true,
      ),
      lens(radius: 7.5, linear: true),
      lens(radius: 8, fringe: 250, gain: 20, threshold: 100, saturation: 50),
    ]) {
      final iris = irisOf(effect, width, paper);
      expect(iris.light, isNotNull, reason: 'fixture: $effect has a light');
      expectWithinOne(
        await blurred(tester, source, effect),
        await truth(tester, input, width, iris),
        reason: '$effect',
      );
    }
  });

  testWidgets('in linear light an edge between white and black blurs as '
      'sRGB\'s own curve has it', (tester) async {
    final (width, height) = (40, 9);
    final bytes = Uint8List(width * height * 4);
    for (var i = 0; i < bytes.length; i += 4) {
      final white = (i ~/ 4) % width < 20;
      bytes.fillRange(i, i + 3, white ? 255 : 0);
      bytes[i + 3] = 255;
    }
    final source = await imageOf(tester, bytes, width, height);
    // A square of 5 × 5: at column 20 two of its five columns are white.
    final at = (4 * width + 20) * 4;
    final linear = await blurred(
      tester,
      source,
      lens(radius: 3, shape: 1, linear: true),
    );
    expect(
      linear[at],
      closeTo(255 * (1.055 * math.pow(0.4, 1 / 2.4) - 0.055), 1),
    );
    expect(linear[at + 3], 255);
    final stored = await blurred(tester, source, lens(radius: 3, shape: 1));
    expect(stored[at], closeTo(255 * 0.4, 1));
  });

  testWidgets('a highlight spread over what is clear covers it: a lamp\'s '
      'bokeh shows over a clear cel (I-132-Q20 a)', (tester) async {
    final (width, height, dotX, dotY) = (40, 40, 20, 20);
    final source = await imageOf(
      tester,
      dotPicture(width, height, dotX, dotY),
      width,
      height,
    );
    final effect = lens(radius: 5, shape: 1, gain: 100, threshold: 0);
    final iris = irisOf(effect, width, const Rect.fromLTWH(0, 0, 40, 40));
    final cover = irisLaidCoverOf(await irisTableOf(tester, iris), iris);
    // White past a threshold of 0 gains a hundred times its luma more.
    expect(101 / cover.weight, greaterThan(1), reason: 'fixture: outshines');
    final got = await blurred(tester, source, effect);

    final lit = litBy(cover, dotX, dotY);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final at = (y * width + x) * 4;
        expect(
          got.sublist(at, at + 4),
          lit.contains((x, y)) ? [255, 255, 255, 255] : [0, 0, 0, 0],
          reason: '($x, $y)',
        );
      }
    }
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
    final cover = irisLaidCoverOf(await irisTableOf(tester, iris), iris);
    final edge = cover.outline[cover.reach];
    expect(
      got[(dotY * width + dotX - edge.left) * 4 + 3],
      closeTo(255 / cover.weight, 1),
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
      await truth(tester, input, width, irisOf(effect, width, paper)),
    );
  });

  /// [source] through [pass], each pixel at the radius [map] names
  /// ([IrisGatherPass.map]): its rows summed as a camera lens blur sums
  /// them ([rowSumPasses]), then its iris gathered out of the sums.
  /// [pass] drawn over [source] by the shaders themselves, reading [map]
  /// where the pass reads one.
  Future<Uint8List> blurredBy(
    WidgetTester tester,
    ui.Image source,
    IrisGatherPass pass, {
    ui.Image? map,
  }) async {
    final (width, height) = (source.width, source.height);
    ui.Image drawn(ui.FragmentShader shader, {required bool inFloats}) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        Rect.fromLTWH(0, 0, width * 1.0, height * 1.0),
        Paint()
          ..shader = shader
          ..blendMode = BlendMode.src,
      );
      final image = rasterPicture(recorder, width, height, inFloats: inFloats);
      shader.dispose();
      addTearDown(image.dispose);
      return image;
    }

    var sums = source;
    for (final sum in rowSumPasses(width, light: pass.light)) {
      sums = drawn(
        IrisBlurShader.rowSumFor(source: sums, pass: sum),
        inFloats: true,
      );
    }
    return bytesOf(
      tester,
      drawn(
        IrisBlurShader.gatherFor(
          sums: sums,
          input: source,
          pass: pass,
          map: map,
        ),
        inFloats: false,
      ),
    );
  }

  group('a blur map', () {
    final (width, height) = (60, 30);

    IrisGatherPass mappedBy(
      IrisMapChannel channel, {
      double radius = 60,
      double focal = 128,
      bool inverts = false,
    }) => IrisGatherPass(
      radius: radius,
      iris: (
        sides: 6,
        roundness: 0.4,
        aspect: 1.3,
        rotation: 0.5,
        fringe: 200,
      ),
      paper: null,
      light: null,
      map: (channel: channel, focal: focal, inverts: inverts),
    );

    testWidgets('names each pixel\'s radius: the blur\'s, times how far its '
        'value lies from the focal distance over 255 — a pixel in focus is '
        'itself', (tester) async {
      final bytes = randomPicture(width, height, seed: 21);
      final source = await imageOf(tester, bytes, width, height);
      final input = await bytesOf(tester, source);
      // Grey, a level a column from 98 on: the focal distance at column 30.
      final levels = Uint8List(width * height * 4);
      for (var i = 0; i < levels.length; i += 4) {
        levels.fillRange(i, i + 3, 98 + (i ~/ 4) % width);
        levels[i + 3] = 255;
      }
      final map = await imageOf(tester, levels, width, height);
      for (final inverts in [false, true]) {
        final pass = mappedBy(
          IrisMapChannel.luminance,
          focal: inverts ? 255 - 128 : 128,
          inverts: inverts,
        );
        final got = await blurredBy(tester, source, pass, map: map);
        expectWithinOne(
          got,
          await truth(tester, input, width, pass, map: levels),
          reason: 'inverts $inverts',
        );
        for (var y = 0; y < height; y += 1) {
          final at = (y * width + 30) * 4;
          expect(
            got.sublist(at, at + 4),
            input.sublist(at, at + 4),
            reason: 'in focus, row $y',
          );
        }
      }
    });

    testWidgets('reads its level off the channel it is told to: the luma, '
        'red, or alpha', (tester) async {
      final bytes = randomPicture(width, height, seed: 23);
      final source = await imageOf(tester, bytes, width, height);
      final input = await bytesOf(tester, source);
      final levels = randomPicture(width, height, seed: 29);
      final map = await imageOf(tester, levels, width, height);
      for (final channel in [
        IrisMapChannel.luminance,
        IrisMapChannel.red,
        IrisMapChannel.alpha,
      ]) {
        final pass = mappedBy(channel, radius: 20, focal: 40);
        expectWithinOne(
          await blurredBy(tester, source, pass, map: map),
          await truth(tester, input, width, pass, map: levels),
          reason: channel.name,
        );
      }
    });
  });

  // A level of more than 1024 rows takes two lines of the table: the rows
  // from 424 below on lie on the second. A triangle turned to point down
  // lays its narrowest rows there, by its tip — narrower than the picture,
  // so a row read off the wrong line sums to something else.
  testWidgets('an iris of more than 1024 rows reads its rows off both '
      'lines of its table, with a blur map or without', (tester) async {
    final (width, height) = (16, 620);
    final bytes = randomPicture(width, height, seed: 31);
    final source = await imageOf(tester, bytes, width, height);
    final input = await bytesOf(tester, source);
    // Every level from 230 up: each past 540 at a focal distance of 0.
    final random = math.Random(37);
    final levels = Uint8List(width * height * 4);
    for (var i = 0; i < levels.length; i += 4) {
      levels.fillRange(i, i + 4, 230 + random.nextInt(26));
    }
    final map = await imageOf(tester, levels, width, height);
    const shape = (
      sides: 3,
      roundness: 0.0,
      aspect: 1.0,
      rotation: math.pi,
      fringe: 200.0,
    );
    for (final reads in [false, true]) {
      final pass = IrisGatherPass(
        radius: 600,
        iris: shape,
        paper: null,
        light: null,
        map: reads
            ? (channel: IrisMapChannel.red, focal: 0, inverts: false)
            : null,
      );
      expectWithinOne(
        await blurredBy(tester, source, pass, map: reads ? map : null),
        await truth(tester, input, width, pass, map: reads ? levels : null),
        reason: 'a map $reads',
      );
    }
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
