import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/ui/canvas/colour_key_shader.dart';
import 'package:anicel/src/ui/canvas/composite_effect_paint.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';

/// 🚨★★★TWO SCALES, TWO QUESTIONS — and one parameter used to answer both.
///
/// A chain's blur radii are CANVAS pixels. Two different numbers turn them
/// into something a draw can use:
///
/// • the PAINT's scale is the space the DRAW lands in — 1 under a canvas-space
///   CTM (Skia maps the sigma through the matrix), the raster's scale where a
///   route draws pre-scaled pixels;
/// • the STEPS' scale is the IMAGE's own resolution, because a step rasters
///   the image at its own size, at the identity, with no matrix to map
///   anything.
///
/// They coincide wherever image and draw share a space, which is why one
/// `rasterScale` served for a long time. ⛔The playback painter is where they
/// stop coinciding — it draws a Half/Quarter cache up to canvas space.
///
/// ⇒ [steppedForChain] DERIVES the step scale from the image and the extent it
/// covers. These tests hold that derivation, because a hand-written ratio at
/// each call site is what it replaced — and one of those was already wrong
/// (the export wrote `1`, which is right at full size and wrong for a
/// storyboard thumbnail).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(ColourKeyShader.load);

  ResolvedLayerEffect key() => ResolvedLayerEffect(
    kind: EffectKind.deleteColor,
    values: const [0, 0, 0, 0, 100],
  );

  ResolvedLayerEffect blur({double radius = 4}) =>
      ResolvedLayerEffect(kind: EffectKind.blur, values: [radius, radius]);

  /// A chain whose STEP carries a blur: a key, then a blur, then a second key
  /// — the only shape that puts painted state inside a step rather than on
  /// the final draw.
  CompositeEffectPlan chainWithABlurInsideAStep() =>
      resolveCompositeEffectPlan([key(), blur(), key()]);

  ui.Image dot(int side) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(side / 4, side / 4, side / 2, side / 2),
      Paint()
        ..color = const Color(0xFFFF0000)
        ..isAntiAlias = false,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(side, side);
    picture.dispose();
    return image;
  }

  Future<List<int>> bytesOf(WidgetTester tester, ui.Image image) async {
    final data = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    return data!.buffer.asUint8List().toList();
  }

  testWidgets('the extent decides the step scale, so it cannot be ignored', (
    tester,
  ) async {
    final plan = chainWithABlurInsideAStep();
    expect(
      plan.preSteps.any((step) => step.then.isNotEmpty),
      isTrue,
      reason: 'fixture: a blur really is inside a step, not on the final draw',
    );

    final source = dot(64);
    addTearDown(source.dispose);

    // Same image, same plan — told it covers 64 canvas px, then 32. The
    // second is a half-resolution cache of a 32px-wide picture, so its blur
    // must come out twice as wide in image pixels.
    final atFull = steppedForChain(
      image: source,
      plan: plan,
      canvasExtent: 64,
    );
    addTearDown(atFull.dispose);
    final atHalf = steppedForChain(
      image: source,
      plan: plan,
      canvasExtent: 32,
    );
    addTearDown(atHalf.dispose);

    expect(
      await bytesOf(tester, atFull),
      isNot(await bytesOf(tester, atHalf)),
      reason: 'a hard-coded ratio would make these identical — which is the '
          'bug the export had at thumbnail sizes',
    );
  });

  testWidgets('an extent equal to the image is scale 1, exactly', (
    tester,
  ) async {
    final plan = chainWithABlurInsideAStep();
    final source = dot(64);
    addTearDown(source.dispose);

    final derived = steppedForChain(
      image: source,
      plan: plan,
      canvasExtent: 64,
    );
    addTearDown(derived.dispose);
    final spelled = applyEffectSteps(
      source: source,
      steps: plan.preSteps,
      pixelWidth: source.width,
      pixelHeight: source.height,
      imageScale: 1,
    );
    addTearDown(spelled.dispose);

    expect(
      await bytesOf(tester, derived),
      await bytesOf(tester, spelled),
      reason: 'the 1:1 routes keep the pixels they always had',
    );
  });

  test('a single-draw chain hands the image straight back', () {
    // ⛔IDENTITY, not equality: the caller disposes only what differs, so a
    // copy here would leak the caller into disposing the cache's image.
    final plan = resolveCompositeEffectPlan([blur()]);
    expect(plan.isSingleDraw, isTrue, reason: 'fixture: no key, no step');
    final source = dot(8);
    addTearDown(source.dispose);
    expect(
      identical(
        steppedForChain(image: source, plan: plan, canvasExtent: 8),
        source,
      ),
      isTrue,
    );
  });

  test('a zero extent falls back to 1 rather than dividing by it', () {
    final plan = chainWithABlurInsideAStep();
    final source = dot(8);
    addTearDown(source.dispose);
    final out = steppedForChain(image: source, plan: plan, canvasExtent: 0);
    addTearDown(out.dispose);
    expect(out.width, 8, reason: 'a degenerate extent still produces a raster');
  });
}
