import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/ui/canvas/composite_effect_paint.dart';

/// R6 — the PIXELS, not just the plan.
///
/// Three claims the round makes about compositing get proved here by
/// rendering them: colour effects actually move channels, a filter does NOT
/// distribute over compositing (which is why a folder carrying one has to
/// buffer), and a group buffer has to grow by the blur's spread or the blur
/// is clipped at the buffer edge.
void main() {
  const size = 40;
  const bounds = ui.Rect.fromLTWH(0, 0, 40, 40);

  ResolvedLayerEffect brightness(double amount) => ResolvedLayerEffect(
    kind: EffectKind.brightnessContrast,
    values: [amount, 0],
  );

  ResolvedLayerEffect blur(double radius) =>
      ResolvedLayerEffect(kind: EffectKind.blur, values: [radius, radius]);

  Future<ui.Image> rasterize(void Function(Canvas canvas) draw) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    draw(canvas);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(size, size);
    } finally {
      picture.dispose();
    }
  }

  Future<List<int>> pixels(ui.Image image) async {
    final data = await image.toByteData();
    return [
      for (var index = 0; index < data!.lengthInBytes; index += 1)
        data.getUint8(index),
    ];
  }

  Future<List<int>> pixelAt(ui.Image image, int x, int y) async {
    final bytes = await pixels(image);
    final index = (y * image.width + x) * 4;
    return bytes.sublist(index, index + 4);
  }

  /// One opaque grey rect, drawn through [plan].
  Future<ui.Image> slabThrough(
    CompositeEffectPaint plan, {
    required ui.Rect rect,
    int grey = 0x80,
  }) {
    return rasterize((canvas) {
      final paint = Paint()..color = Color.fromARGB(255, grey, grey, grey);
      plan.applyTo(paint);
      canvas.drawRect(rect, paint);
    });
  }

  test('a BRIGHTNESS effect actually moves the channels', () async {
    final plain = await slabThrough(CompositeEffectPaint.none, rect: bounds);
    final brighter = await slabThrough(
      resolveCompositeEffectPaint([brightness(20)]),
      rect: bounds,
    );
    addTearDown(() {
      plain.dispose();
      brighter.dispose();
    });
    expect((await pixelAt(plain, 20, 20))[0], closeTo(0x80, 1));
    // +20 of the −100…100 slider = +20 % of full scale = +51.
    expect((await pixelAt(brighter, 20, 20))[0], closeTo(0x80 + 51, 2));
    expect(
      (await pixelAt(brighter, 20, 20))[3],
      255,
      reason: 'a colour matrix must not touch alpha',
    );
  });

  test('a colour effect leaves TRANSPARENT pixels transparent', () async {
    // The classic trap: a brightness offset on a premultiplied buffer would
    // light up empty space. Skia unpremultiplies first, so it must not.
    final image = await slabThrough(
      resolveCompositeEffectPaint([brightness(100)]),
      rect: const ui.Rect.fromLTWH(0, 0, 10, 10),
    );
    addTearDown(image.dispose);
    expect(await pixelAt(image, 30, 30), [0, 0, 0, 0]);
  });

  test(
    'a BLUR does not distribute over compositing — the buffer earns its cost',
    () async {
      // Two abutting slabs. Blurred as a GROUP the seam is invisible (they are
      // one picture); blurred PER MEMBER each edge softens and the seam shows.
      const left = ui.Rect.fromLTWH(0, 0, 20, 40);
      const right = ui.Rect.fromLTWH(20, 0, 20, 40);
      final plan = resolveCompositeEffectPaint([blur(6)]);

      final grouped = await rasterize((canvas) {
        final groupPaint = Paint();
        plan.applyTo(groupPaint);
        canvas.saveLayer(effectBufferBounds(bounds, plan), groupPaint);
        canvas.drawRect(left, Paint()..color = const Color(0xFF808080));
        canvas.drawRect(right, Paint()..color = const Color(0xFF808080));
        canvas.restore();
      });
      final perMember = await rasterize((canvas) {
        final memberPaint = Paint()..color = const Color(0xFF808080);
        plan.applyTo(memberPaint);
        canvas.drawRect(left, memberPaint);
        canvas.drawRect(right, memberPaint);
      });
      addTearDown(() {
        grouped.dispose();
        perMember.dispose();
      });

      // Dead centre of the group: still fully opaque grey, the seam gone.
      final groupedSeam = await pixelAt(grouped, 20, 20);
      final memberSeam = await pixelAt(perMember, 20, 20);
      expect(groupedSeam[3], 255, reason: 'one picture, no seam');
      expect(
        memberSeam[3],
        lessThan(groupedSeam[3]),
        reason:
            'per-member blurring eats the shared edge — the wrong picture, '
            'which is why folderNeedsCompositeBuffer answers true for effects',
      );
    },
  );

  test(
    'the group buffer must GROW by the blur spread or the blur is clipped',
    () async {
      // Artwork sitting just outside the buffer's nominal bounds: its blur has
      // to bleed IN. With un-inflated bounds it is clipped away first.
      const outside = ui.Rect.fromLTWH(-14, 0, 14, 40);
      final plan = resolveCompositeEffectPaint([blur(8)]);

      Future<ui.Image> render({required bool grown}) => rasterize((canvas) {
        final paint = Paint();
        plan.applyTo(paint);
        canvas.saveLayer(
          grown ? effectBufferBounds(bounds, plan) : bounds,
          paint,
        );
        canvas.drawRect(outside, Paint()..color = const Color(0xFF808080));
        canvas.restore();
      });

      final grown = await render(grown: true);
      final clipped = await render(grown: false);
      addTearDown(() {
        grown.dispose();
        clipped.dispose();
      });

      expect(
        (await pixelAt(grown, 2, 20))[3],
        greaterThan(0),
        reason: 'off-buffer artwork bleeds in when the bounds grow',
      );
      expect(
        (await pixelAt(clipped, 2, 20))[3],
        0,
        reason: 'and is clipped away entirely when they do not',
      );
    },
  );

  group('an adjustment scope (R6b)', () {
    /// The scope's pass, run exactly as a composite route runs it.
    Future<ui.Image> renderScope({
      required double mix,
      int scopeColor = 0xFF808080,
      List<ResolvedLayerEffect>? effects,
    }) {
      final pass = resolveAdjustmentScopePass(
        bounds: bounds,
        effects: effects ?? [brightness(40)],
        mix: mix,
      );
      return rasterize((canvas) {
        void drawScope() {
          canvas.drawRect(bounds, Paint()..color = Color(scopeColor));
        }

        if (pass.crossfades) {
          canvas.saveLayer(pass.bufferBounds, pass.crossfadeLayerPaint!);
          canvas.saveLayer(pass.bufferBounds, pass.unfilteredPaint!);
          drawScope();
          canvas.restore();
        }
        canvas.saveLayer(pass.bufferBounds, pass.filteredPaint);
        drawScope();
        canvas.restore();
        if (pass.crossfades) {
          canvas.restore();
        }
      });
    }

    test('at full strength the scope is filtered once', () async {
      final image = await renderScope(mix: 1);
      addTearDown(image.dispose);
      // +40 of the slider = +40 % of full scale = +102.
      expect((await pixelAt(image, 20, 20))[0], closeTo(0x80 + 102, 2));
      expect((await pixelAt(image, 20, 20))[3], 255);
    });

    test('a MIX below 1 crossfades — it must never thin the stack', () async {
      final image = await renderScope(mix: 0.5);
      addTearDown(image.dispose);
      final pixel = await pixelAt(image, 20, 20);
      expect(
        pixel[3],
        255,
        reason:
            'HALF a grade, not a half-transparent picture — the whole reason '
            'the scope is drawn twice',
      );
      // Halfway between the plain 0x80 and the fully graded 0x80+102.
      expect(pixel[0], closeTo(0x80 + 51, 3));
    });

    test('a TRANSLUCENT scope keeps its own alpha at every mix', () async {
      // The trap: drawing the scope unfiltered and then the filtered copy
      // over it with src-over gives lerp(U, F, m) only where the scope is
      // OPAQUE. On a 50 % picture it compounded alpha — 128 came out 160,
      // and the colour with it.
      for (final mix in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final image = await renderScope(mix: mix, scopeColor: 0x80808080);
        addTearDown(image.dispose);
        final pixel = await pixelAt(image, 20, 20);
        expect(
          pixel[3],
          closeTo(128, 2),
          reason: 'mix $mix must not change how transparent the scope is',
        );
      }
    });

    test('a BLURRED scope crossfades, and still keeps its alpha', () async {
      // A spatial chain cannot fold the mix into a matrix, so this is the
      // two-pass path — the one that has to add up inside one buffer.
      final pass = resolveAdjustmentScopePass(
        bounds: bounds,
        effects: [blur(4)],
        mix: 0.5,
      );
      expect(pass.crossfades, isTrue);
      expect(
        resolveAdjustmentScopePass(
          bounds: bounds,
          effects: [brightness(40)],
          mix: 0.5,
        ).crossfades,
        isFalse,
        reason: 'a colour-only chain folds the mix into its matrix instead',
      );

      final image = await renderScope(
        mix: 0.5,
        scopeColor: 0x80808080,
        effects: [blur(4)],
      );
      addTearDown(image.dispose);
      // Dead centre, far from the blur's edges: half sharp + half blurred
      // of the same flat colour is that colour, at its own alpha. The bytes
      // are PREMULTIPLIED, so a 50 %-alpha mid grey reads 64, not 128.
      final pixel = await pixelAt(image, 20, 20);
      expect(pixel[3], closeTo(128, 3));
      expect(pixel[0], closeTo(64, 3));
    });
  });

  test(
    'rasterScale keeps a blur the same SIZE relative to the picture',
    () async {
      // The playback cache composes at a reduced raster and draws pre-scaled
      // images 1:1, so the radius has to scale with them. Rendering the same
      // picture at half size with rasterScale 0.5 must spread half as many
      // raster pixels — not the same number, which would read as a
      // double-strength blur.
      Future<int> spread({required double scale}) async {
        final plan = resolveCompositeEffectPaint([
          blur(12),
        ], rasterScale: scale);
        final image = await rasterize((canvas) {
          final paint = Paint()..color = const Color(0xFF808080);
          plan.applyTo(paint);
          canvas.drawRect(
            ui.Rect.fromLTWH(0, 0, 20 * scale, size.toDouble()),
            paint,
          );
        });
        addTearDown(image.dispose);
        final bytes = await pixels(image);
        var lit = 0;
        final edge = (20 * scale).round();
        for (var x = edge; x < size; x += 1) {
          if (bytes[(20 * size + x) * 4 + 3] > 4) {
            lit += 1;
          }
        }
        return lit;
      }

      final full = await spread(scale: 1);
      final half = await spread(scale: 0.5);
      expect(full, greaterThan(4), reason: 'the blur has to be visible at all');
      expect(
        half,
        closeTo(full / 2, full / 4),
        reason: 'half the raster, half the spread',
      );
    },
  );
}
