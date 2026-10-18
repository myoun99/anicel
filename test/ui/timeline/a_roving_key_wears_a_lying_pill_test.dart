import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/key_mark.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/ui/timeline/key_mark_glyph.dart';

/// I-89 ④: a key whose time roves wears a mark of its own on the frame axis
/// — not its sides, which say nothing of the pace through it — where it
/// roves; an end flagged roving keeps its time, and its sides.
///
/// 🗣️F-367 (유저 2026-10-16): 「다시 정정. 아티팩트 보니 맘이 바뀜. 로빙키
/// 누운 알약으로」 — a pill lying along the frames. ↩️It was After Effects'
/// small dot, half the box across.
void main() {
  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  test('a lane wears the roving mark where a key roves, and its sides at an '
      'end the flag cannot free', () {
    final track = PropertyTrack(
      keys: {
        0: PropertyKey(p(0, 0), roving: true, outgoing: KeyExit.hold),
        5: PropertyKey(p(100, 0), roving: true),
        20: PropertyKey(p(100, 300)),
      },
    );
    expect(keyMarksOf(track), {
      0: const SidesKeyMark(
        incoming: KeySideKind.linear,
        outgoing: KeySideKind.hold,
      ),
      5: KeyMark.roving,
      20: KeyMark.linear,
    });
  });

  test('a header over a roving key and a key of another kind says they '
      'disagree', () {
    expect(
      unionKeyMarks([
        {5: KeyMark.roving},
        {5: KeyMark.linear},
      ]),
      {5: KeyMark.mixed},
    );
    expect(
      unionKeyMarks([
        {5: KeyMark.roving},
        {5: KeyMark.roving},
      ]),
      {5: KeyMark.roving},
    );
  });

  test('the pill is the box\'s width and six tenths of its height, lying '
      'in its middle with round ends, filled', () {
    final pill = keyMarkPath(KeyMark.roving, const Size.square(12));
    expect(
      pill.getBounds(),
      // A path keeps its points in 32 bits.
      rectMoreOrLessEquals(const Rect.fromLTWH(0, 2.4, 12, 7.2), epsilon: 1e-5),
    );
    // F-367-Q4: a narrowed box keeps the pill's height and shortens it.
    expect(
      keyMarkPath(KeyMark.roving, const Size(8, 12)).getBounds(),
      rectMoreOrLessEquals(const Rect.fromLTWH(0, 2.4, 8, 7.2), epsilon: 1e-5),
    );
    expect(pill.contains(const Offset(6, 6)), isTrue, reason: 'its middle');
    expect(
      pill.contains(const Offset(0.6, 2.8)),
      isFalse,
      reason: 'a round end, not a box\'s corner',
    );
    expect(keyMarkIsHollow(KeyMark.roving), isFalse);
  });
}
