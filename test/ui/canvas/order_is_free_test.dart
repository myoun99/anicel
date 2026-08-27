import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/ui/canvas/colour_key_shader.dart';
import 'package:anicel/src/ui/canvas/composite_effect_paint.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';

/// 🚨★★★ORDER IS FREE, AND IT MEANS WHAT IT SAYS.
///
/// 유저 2026-08-27: *「누가 트랜스폼fx처럼 고정 fx가 아닌것에 순서를
/// 고정하라했지? ae몰라? ae는 순서 자유잖아. 자유롭게 해야지. **순서가
/// 결과에 영향주는거고**」*
///
/// A chain used to be normalized so every colour key sat at the front — the
/// key was a CPU pass over the cel's own bytes and "blur, then key" was not
/// a thing the composite could do. It is now: a key is a fragment shader
/// over whatever the chain has painted so far, so the chain is rendered in
/// the order it is written, one raster per key.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(ColourKeyShader.load);

  ResolvedLayerEffect blur(double radius) =>
      ResolvedLayerEffect(kind: EffectKind.blur, values: [radius, radius]);

  ResolvedLayerEffect deleteWhite() => ResolvedLayerEffect(
    kind: EffectKind.deleteColor,
    // key = white, tolerance 0, amount 100.
    values: const [255, 255, 255, 0, 100],
  );

  group('the plan follows the chain', () {
    test('a chain with no keys is still ONE draw', () {
      final plan = resolveCompositeEffectPlan([blur(3)]);
      expect(plan.isSingleDraw, isTrue);
      expect(plan.preSteps, isEmpty);
      expect(plan.finalPaint.isNotEmpty, isTrue);
    });

    test('key then blur is ONE step — a paint carries both', () {
      // A `ui.Paint` applies its shader, then its colour filter, then its
      // image filter, so the key can lead the same draw the blur rides.
      final plan = resolveCompositeEffectPlan([deleteWhite(), blur(3)]);
      expect(plan.preSteps.length, 1);
      expect(plan.preSteps.single.key, isNotNull);
      expect(plan.preSteps.single.then, isEmpty);
      // The blur stayed on the final draw, where it always was.
      expect(plan.finalPaint.isNotEmpty, isTrue);
      expect(plan.outsetPixels, greaterThan(0));
    });

    test('blur then key is TWO steps, and the first has no key', () {
      final plan = resolveCompositeEffectPlan([blur(3), deleteWhite()]);
      expect(plan.preSteps.length, 2);
      expect(plan.preSteps.first.key, isNull);
      expect(plan.preSteps.first.then.map((e) => e.kind), [EffectKind.blur]);
      expect(plan.preSteps.last.key, isNotNull);
      // Nothing follows the key, so the composite draw carries nothing.
      expect(plan.finalPaint.isEmpty, isTrue);
      expect(plan.outsetPixels, greaterThan(0));
    });

    test('a key at Amount 0 is dropped, not rasterised', () {
      // "Add effect" promises to change nothing, and a raster that changes
      // nothing is still a raster.
      final fresh = ResolvedLayerEffect(
        kind: EffectKind.deleteColor,
        values: const [255, 255, 255, 0, 0],
      );
      final plan = resolveCompositeEffectPlan([fresh, blur(3)]);
      expect(plan.isSingleDraw, isTrue);
    });
  });

  test('blur-then-key keys the BLURRED result, not the source', () async {
    // 🚨THE WHOLE POINT, IN PIXELS. Two blocks that TOUCH: white on the
    // left, red on the right.
    //
    // ⚠️The colours have to meet. Blurring white on TRANSPARENT leaves the
    // colour white and only drops the alpha, so a key would still take all
    // of it either way and the test would pass for the wrong reason — the
    // first draft did exactly that. A blur only changes a COLOUR where two
    // colours mix.
    const side = 64;
    final straight = Uint8List(side * side * 4);
    for (var y = 20; y < 44; y++) {
      for (var x = 12; x < 52; x++) {
        final at = (y * side + x) * 4;
        final white = x < 32;
        straight[at] = 255;
        straight[at + 1] = white ? 255 : 0;
        straight[at + 2] = white ? 255 : 0;
        straight[at + 3] = 255;
      }
    }
    Future<Uint8List> render(List<ResolvedLayerEffect> chain) async {
      final source = await _imageFrom(straight, side, side);
      final plan = resolveCompositeEffectPlan(chain);
      final stepped = applyEffectSteps(
        source: source,
        steps: plan.preSteps,
        pixelWidth: side,
        pixelHeight: side,
        rasterScale: 1,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint();
      plan.finalPaint.applyTo(paint);
      canvas.drawImageRect(
        stepped,
        const Rect.fromLTWH(0, 0, 64, 64),
        const Rect.fromLTWH(0, 0, 64, 64),
        paint,
      );
      final picture = recorder.endRecording();
      final out = picture.toImageSync(side, side);
      picture.dispose();
      final bytes = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
      out.dispose();
      if (!identical(stepped, source)) {
        stepped.dispose();
      }
      source.dispose();
      return bytes!.buffer.asUint8List();
    }

    int inkPixels(Uint8List bytes) {
      var n = 0;
      for (var i = 3; i < bytes.length; i += 4) {
        if (bytes[i] != 0) {
          n += 1;
        }
      }
      return n;
    }

    final keyFirst = await render([deleteWhite(), blur(4)]);
    final blurFirst = await render([blur(4), deleteWhite()]);

    // ⛔Both must have drawn something, or the comparison below is two
    // empty pictures agreeing.
    expect(inkPixels(keyFirst), greaterThan(0), reason: 'key-first drew');
    expect(inkPixels(blurFirst), greaterThan(0), reason: 'blur-first drew');
    // Keyed first, the white block was still pure white and went entirely;
    // only the red survives to be blurred. Blurred first, the seam had
    // already mixed toward pink, and at tolerance 0 the key spares every
    // pixel that is no longer exactly white.
    var differing = 0;
    for (var i = 0; i < keyFirst.length; i += 4) {
      if (keyFirst[i] != blurFirst[i] ||
          keyFirst[i + 1] != blurFirst[i + 1] ||
          keyFirst[i + 2] != blurFirst[i + 2] ||
          keyFirst[i + 3] != blurFirst[i + 3]) {
        differing += 1;
      }
    }
    expect(
      differing,
      greaterThan(0),
      reason: 'the same two effects in the other order have to be a '
          'different picture — that is what free ordering MEANS',
    );
  });
}

Future<ui.Image> _imageFrom(Uint8List straight, int width, int height) {
  final premultiplied = Uint8List.fromList(straight);
  for (var i = 0; i < premultiplied.length; i += 4) {
    final alpha = premultiplied[i + 3];
    if (alpha == 255) {
      continue;
    }
    premultiplied[i] = (premultiplied[i] * alpha + 127) ~/ 255;
    premultiplied[i + 1] = (premultiplied[i + 1] * alpha + 127) ~/ 255;
    premultiplied[i + 2] = (premultiplied[i + 2] * alpha + 127) ~/ 255;
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    premultiplied,
    width,
    height,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}
