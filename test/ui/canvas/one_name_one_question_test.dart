import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/core/draw_space.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/ui/canvas/composite_effect_paint.dart';

/// 🚨★★★ONE NAME WAS ANSWERING THREE QUESTIONS.
///
/// `rasterScale` used to mean all of these, in the same files:
///
/// 1. **what space the DRAW lands in** — 1 under a canvas-space CTM, because
///    Skia maps a blur's sigma through the matrix; the raster's scale where a
///    route draws pre-scaled pixels with no matrix to map anything;
/// 2. **what scale a SUB-TREE should raster at** — a request, which the plan
///    may clamp against the 8192 cap;
/// 3. **what resolution the IMAGE the steps run over already has.**
///
/// They agree on most routes, which is exactly what made the overload safe to
/// keep and impossible to notice. ⛔They stopped agreeing at the playback
/// painter, which draws a Half/Quarter cache up to canvas space — and the
/// hand-written ratio that followed was already wrong in the export path.
///
/// So (1) has a type now, (3) is derived and renamed `imageScale`, and (2)
/// keeps the name because it is the only one left asking it.
void main() {
  group('the draw space is a value, not a number', () {
    test('canvas space is the identity, and says so', () {
      expect(DrawSpace.canvas.scale, 1);
      expect(DrawSpace.canvas.isCanvasSpace, isTrue);
      expect(const DrawSpace.preScaled(0.5).isCanvasSpace, isFalse);
    });

    test('it is a VALUE, so a resolve is not a new object every frame', () {
      expect(const DrawSpace.preScaled(0.5), const DrawSpace.preScaled(0.5));
      expect(
        const DrawSpace.preScaled(0.5).hashCode,
        const DrawSpace.preScaled(0.5).hashCode,
      );
      expect(const DrawSpace.preScaled(1), DrawSpace.canvas);
    });

    test('it scales the blur and leaves colour alone', () {
      final full = resolveCompositeEffectPaint([
        ResolvedLayerEffect(kind: EffectKind.blur, values: const [12, 12]),
      ]);
      final half = resolveCompositeEffectPaint(
        [ResolvedLayerEffect(kind: EffectKind.blur, values: const [12, 12])],
        space: const DrawSpace.preScaled(0.5),
      );
      expect(full.outsetPixels, 12);
      expect(
        half.outsetPixels,
        6,
        reason: 'a half-size raster must not show a double blur',
      );
    });
  });

  test('no lib file hands a bare number where a draw space is wanted', () {
    // ⛔A SOURCE SCAN, because the compiler already stops the ones it can see
    // and what it cannot see is a route added later that reaches for the old
    // name. `rasterScale` may still be a double — it is question (2), and the
    // geometry parameter `drawPosedLayerImage` takes — but it must never
    // again be the argument to a chain resolve.
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      final path = file.path.replaceAll(r'\', '/');
      final source = file.readAsStringSync();
      for (final resolve in const [
        'resolveCompositeEffectPaint(',
        'resolveCompositeEffectPlan(',
        'resolveAdjustmentScopePass(',
      ]) {
        var at = source.indexOf(resolve);
        while (at >= 0) {
          // The call's own arguments end at the first blank line or the next
          // resolve — a window is enough to catch `rasterScale:` riding along.
          final window = source.substring(
            at,
            (at + 400).clamp(0, source.length),
          );
          final args = window.substring(0, window.indexOf(');') + 1);
          if (args.contains('rasterScale:')) {
            offenders.add('$path (${resolve.replaceAll('(', '')})');
          }
          at = source.indexOf(resolve, at + 1);
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'a chain resolve takes a DrawSpace — the caller has to say '
          'WHICH space, because 1 and s are both plausible numbers and only '
          'one of them is right for a given route',
    );
  });

  test('the step scale is not a parameter anyone can get wrong', () {
    // `applyEffectSteps` still takes `imageScale`, but only `steppedForChain`
    // calls it in lib — and that one derives the number from the image.
    final source = File(
      'lib/src/ui/canvas/subtree_image_composite.dart',
    ).readAsStringSync();
    final callers = 'imageScale:'.allMatches(source).length;
    expect(
      callers,
      lessThanOrEqualTo(2),
      reason: 'the declaration and the one derived call — a third means a '
          'route started spelling the ratio out again',
    );
    expect(
      source.contains('image.width / canvasExtent'),
      isTrue,
      reason: 'and it is still derived rather than passed',
    );
  });
}
