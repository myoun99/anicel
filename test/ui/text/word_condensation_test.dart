import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/text/word_condensation.dart';

/// THE narrowing every word in a block keeps (F-93, made every block word's
/// by `block-word-size-at-zoom-Q1` 답 B, 유저 2026-09-24).
void main() {
  test('F-93: a word narrows only once it would run past its room', () {
    expect(wordCondensation(extent: 12, room: 30), 1.0);
    expect(wordCondensation(extent: 12, room: 12), 1.0);
    expect(wordCondensation(extent: 12, room: 3), 0.25);
    expect(
      wordCondensation(extent: 0, room: 3),
      1.0,
      reason: 'nothing to narrow',
    );
  });

  test('never above 1 — a roomy block stretches nothing', () {
    expect(wordCondensation(extent: 5, room: 500), 1.0);
  });

  test('quantised DOWN, so the classic pass and a baked tile agree and the '
      'word still fits', () {
    const extent = 30.8;
    for (final room in [29.9, 24.0, 17.3, 8.0, 2.4]) {
      final factor = wordCondensation(extent: extent, room: room);
      expect(
        (factor * 64).roundToDouble(),
        factor * 64,
        reason: '$room: one of 64 steps, the tile bake keys on it',
      );
      expect(
        extent * factor,
        lessThanOrEqualTo(room),
        reason: '$room: narrowed into the room, never past it',
      );
    }
  });

  test('never below one step — a word that fits nowhere still says it is '
      'there (R26 #38: 「절대 안 사라지도록」)', () {
    expect(wordCondensation(extent: 400, room: 1), 1 / 64);
    expect(wordCondensation(extent: 400, room: 0), 1 / 64);
  });

  test('each axis on its own', () {
    expect(wordFit(const Size(40, 14), const Size(20, 27)), (x: 0.5, y: 1.0));
    expect(wordFit(const Size(10, 14), const Size(24, 7)), (x: 1.0, y: 0.5));
    expect(wordFit(const Size(10, 14), const Size(24, 27)), wordFitsAsItIs);
  });
}
