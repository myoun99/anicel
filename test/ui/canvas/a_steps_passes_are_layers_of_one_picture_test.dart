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
import 'package:anicel/src/ui/canvas/directional_blur_shader.dart';
import 'package:anicel/src/ui/canvas/iris_blur_shader.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';

/// 🗣️effect-step-passes-each-pay-a-snapshot-Q1 a (유저 2026-10-29): a
/// directional or a radial blur's passes are the layers of ONE picture
/// where the engine has a shader filter, not a raster a pass (~22ms each on
/// the Surface Pro 11) — and the picture is the one the rasters made.
///
/// ⚠️ONE STEP OF 1/255 AT MOST, the Surface's own measure (10-29, Windows
/// GLES: 0.4–0.8% of the pixels that far, none further): between two passes
/// the rasters round to a byte where the layers do not.
///
/// ⚠️IMPELLER ONLY: Skia has no shader filter, so on the default runner
/// every pass is a raster and this skips.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await DirectionalBlurShader.load();
    await IrisBlurShader.load();
  });

  tearDown(() => debugPassesInOnePicture = true);

  const width = 72;
  const height = 48;

  /// A pixel apiece of colour and alpha, the same every run — what any
  /// sample landing elsewhere would show.
  ui.Image noise() {
    final random = math.Random(3);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        canvas.drawRect(
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

  /// [chain] over the noise, with the passes in one picture or not, and how
  /// many steps laid theirs in one.
  Future<(Uint8List, int)> stepped(
    WidgetTester tester,
    ui.Image source,
    List<ResolvedLayerEffect> chain, {
    required bool inOnePicture,
  }) async {
    debugPassesInOnePicture = inOnePicture;
    debugStepsInOnePicture = 0;
    const canvas = Rect.fromLTWH(0, 0, width * 1.0, height * 1.0);
    final out = steppedForChain(
      image: source,
      plan: resolveCompositeEffectPlan(chain, paper: canvas),
      extent: canvas,
      paper: canvas,
    );
    final laid = debugStepsInOnePicture;
    final bytes = await bytesOf(tester, out);
    if (!identical(out, source)) {
      out.dispose();
    }
    return (bytes, laid);
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

  final brighter = ResolvedLayerEffect(
    kind: EffectKind.brightnessContrast,
    values: [40, 25],
  );
  final gaussian = ResolvedLayerEffect(kind: EffectKind.blur, values: [3]);
  final cameraLens = ResolvedLayerEffect(
    kind: EffectKind.cameraLensBlur,
    values: [
      for (final spec in EffectKind.cameraLensBlur.parameters)
        if (spec.id == 'blurRadius') 6 else spec.defaultValue,
    ],
  );

  final chains = <String, (List<ResolvedLayerEffect>, int)>{
    'a directional blur of one pass': ([directional(90, 12)], 1),
    'a directional blur of two passes': ([directional(30, 40)], 1),
    'a spin': ([radial(30, zoom: false)], 1),
    'a zoom': ([radial(20, zoom: true)], 1),
    'a blur, then a colour over it': ([directional(30, 40), brighter], 1),
    'a blur, then a Gaussian over it': ([directional(120, 40), gaussian], 1),
    'two blurs, a step each': ([directional(0, 40), radial(25, zoom: true)], 2),
    'a camera lens blur, which stays a raster a pass': ([cameraLens], 0),
  };

  for (final MapEntry(key: name, value: (chain, steps)) in chains.entries) {
    testWidgets(
      name,
      (tester) async {
        final source = noise();
        addTearDown(source.dispose);
        final (rastered, none) = await stepped(
          tester,
          source,
          chain,
          inOnePicture: false,
        );
        final (layered, laid) = await stepped(
          tester,
          source,
          chain,
          inOnePicture: true,
        );
        expect(none, 0, reason: 'switched off, every pass is a raster');
        expect(laid, steps, reason: 'the steps that lay their passes in one');

        final original = await bytesOf(tester, source);
        var moved = 0;
        var most = 0;
        for (var i = 0; i < rastered.length; i += 1) {
          if (rastered[i] != original[i]) {
            moved += 1;
          }
          most = math.max(most, (rastered[i] - layered[i]).abs());
        }
        expect(
          moved,
          greaterThan(rastered.length ~/ 2),
          reason: 'the chain moved the picture — a picture left as it came '
              'would match itself',
        );
        expect(most, lessThanOrEqualTo(1), reason: 'the same picture');
      },
      skip: !ui.ImageFilter.isShaderFilterSupported,
    );
  }
}
