import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/onion_skin_settings.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/onion_skin_plan.dart';
import 'package:anicel/src/ui/canvas/composite_effect_paint.dart';

/// I-8-Q5 — 유저 2026-08-27 chose "the ghost shows the pixels the screen
/// shows". The old exception was not a design: the Colors tint was written
/// straight onto `Paint.colorFilter`, which is ONE slot, so a ghost could
/// wear the tint or the row's chain and never both.
void main() {
  ResolvedLayerEffect brightness(double value) =>
      ResolvedLayerEffect(kind: EffectKind.brightnessContrast, values: [value, 0]);

  ResolvedLayerEffect blur(double radius) =>
      ResolvedLayerEffect(kind: EffectKind.blur, values: [radius, radius]);

  group('the tint folds into the chain instead of taking its slot', () {
    test('a tint alone still resolves to a color filter', () {
      final resolved = resolveCompositeEffectPaint(const [], tint: 0xFF00FF00);
      expect(resolved.colorFilter, isNotNull);
      expect(resolved.imageFilter, isNull);
    });

    test('tint AND a color effect land as ONE filter, and applyTo accepts it',
        () {
      final resolved = resolveCompositeEffectPaint(
        [brightness(50)],
        tint: 0xFF00FF00,
      );
      expect(resolved.colorFilter, isNotNull);
      expect(resolved.imageFilter, isNull);
      // The assert this used to trip is the point: the tint no longer
      // arrives on the paint ahead of the chain.
      final paint = ui.Paint();
      resolved.applyTo(paint);
      expect(paint.colorFilter, isNotNull);
    });

    test('a tinted BLUR rides the image filter, colours composed inside', () {
      final resolved = resolveCompositeEffectPaint(
        [brightness(50), blur(6)],
        tint: 0xFF00FF00,
      );
      expect(resolved.imageFilter, isNotNull);
      expect(resolved.colorFilter, isNull);
      expect(resolved.outsetPixels, greaterThan(0));
    });

    test('the tint matrix takes the RGB and keeps only the alpha', () {
      final matrix = onionTintColorMatrix(0x8012_3456);
      // Rows read: out.r = 0x12, out.g = 0x34, out.b = 0x56, out.a = a×(128/255).
      expect(matrix.sublist(0, 5), [0, 0, 0, 0, 0x12]);
      expect(matrix.sublist(5, 10), [0, 0, 0, 0, 0x34]);
      expect(matrix.sublist(10, 15), [0, 0, 0, 0, 0x56]);
      expect(matrix.sublist(15, 19), [0, 0, 0, closeTo(128 / 255, 1e-9)]);
      expect(matrix[19], 0);
    });

    test('an empty chain with no tint is still nothing at all', () {
      expect(resolveCompositeEffectPaint(const []), CompositeEffectPaint.none);
    });
  });

  group('a ghost knows its own time', () {
    test('the plan carries the sheet index its drawing is exposed at', () {
      // Three one-frame drawings; the playhead sits on the third.
      final layer = Layer(
        id: const LayerId('a'),
        name: 'a',
        frames: [
          for (final id in ['f0', 'f1', 'f2'])
            Frame(id: FrameId(id), duration: 1, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(const FrameId('f0'), length: 1),
          1: TimelineExposure.drawing(const FrameId('f1'), length: 1),
          2: TimelineExposure.drawing(const FrameId('f2'), length: 1),
        },
      );
      final plans = planOnionSkin(
        layer: layer,
        frameIndex: 2,
        settings: const OnionSkinSettings(),
      );
      expect(plans, isNotEmpty);
      for (final plan in plans) {
        // ★A keyframed effect read at the PLAYHEAD would paint a past
        // drawing with the present frame's numbers.
        expect(plan.frameIndex, isNot(2));
        expect(
          layer.timeline[plan.frameIndex]?.frameId,
          plan.frameId,
          reason: 'the index must be where THAT drawing is exposed',
        );
      }
    });
  });
}
