import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../../helpers/a_row_laid_on_the_engine.dart';

/// 🚨★★★ORDER IS FREE, AND IT MEANS WHAT IT SAYS.
///
/// 유저 2026-08-27: *「누가 트랜스폼fx처럼 고정 fx가 아닌것에 순서를
/// 고정하라했지? ae몰라? ae는 순서 자유잖아. 자유롭게 해야지. **순서가
/// 결과에 영향주는거고**」*
///
/// A chain used to be normalized so every colour key sat at the front — the
/// key was a CPU pass over the cel's own bytes and "blur, then key" was not
/// a thing the composite could do. It is now: a key is a step over whatever
/// the chain has painted so far, so the chain is laid in the order it is
/// written, one step per run of keys.
///
/// ↩️Its pixels were the Flutter chain's (`applyEffectSteps`) till it went
/// (the-flutter-fx-chain-is-a-second-chain). A key feeding the next, what
/// follows a run riding its last key, a keep giving back what its run took
/// (I-132-Q2) — each as the eyedropper reads it — are the engine's own pins
/// now (the_engine_keys_a_row_as_each_pixel_is_keyed_test), and a keyed
/// adjustment below full mix TREE's ('an adjustment keyed past a colour at
/// part mix').
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ResolvedLayerEffect blur(double radius) =>
      ResolvedLayerEffect(kind: EffectKind.blur, values: [radius, 0]);

  ResolvedLayerEffect deleteRed() => ResolvedLayerEffect(
    kind: EffectKind.colorKey,
    values: const [0, 0xFFFF0000, 0, 100],
  );

  ResolvedLayerEffect deleteWhite() => ResolvedLayerEffect(
    kind: EffectKind.colorKey,
    // Key Colors, key = white, tolerance 0, amount 100.
    values: const [0, 0xFFFFFFFF, 0, 100],
  );

  group('the plan follows the chain', () {
    test('a chain with no keys is still ONE draw', () {
      final plan = resolveCompositeEffectPlan([blur(3)], paper: Rect.zero);
      expect(plan.isSingleDraw, isTrue);
      expect(plan.preSteps, isEmpty);
      expect(plan.finalEffects, isNotEmpty);
    });

    test('key then blur is ONE step — its draw carries both', () {
      final plan = resolveCompositeEffectPlan(
        [deleteWhite(), blur(3)],
        paper: Rect.zero,
      );
      expect(plan.preSteps.length, 1);
      expect(_keysOf(plan.preSteps.single), hasLength(1));
      expect(plan.preSteps.single.then, isEmpty);
      // The blur stayed on the final draw, where it always was.
      expect(plan.finalEffects, isNotEmpty);
      expect(plan.outsetPixels, greaterThan(0));
    });

    test('blur then key is TWO steps, and the first has no key', () {
      final plan = resolveCompositeEffectPlan(
        [blur(3), deleteWhite()],
        paper: Rect.zero,
      );
      expect(plan.preSteps.length, 2);
      expect(plan.preSteps.first.lead, isNull);
      expect(plan.preSteps.first.then.map((e) => e.kind), [EffectKind.blur]);
      expect(_keysOf(plan.preSteps.last), hasLength(1));
      // Nothing follows the key, so the composite draw carries nothing.
      expect(plan.finalEffects, isEmpty);
      expect(
        plan.outsetPixels,
        3,
        reason: 'what a step before the last paints reaches as far',
      );
    });

    test('a key at Amount 0 is dropped, not rasterised', () {
      // "Add effect" promises to change nothing, and a raster that changes
      // nothing is still a raster.
      final fresh = ResolvedLayerEffect(
        kind: EffectKind.colorKey,
        values: const [0, 0xFFFFFFFF, 0, 0],
      );
      final plan = resolveCompositeEffectPlan(
        [fresh, blur(3)],
        paper: Rect.zero,
      );
      expect(plan.isSingleDraw, isTrue);
    });
  });

  test('keys a painted effect stands between are two runs', () {
    final plan = resolveCompositeEffectPlan([
      deleteWhite(),
      blur(3),
      deleteRed(),
    ], paper: Rect.zero);
    expect(plan.preSteps, hasLength(2));
    expect(_keysOf(plan.preSteps.first), hasLength(1));
    expect(plan.preSteps.first.then.map((e) => e.kind), [EffectKind.blur]);
    expect(_keysOf(plan.preSteps.last), hasLength(1));
  });

  group('on the engine', () {
    const side = 128;
    late GpuComposite composite;
    late EngineLetters letters;

    setUpAll(() async {
      composite = GpuComposite(appGpuEngine);
      letters = await EngineLetters.open(composite);
    });
    tearDownAll(() {
      composite.free();
    });

    test('blur-then-key keys the BLURRED result, not the source', () async {
      // 🚨THE WHOLE POINT, IN PIXELS. Two blocks that TOUCH: white on the
      // left, red on the right.
      //
      // ⚠️The colours have to meet. Blurring white on TRANSPARENT leaves the
      // colour white and only drops the alpha, so a key would still take
      // all of it either way and the test would pass for the wrong reason —
      // the first draft did exactly that. A blur only changes a COLOUR where
      // two colours mix.
      final pixels = Uint8List(side * side * 4);
      for (var y = 40; y < 88; y++) {
        for (var x = 24; x < 104; x++) {
          final at = (y * side + x) * 4;
          final white = x < 64;
          pixels[at] = 255;
          pixels[at + 1] = white ? 255 : 0;
          pixels[at + 2] = white ? 255 : 0;
          pixels[at + 3] = 255;
        }
      }
      final cel = BitmapSurface(
        canvasSize: const CanvasSize(width: side, height: side),
        tileSize: side,
        tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: side, pixels: pixels)},
      );
      final keyFirst = await aRowLaidOnTheEngine(composite, letters, cel, [
        deleteWhite(),
        blur(4),
      ]);
      final blurFirst = await aRowLaidOnTheEngine(composite, letters, cel, [
        blur(4),
        deleteWhite(),
      ]);

      // Just left of the seam, inside the white.
      const seam = (64 * side + 62) * 4;
      // Keyed first, the white went whole; only the red was left to blur,
      // and it spread there red.
      expect(keyFirst[seam + 3], greaterThan(0), reason: 'the red spread');
      expect(keyFirst[seam + 1], 0, reason: 'nothing white was left to mix');
      // Blurred first, the seam had already mixed toward pink, and at
      // tolerance 0 the key spares every pixel that is no longer exactly
      // white.
      expect(blurFirst[seam + 3], 255, reason: 'the pink was spared');
      expect(
        blurFirst[seam + 1],
        allOf(greaterThan(0), lessThan(255)),
        reason: 'the same two effects in the other order are a different '
            'picture — that is what free ordering MEANS',
      );
    });
  });
}

/// The keys [step] opens with — none unless its lead is a run of them.
List<Object> _keysOf(CompositeEffectStep step) => switch (step.lead) {
  KeyRun(:final keys) => keys,
  _ => const [],
};
