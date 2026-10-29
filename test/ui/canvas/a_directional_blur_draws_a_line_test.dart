import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';
import 'package:anicel/src/services/directional_blur_passes.dart';
import 'package:anicel/src/services/guide_geometry.dart';
import 'package:anicel/src/ui/canvas/directional_blur_shader.dart';
import 'package:anicel/src/ui/canvas/layer_image_draw.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';

/// 🗣️I-132-Q3 · Q8 (유저 2026-10-27): AE's Directional Blur — every pixel the
/// average of the line through it, [blurLength] across; 0° up, clockwise,
/// so 0° blurs up and down.
///
/// 🔬Drawn as a raster step at the identity, not an `ImageFilter.shader` in
/// the frame: on Impeller that filter ignored the canvas's turn and spread a
/// dot no further than ±1 px ([ShadedEffect]). This runner's Skia draws a
/// raster a pass; Impeller lays the passes in one raster, held to these
/// bytes by `a_steps_passes_are_layers_of_one_picture_test`. A dot is the
/// probe here too — what it becomes IS the kernel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(DirectionalBlurShader.load);

  ResolvedLayerEffect directional({
    required double degrees,
    required double length,
  }) => ResolvedLayerEffect(
    kind: EffectKind.directionalBlur,
    values: [degrees, length],
  );

  const side = 128;
  const centre = side ~/ 2;

  /// One opaque white pixel at the centre of a transparent [side] square.
  ui.Image dot() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(centre.toDouble(), centre.toDouble(), 1, 1),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..isAntiAlias = false,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(side, side);
    picture.dispose();
    return image;
  }

  /// Every pixel's alpha, row by row.
  Future<List<int>> alphasOf(WidgetTester tester, ui.Image image) async {
    final data = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final bytes = data!.buffer.asUint8List();
    return [for (var i = 3; i < bytes.length; i += 4) bytes[i]];
  }

  /// The pixels with any alpha, as (x, y) from the centre.
  Set<(int, int)> inkOf(List<int> alphas) => {
    for (var i = 0; i < alphas.length; i += 1)
      if (alphas[i] != 0) (i % side - centre, i ~/ side - centre),
  };

  Future<List<int>> blurred(
    WidgetTester tester,
    List<ResolvedLayerEffect> chain, {
    double canvasExtent = side * 1.0,
  }) async {
    final source = dot();
    addTearDown(source.dispose);
    // The picture is the canvas, all of it.
    final canvas = Rect.fromLTWH(0, 0, canvasExtent, canvasExtent);
    final out = steppedForChain(
      image: source,
      plan: resolveCompositeEffectPlan(chain, paper: canvas),
      extent: canvas,
      paper: canvas,
    );
    if (!identical(out, source)) {
      addTearDown(out.dispose);
    }
    return alphasOf(tester, out);
  }

  group('the passes make one box', () {
    for (final length in [1.0, 1.5, 7.0, 32.0, 33.0, 500.0, 1024.0, 1025.0]) {
      test('$length long', () {
        final passes = directionalBlurPasses(dx: 0.6, dy: -0.8, length: length);
        final taps = passes.first.taps;
        expect(passes.map((pass) => pass.taps).toSet(), {taps});
        expect(taps, inInclusiveRange(1, lineBoxTapsAPass));
        final samples = math.pow(taps, passes.length);
        expect(
          samples,
          greaterThanOrEqualTo(length),
          reason: 'a sample every pixel at most — no gap between two',
        );
        expect(
          passes.length == 1 ||
              math.pow(lineBoxTapsAPass, passes.length - 1) < length,
          isTrue,
          reason: 'the fewest passes that reach it',
        );
        for (var index = 0; index < passes.length; index += 1) {
          final pass = passes[index];
          final step = math.sqrt(
            pass.stepX * pass.stepX + pass.stepY * pass.stepY,
          );
          expect(
            step * math.pow(taps, passes.length - index),
            closeTo(length, 1e-9),
            reason: 'each pass N times the one before, the last across '
                'the length',
          );
          expect(pass.stepX * 0.8, closeTo(-pass.stepY * 0.6, 1e-9));
        }
      });
    }
  });

  testWidgets('90° lays a dot out across, the length long, evenly', (
    tester,
  ) async {
    final alphas = await blurred(tester, [
      directional(degrees: 90, length: 15),
    ]);
    expect(inkOf(alphas), {for (var x = -7; x <= 7; x += 1) (x, 0)});
    // 255 / 15: one tap a pixel lands on the dot.
    expect(
      {
        for (var x = -7; x <= 7; x += 1)
          alphas[centre * side + centre + x],
      },
      {17},
    );
  });

  testWidgets('🗣️I-132-Q8: 0° blurs up and down', (tester) async {
    final alphas = await blurred(tester, [
      directional(degrees: 0, length: 15),
    ]);
    expect(inkOf(alphas), {for (var y = -7; y <= 7; y += 1) (0, y)});
  });

  testWidgets('the angle turns clockwise from up: 45° runs up and right', (
    tester,
  ) async {
    final ink = inkOf(
      await blurred(tester, [directional(degrees: 45, length: 21)]),
    );
    expect(ink, contains((6, -6)));
    expect(ink, contains((-6, 6)));
    expect(ink, isNot(contains((6, 6))));
    expect(ink, isNot(contains((-6, -6))));
  });

  testWidgets('past the picture there is nothing — its edge is not smeared '
      'in', (tester) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, centre.toDouble(), 1, 1),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..isAntiAlias = false,
    );
    final picture = recorder.endRecording();
    final source = picture.toImageSync(side, side);
    picture.dispose();
    addTearDown(source.dispose);
    final out = steppedForChain(
      image: source,
      plan: resolveCompositeEffectPlan(
        [directional(degrees: 90, length: 15)],
        paper: Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      ),
      extent: Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      paper: Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    );
    addTearDown(out.dispose);
    final alphas = await alphasOf(tester, out);
    // One tap of fifteen lands on it, as anywhere else on the line: the
    // seven left of the edge read nothing, not the edge pixel again.
    expect(alphas[centre * side], 17);
  });

  testWidgets('a picture taller than wide is blurred where its dot stands', (
    tester,
  ) async {
    // Every other probe here is square: a step or a shader that read its
    // height off its width would blur them all the same.
    const width = 32;
    const height = 128;
    const row = 100;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(width / 2, row.toDouble(), 1, 1),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..isAntiAlias = false,
    );
    final picture = recorder.endRecording();
    final source = picture.toImageSync(width, height);
    picture.dispose();
    addTearDown(source.dispose);
    final out = steppedForChain(
      image: source,
      plan: resolveCompositeEffectPlan(
        [directional(degrees: 90, length: 15)],
        paper: Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ),
      extent: Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      paper: Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    addTearDown(out.dispose);
    final alphas = await alphasOf(tester, out);
    expect({
      for (var i = 0; i < alphas.length; i += 1)
        if (alphas[i] != 0) (i % width, i ~/ width),
    }, {for (var x = width ~/ 2 - 7; x <= width ~/ 2 + 7; x += 1) (x, row)});
  });

  testWidgets('a long blur is passes, and still one unbroken line', (
    tester,
  ) async {
    expect(
      directionalBlurPasses(dx: 1, dy: 0, length: 100),
      hasLength(2),
      reason: 'fixture: longer than one pass reaches',
    );
    final alphas = await blurred(tester, [
      directional(degrees: 90, length: 100),
    ]);
    // Ten taps half a pixel off centre, then ten ten pixels apart: the
    // box's hundred samples, each between two pixels, so 101 of them.
    expect(inkOf(alphas), {for (var x = -50; x <= 50; x += 1) (x, 0)});
  });

  testWidgets("its length is the raster's: a half-size image, half the line", (
    tester,
  ) async {
    final full = inkOf(
      await blurred(tester, [directional(degrees: 90, length: 20)]),
    );
    final half = inkOf(
      await blurred(tester, [
        directional(degrees: 90, length: 20),
      ], canvasExtent: side * 2.0),
    );
    // Twenty taps (ten at half size), each half a pixel off a pixel.
    expect(full, {for (var x = -10; x <= 10; x += 1) (x, 0)});
    expect(half, {for (var x = -5; x <= 5; x += 1) (x, 0)});
  });

  testWidgets('it turns with its layer, as the Gaussian does', (tester) async {
    final source = dot();
    addTearDown(source.dispose);
    final recorder = ui.PictureRecorder();
    // A quarter turn about the centre: across becomes down.
    drawPosedLayerImage(
      Canvas(recorder),
      pieces: [
        (
          image: source,
          worldRect: Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
        ),
      ],
      extent: Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      paper: Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      placement: GuideTransform(0, 1, -1, 0, side.toDouble(), 0),
      opacity: 1,
      blendMode: LayerBlendMode.normal,
      effects: [directional(degrees: 90, length: 15)],
      texelScale: 1,
      filterQuality: ui.FilterQuality.none,
    );
    final picture = recorder.endRecording();
    final shown = picture.toImageSync(side, side);
    picture.dispose();
    addTearDown(shown.dispose);
    final ink = inkOf(await alphasOf(tester, shown));
    expect(ink.map((at) => at.$1).toSet(), hasLength(1));
    expect(ink.map((at) => at.$2).toSet(), hasLength(15));
  });

  group('the plan', () {
    test('a blur of no length is no step, whichever way it points', () {
      final plan = resolveCompositeEffectPlan([
        directional(degrees: 37, length: 0),
      ], paper: Rect.zero);
      expect(plan.isSingleDraw, isTrue);
      expect(plan.finalPaint.isEmpty, isTrue);
    });

    test('it is a step of its own, and grows the buffer half the line each '
        'way', () {
      final plan = resolveCompositeEffectPlan([
        directional(degrees: 90, length: 40),
      ], paper: Rect.zero);
      expect(plan.preSteps, hasLength(1));
      expect(plan.preSteps.single.lead, isA<ShadedEffect>());
      expect(plan.preSteps.single.then, isEmpty);
      expect(plan.finalPaint.isEmpty, isTrue);
      expect(plan.outsetPixels, 21);
    });

    test('what comes before it is a step before it, and what follows it the '
        'draw after', () {
      final blur = ResolvedLayerEffect(
        kind: EffectKind.blur,
        values: const [3, 3],
      );
      final plan = resolveCompositeEffectPlan([
        blur,
        directional(degrees: 90, length: 40),
        blur,
      ], paper: Rect.zero);
      expect([for (final step in plan.preSteps) step.lead.runtimeType], [
        Null,
        ShadedEffect,
      ]);
      expect(plan.preSteps.first.then, [blur]);
      expect(plan.finalPaint.isNotEmpty, isTrue);
      expect(
        plan.outsetPixels,
        21 + 2 * resolveCompositeEffectPaint([blur]).outsetPixels,
      );
    });
  });
}
