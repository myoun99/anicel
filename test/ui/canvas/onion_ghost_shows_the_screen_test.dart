import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/onion_skin_settings.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/onion_skin_plan.dart';
import 'package:anicel/src/services/composite_effect_paint.dart'
    show onionTintColorMatrix;

/// I-8-Q5 — 유저 2026-08-27 chose "the ghost shows the pixels the screen
/// shows". The old exception was not a design: the Colors tint was written
/// straight onto `Paint.colorFilter`, which is ONE slot, so a ghost could
/// wear the tint or the row's chain and never both.
void main() {
  // A ghost of a row, of a row in a colour and of a row blurred, each in
  // its peg's colour over the chain, is the engine's to lay — TREE pins
  // each ('a ghost' · 'a ghost of a row in a colour' · 'a ghost of a row
  // blurred along a way'). ↩️Pinned here on the Skia paint the tint folded
  // into (`resolveCompositeEffectPaint`) till the Flutter chain went
  // (the-flutter-fx-chain-is-a-second-chain).
  group('the tint is a matrix the chain composes with', () {
    test('the tint matrix takes the RGB and keeps only the alpha', () {
      final matrix = onionTintColorMatrix(0x8012_3456);
      // Rows read: out.r = 0x12, out.g = 0x34, out.b = 0x56, out.a = a×(128/255).
      expect(matrix.sublist(0, 5), [0, 0, 0, 0, 0x12]);
      expect(matrix.sublist(5, 10), [0, 0, 0, 0, 0x34]);
      expect(matrix.sublist(10, 15), [0, 0, 0, 0, 0x56]);
      expect(matrix.sublist(15, 19), [0, 0, 0, closeTo(128 / 255, 1e-9)]);
      expect(matrix[19], 0);
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
          0: const TimelineExposure.drawing(FrameId('f0'), length: 1),
          1: const TimelineExposure.drawing(FrameId('f1'), length: 1),
          2: const TimelineExposure.drawing(FrameId('f2'), length: 1),
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
