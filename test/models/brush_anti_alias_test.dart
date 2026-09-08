// THE BRUSH EDGE TIGHTENS WITHOUT MOVING THE RADIUS.
//
// 유저 2026-09-08, after drawing Clip Studio's G펜 at all four settings:
// 「굵기 안바꾸고 가장자리만 조이는거였어」. That sentence is the whole
// specification, and these pins are what make it checkable — the half
// coverage point is the one that must not move, because it IS the radius
// the eye reads.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_anti_alias.dart';

void main() {
  test('3단계 is what the engine already drew — a brush that says nothing '
      'draws identically', () {
    for (final coverage in [0.0, 0.13, 0.5, 0.87, 1.0]) {
      expect(BrushAntiAlias.high.applyTo(coverage), coverage);
    }
    expect(BrushAntiAlias.high.contrast, 1.0);
  });

  test('🚨THE HALF-COVERAGE CROSSING DOES NOT MOVE — that is the whole point', () {
    // What the user looked at: the stroke does not get thinner. The radius
    // the eye reads is where coverage crosses a half, so NO step may move a
    // pixel across that line. ⛔The alpha-threshold shape the user ruled out
    // fails exactly here — raising its cut pushes the crossing inward.
    for (final step in BrushAntiAlias.values) {
      expect(step.applyTo(0.51), greaterThan(0.5), reason: '$step inside');
      expect(step.applyTo(0.49), lessThan(0.5), reason: '$step outside');
    }
    // The scaling steps hold 0.5 as an exact fixed point; 없음 is the one
    // discontinuity, and it resolves the tie by painting (`>=`), which is
    // what makes it a HARD edge rather than a half-lit ring.
    for (final step in [
      BrushAntiAlias.high,
      BrushAntiAlias.medium,
      BrushAntiAlias.low,
    ]) {
      expect(step.applyTo(0.5), 0.5, reason: '$step fixes the half point');
    }
    expect(BrushAntiAlias.none.applyTo(0.5), 1.0);
  });

  test('the ladder tightens, step by step', () {
    // One coverage well inside the ramp: each step drives it further from
    // 0.5 than the last, and 없음 takes it all the way.
    const soft = 0.6;
    final ramp = [
      BrushAntiAlias.high.applyTo(soft),
      BrushAntiAlias.medium.applyTo(soft),
      BrushAntiAlias.low.applyTo(soft),
      BrushAntiAlias.none.applyTo(soft),
    ];
    expect(ramp[0], closeTo(0.6, 1e-12));
    expect(ramp[1], closeTo(0.7, 1e-12));
    expect(ramp[2], closeTo(0.9, 1e-12));
    expect(ramp[3], 1.0);
    // Monotone: no step is softer than the one before it.
    for (var i = 1; i < ramp.length; i += 1) {
      expect(ramp[i], greaterThan(ramp[i - 1]), reason: 'step $i tightens');
    }
  });

  test('없음 is a hard cut, and it is the only step that is', () {
    expect(BrushAntiAlias.none.applyTo(0.49), 0.0);
    expect(BrushAntiAlias.none.applyTo(0.5), 1.0);
    expect(BrushAntiAlias.none.contrast, isNull);
    for (final step in BrushAntiAlias.values.where((s) => s != BrushAntiAlias.none)) {
      expect(step.contrast, isNotNull, reason: '$step scales, not cuts');
    }
  });

  test('the output never leaves the unit interval', () {
    for (final step in BrushAntiAlias.values) {
      for (var i = 0; i <= 20; i += 1) {
        final out = step.applyTo(i / 20);
        expect(out, inInclusiveRange(0.0, 1.0), reason: '$step at ${i / 20}');
      }
    }
  });

  test('the index is Clip Studio\'s 0..3 order', () {
    // The importer is meant to map by index; this is the pin that says the
    // order is the one it will map through.
    expect(BrushAntiAlias.values.map((s) => s.index), [0, 1, 2, 3]);
    expect(BrushAntiAlias.none.index, 0);
    expect(BrushAntiAlias.high.index, 3);
  });

  test('named reads what toJson wrote, and shrugs at anything else', () {
    for (final step in BrushAntiAlias.values) {
      expect(BrushAntiAlias.named(step.toJson()), step);
    }
    expect(BrushAntiAlias.named(null), isNull);
    expect(BrushAntiAlias.named('sharp'), isNull);
  });
}
