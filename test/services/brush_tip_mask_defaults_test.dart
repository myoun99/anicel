// EVERY BUNDLED TIP AND TEXTURE MASK IS A FULL 64-SIDED SQUARE.
//
// A survivor of the mutation campaign (2026-09-03): the chalk generator's
// row loop bound `y < size` became `y <= size`, which walks one row past
// the buffer. No test ever touched the generated masks; this one does,
// for all eight.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/services/brush_tip_mask_defaults.dart';

void main() {
  final masks = [
    chalkBrushTipMask,
    splatterBrushTipMask,
    grainBrushTipMask,
    bristleBrushTipMask,
    spongeBrushTipMask,
    wetBlotBrushTipMask,
    paperGrainTextureMask,
    canvasWeaveTextureMask,
  ];

  test('every bundled mask is 64 a side with an alpha per cell', () {
    for (final mask in masks) {
      expect(mask.size, 64, reason: mask.id);
      expect(mask.alpha.length, 64 * 64, reason: mask.id);
    }
  });

  test('🚨a shipped generator never changes — the alpha sums, locked', () {
    // ⛔THE SOURCE ALREADY CLAIMED THIS TEST EXISTED. `brush_tip_mask_defaults`
    // says "the alpha sums are locked in tests" and has since the masks
    // shipped — but nothing pinned a byte, only the shape above. The comment
    // was the whole enforcement, which is to say there was none.
    //
    // Why it matters enough to lock: changing a generator RE-RENDERS EVERY
    // OLD STROKE that used its mask. A stroke is stored as dabs plus a tip
    // ID, so the bytes behind that id are part of the saved artwork's
    // meaning. A new look is a NEW mask with a new id, never an edit here.
    //
    // ⚠️These numbers are FINGERPRINTS, not designed values: they were
    // measured from the generators as they shipped. A failure here does not
    // mean a number is wrong — it means a generator moved, and the question
    // to answer is whether that was intended (in which case it needs a new
    // id) rather than what to type in to make it green.
    const sums = <String, int>{
      'builtin-chalk': 224521,
      'builtin-splatter': 115796,
      'builtin-grain': 251292,
      'builtin-bristle': 251426,
      'builtin-sponge': 73504,
      'builtin-wet-blot': 366774,
      'builtin-paper-grain': 702170,
      'builtin-canvas-weave': 692736,
    };

    expect(
      masks.map((mask) => mask.id).toSet(),
      sums.keys.toSet(),
      reason: 'a mask was added or renamed without a fingerprint',
    );
    for (final mask in masks) {
      expect(
        mask.alpha.fold<int>(0, (total, byte) => total + byte),
        sums[mask.id],
        reason: mask.id,
      );
    }
  });

  test('the wet blot gains towards its rim, unlike every other tip', () {
    // The one tip whose falloff runs backwards, and the reason it exists: a
    // wash leaves pigment at the boundary as it dries.
    //
    // ⚠️Rings, and MEANS over them — never one pixel. The first draft of this
    // pin compared a single centre cell and went red on chalk, because chalk
    // drops ~30% of its cells outright for grain and the centre happened to
    // be one of them. A speckled tip has no meaningful pixel; it only has a
    // distribution.
    double meanOf(BrushTipMask mask, double from, double to) {
      const centre = 32.0;
      var total = 0;
      var cells = 0;
      for (var y = 0; y < 64; y += 1) {
        for (var x = 0; x < 64; x += 1) {
          final dx = x + 0.5 - centre;
          final dy = y + 0.5 - centre;
          final edge = (dx * dx + dy * dy) / (31.0 * 31.0);
          if (edge >= from * from && edge < to * to) {
            total += mask.alpha[y * 64 + x];
            cells += 1;
          }
        }
      }
      return cells == 0 ? 0 : total / cells;
    }

    expect(
      meanOf(wetBlotBrushTipMask, 0.80, 0.92),
      greaterThan(meanOf(wetBlotBrushTipMask, 0.0, 0.5)),
      reason: 'the rim band must be heavier than the pool',
    );
    // ...and the ordinary law, so the contrast is what is being pinned:
    // chalk fades outward, which is what every other tip here does.
    expect(
      meanOf(chalkBrushTipMask, 0.80, 0.92),
      lessThan(meanOf(chalkBrushTipMask, 0.0, 0.5)),
      reason: 'chalk is the control — it must fade towards its rim',
    );
  });
}
