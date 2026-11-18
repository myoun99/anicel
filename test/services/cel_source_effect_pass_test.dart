import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/cel_source_effect_pass.dart';

import '../helpers/a_plugin_that_shifts.dart';

/// A row's colour keys, one at a time, and the leading run of them a
/// chain's head holds ([celSourceKeys]).
///
/// ↩️It walked the keys a plugin after them reads, too — erasing, keeping,
/// a tile's memo — while that plugin ran on the CPU over the cel: the
/// engine keys the row the plugin reads since it is a step of the chain,
/// each pixel as the definition does
/// (`the_engine_keys_a_row_as_each_pixel_is_keyed_test`,
/// float-warp-resamples-in-the-c-engine (2), 2026-11-11).
void main() {
  // The Color Key: Key Colors, or Keep Colors with [keep] (I-132-Q2).
  ResolvedLayerEffect key({
    bool keep = false,
    int red = 0,
    int green = 0,
    int blue = 0,
    double tolerance = 0,
    double amount = 100,
  }) => ResolvedLayerEffect(
    kind: EffectKind.colorKey,
    values: [
      if (keep) 1 else 0,
      (0xFF000000 | red << 16 | green << 8 | blue).toDouble(),
      tolerance,
      amount,
    ],
  );

  group('CelColorKey', () {
    test('tolerance is the largest single-channel gap, not the distance', () {
      final erase = CelColorKey.fromResolved(
        key(red: 100, green: 100, blue: 100, tolerance: 10),
      )!;
      // Every channel 10 away: Chebyshev says 10, inside. A Euclidean
      // metric would call this 17.3 and let the pixel through — that
      // difference is the whole reason this test names the metric.
      expect(erase.matches(110, 110, 110), isTrue);
      expect(erase.matches(90, 90, 90), isTrue);
      // One channel 11 away is out, however close the other two are.
      expect(erase.matches(100, 100, 111), isFalse);
    });

    test('keep gives back what its run took, by the same comparison', () {
      final erase = CelColorKey.fromResolved(key(red: 255))!;
      final keep = CelColorKey.fromResolved(key(keep: true, red: 255))!;
      expect(erase.alphaFor(255, 0, 0, 200, original: 200), 0);
      expect(erase.alphaFor(0, 0, 0, 200, original: 200), 200);
      // 🚨I-132-Q2 (유저 2026-10-27 「하나로 + AE 뜻」): a keep gives back,
      // and erases nothing — ↩️it erased every pixel its colour did not
      // name.
      expect(keep.alphaFor(255, 0, 0, 0, original: 200), 200);
      expect(keep.alphaFor(0, 0, 0, 0, original: 200), 0);
      expect(keep.alphaFor(0, 0, 0, 200, original: 200), 200);
      // Nothing taken before it: nothing to give back.
      expect(keep.alphaFor(255, 0, 0, 200, original: 200), 200);
    });

    test('Amount folds into the one pass instead of a second draw', () {
      final half = CelColorKey.fromResolved(key(amount: 50))!;
      // 🚨A two-pass mix would ACCUMULATE alpha here (the rule 6 bug):
      // 200 over 200 at half strength comes back ABOVE 200, not below it.
      expect(half.alphaFor(0, 0, 0, 200, original: 200), 100);
      expect(half.alphaFor(0, 0, 0, 255, original: 255), 128);
      // A keep at half gives back half of what was taken.
      final halfBack = CelColorKey.fromResolved(key(keep: true, amount: 50))!;
      expect(halfBack.alphaFor(0, 0, 0, 0, original: 200), 100);
      expect(halfBack.alphaFor(0, 0, 0, 100, original: 200), 150);
    });

    test('an already-empty pixel is never woken up', () {
      final keep = CelColorKey.fromResolved(key(keep: true, red: 255))!;
      // Color bytes under a zero alpha are arbitrary; a keep must not read
      // them as ink and hand back an alpha.
      expect(keep.alphaFor(255, 0, 0, 0, original: 0), 0);
    });

    test('Amount 0 is the no-op an added effect must be', () {
      final fresh = LayerEffect.defaults(
        id: const EffectId('fx'),
        kind: EffectKind.colorKey,
      );
      final resolved = resolveLayerEffectsAt(
        effects: [fresh],
        frameIndex: 0,
        blocks: null,
        worn: null,
      );
      expect(
        resolved,
        isEmpty,
        reason: 'adding a color key must not erase the line art on sight',
      );
    });
  });

  final blur = ResolvedLayerEffect(kind: EffectKind.blur, values: const [4, 0]);

  group('the leading keys of a chain', () {
    test('are the run of keys it opens with, in their order', () {
      final keys = [key(), key(keep: true)];
      expect(celSourceKeys([...keys, blur]), keys);
      final whole = [...keys];
      expect(identical(celSourceKeys(whole), whole), isTrue);
    });

    test('a plugin after them is a step of the chain, not one of them', () {
      final keys = [key(), key(keep: true)];
      expect(celSourceKeys([...keys, shiftingFxPluginEffect(), blur]), keys);
    });

    test('a chain with no keys has none', () {
      expect(celSourceKeys([blur]), isEmpty);
    });

    test('the LEADING run, not every key of the chain', () {
      // 🚨ORDER IS FREE. A key UNDER a blur means "blur first, then key",
      // and there is no cel byte left to key by then — so only the leading
      // run can key the cel's own bytes. The rest are steps over what the
      // chain has painted so far.
      expect(celSourceKeys([key(), blur, key()]).map((e) => e.kind), [
        EffectKind.colorKey,
      ]);
    });

    test('a chain that opens with paint has none at all', () {
      expect(celSourceKeys([blur, key()]), isEmpty);
    });

    test('a row HOLDS the order it was given', () {
      // ⛔This used to assert the opposite — the chain normalized so a key
      // could never sit under a blur. 유저 2026-08-27: 「누가 트랜스폼fx처럼
      // 고정 fx가 아닌것에 순서를 고정하라했지? ae는 순서 자유잖아. …
      // 순서가 결과에 영향주는거고」.
      final blurred = LayerEffect.defaults(
        id: const EffectId('blur'),
        kind: EffectKind.blur,
      );
      final colorKey = LayerEffect.defaults(
        id: const EffectId('key'),
        kind: EffectKind.colorKey,
      );
      final row = Layer(
        id: const LayerId('row'),
        name: 'row',
        frames: const [],
        timeline: const {},
        effects: [blurred, colorKey],
      );
      expect(row.effects.map((e) => e.kind).toList(), [
        EffectKind.blur,
        EffectKind.colorKey,
      ]);
    });
  });
}
