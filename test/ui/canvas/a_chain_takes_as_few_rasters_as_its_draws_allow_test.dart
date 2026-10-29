@Tags(['impeller'])
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';
import 'package:anicel/src/ui/canvas/colour_key_shader.dart';
import 'package:anicel/src/ui/canvas/directional_blur_shader.dart';
import 'package:anicel/src/ui/canvas/iris_blur_shader.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';

/// 🗣️fx-made-light-by-one-law (유저 2026-10-29 「fx들 가볍게 하는 로직은
/// 서로 최대한 법 통일하면서 알아서해줘. 근본구조적으로」), after
/// effect-step-passes-each-pay-a-snapshot-Q1 a: an effect chain is laid as
/// ONE picture and rastered only where a draw reads the picture before it as
/// an image — a key run's input, a camera lens blur's sums and gather, the
/// paper cut out for a blur repeating its edge — and the picture is the one
/// a raster a draw makes.
///
/// ⚠️ONE STEP OF 1/255 AT MOST where a blur lies between two draws, the
/// Surface's own measure (10-29, Windows GLES: 0.4–0.8% of the pixels that
/// far, none further): between two draws a raster rounds to a byte where a
/// layer does not. A colour key rounds its alpha to a byte itself
/// (`colour_key.frag`), so keys alone are the same bytes.
///
/// ⚠️IMPELLER ONLY: Skia has no shader filter, so on the default runner
/// every draw is a raster and this skips.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await DirectionalBlurShader.load();
    await IrisBlurShader.load();
    await ColourKeyShader.load();
  });

  tearDown(() => debugDrawsInOnePicture = true);

  const width = 72;
  const height = 48;
  const canvas = Rect.fromLTWH(0, 0, width * 1.0, height * 1.0);

  /// A pixel apiece of colour and alpha, the same every run — what any
  /// sample landing elsewhere would show.
  ui.Image noise() {
    final random = math.Random(3);
    final recorder = ui.PictureRecorder();
    final into = Canvas(recorder);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        into.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
          Paint()
            ..color = Color(random.nextInt(1 << 32))
            ..isAntiAlias = false,
        );
      }
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }

  Future<Uint8List> bytesOf(WidgetTester tester, ui.Image image) async {
    final data = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    return data!.buffer.asUint8List();
  }

  /// [chain] over the noise with [paper], laid in one picture or a raster a
  /// draw, and how many rasters it took.
  Future<(Uint8List, int)> stepped(
    WidgetTester tester,
    ui.Image source,
    List<ResolvedLayerEffect> chain, {
    required Rect paper,
    required bool inOnePicture,
  }) async {
    debugDrawsInOnePicture = inOnePicture;
    debugChainRasters = 0;
    final out = steppedForChain(
      image: source,
      plan: resolveCompositeEffectPlan(chain, paper: paper),
      extent: canvas,
      paper: paper,
    );
    final rasters = debugChainRasters;
    final bytes = await bytesOf(tester, out);
    if (!identical(out, source)) {
      out.dispose();
    }
    return (bytes, rasters);
  }

  ResolvedLayerEffect directional(double degrees, double length) =>
      ResolvedLayerEffect(
        kind: EffectKind.directionalBlur,
        values: [degrees, length],
      );

  ResolvedLayerEffect radial(double amount, {required bool zoom}) =>
      ResolvedLayerEffect(
        kind: EffectKind.radialBlur,
        values: [amount, 0, if (zoom) 1 else 0, 0],
        points: {'center': CanvasPoint(x: 41.5, y: 17.25)},
      );

  ResolvedLayerEffect key(int colour, {required bool keeps}) =>
      ResolvedLayerEffect(
        kind: EffectKind.colorKey,
        values: [if (keeps) 1 else 0, colour.toDouble(), 120, 80],
      );

  ResolvedLayerEffect gaussian({bool repeats = false}) => ResolvedLayerEffect(
    kind: EffectKind.blur,
    values: [3, 0, if (repeats) 1 else 0],
  );

  final brighter = ResolvedLayerEffect(
    kind: EffectKind.brightnessContrast,
    values: [40, 25],
  );
  final cameraLens = ResolvedLayerEffect(
    kind: EffectKind.cameraLensBlur,
    values: [
      for (final spec in EffectKind.cameraLensBlur.parameters)
        if (spec.id == 'blurRadius') 6 else spec.defaultValue,
    ],
  );
  const inner = Rect.fromLTWH(5, 4, 58, 37);

  // What a chain takes in one picture, against what it takes a raster a draw
  // ([off]): a number where the count is the chain's own.
  final chains =
      <
        String,
        ({
          List<ResolvedLayerEffect> chain,
          Rect paper,
          bool Function(int laid, int off) takes,
          int most,
        })
      >{
        'a directional blur of one pass': (
          chain: [directional(90, 12)],
          paper: canvas,
          takes: (laid, off) => laid == 1 && off == 1,
          most: 1,
        ),
        'a directional blur of two passes': (
          chain: [directional(30, 40)],
          paper: canvas,
          takes: (laid, off) => laid == 1 && off == 2,
          most: 1,
        ),
        'a spin': (
          chain: [radial(30, zoom: false)],
          paper: canvas,
          takes: (laid, off) => laid == 1,
          most: 1,
        ),
        'a zoom': (
          chain: [radial(20, zoom: true)],
          paper: canvas,
          takes: (laid, off) => laid == 1,
          most: 1,
        ),
        // Two steps, as they always were — and one picture.
        'a blur, a colour, a blur': (
          chain: [directional(30, 40), brighter, directional(0, 12)],
          paper: canvas,
          takes: (laid, off) => laid == 1 && off == 3,
          most: 1,
        ),
        'a blur, a Gaussian, a blur': (
          chain: [directional(120, 40), gaussian(), radial(25, zoom: true)],
          paper: canvas,
          takes: (laid, off) => laid == 1 && off > 2,
          most: 1,
        ),
        'two blurs': (
          chain: [directional(0, 40), radial(25, zoom: true)],
          paper: canvas,
          takes: (laid, off) => laid == 1 && off > 2,
          most: 1,
        ),
        'two keys': (
          chain: [
            key(0xFF808080, keeps: false),
            key(0xFF406080, keeps: true),
          ],
          paper: canvas,
          takes: (laid, off) => laid == 1 && off == 2,
          most: 0,
        ),
        // A key run reads its input beside it: the blur before it is a
        // raster, the keys one more.
        'a blur, then two keys': (
          chain: [
            directional(30, 40),
            key(0xFF808080, keeps: false),
            key(0xFF406080, keeps: true),
          ],
          paper: canvas,
          takes: (laid, off) => laid == 2 && off == 4,
          most: 1,
        ),
        // The paper is cut out of the picture before it; the colour after the
        // blur, and the blur after that, lie over it in the same raster — the
        // blur after it, because a painted effect after every lead is the
        // composite draw's, which a step never holds.
        "a Gaussian repeating the paper's edge, a colour, a blur": (
          chain: [gaussian(repeats: true), brighter, directional(45, 20)],
          paper: inner,
          takes: (laid, off) => laid == 1 && off == 3,
          most: 1,
        ),
        "a Gaussian repeating the paper's edge, then a blur along a way": (
          chain: [gaussian(repeats: true), directional(45, 20)],
          paper: inner,
          takes: (laid, off) => laid == 1 && off == 2,
          most: 1,
        ),
        // Its sums are numbers past a byte and its gather reads them: every
        // raster of its own stays one.
        'a camera lens blur': (
          chain: [cameraLens],
          paper: canvas,
          takes: (laid, off) => laid == off && laid > 1,
          most: 0,
        ),
        // ...and what lies over its gather is one picture with it.
        'a camera lens blur, then a blur along a way': (
          chain: [cameraLens, directional(30, 40)],
          paper: canvas,
          takes: (laid, off) => laid == off - 2,
          most: 1,
        ),
        // Its gather and the colour on it are a raster, as the keys after
        // read them; the keys one more — a fresh paint each, so the colour
        // is laid once.
        'a camera lens blur, a colour, then two keys': (
          chain: [
            cameraLens,
            brighter,
            key(0xFF808080, keeps: false),
            key(0xFF406080, keeps: true),
          ],
          paper: canvas,
          takes: (laid, off) => laid == off - 1,
          most: 0,
        ),
      };

  for (final MapEntry(key: name, value: (:chain, :paper, :takes, :most))
      in chains.entries) {
    testWidgets(
      name,
      (tester) async {
        final source = noise();
        addTearDown(source.dispose);
        final (rastered, off) = await stepped(
          tester,
          source,
          chain,
          paper: paper,
          inOnePicture: false,
        );
        final (layered, laid) = await stepped(
          tester,
          source,
          chain,
          paper: paper,
          inOnePicture: true,
        );
        expect(
          takes(laid, off),
          isTrue,
          reason: 'one picture took $laid rasters, a raster a draw $off',
        );

        final original = await bytesOf(tester, source);
        var moved = 0;
        var far = 0;
        for (var i = 0; i < rastered.length; i += 1) {
          if (rastered[i] != original[i]) {
            moved += 1;
          }
          far = math.max(far, (rastered[i] - layered[i]).abs());
        }
        expect(
          moved,
          greaterThan(rastered.length ~/ 2),
          reason: 'the chain moved the picture — a picture left as it came '
              'would match itself',
        );
        expect(far, lessThanOrEqualTo(most), reason: 'the same picture');
      },
      skip: !ui.ImageFilter.isShaderFilterSupported,
    );
  }
}
