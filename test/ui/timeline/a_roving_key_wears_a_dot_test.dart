import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/key_mark.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/ui/timeline/key_mark_glyph.dart';

/// I-89 ④: a key whose time roves wears After Effects' small dot on the
/// frame axis — not its sides, which say nothing of the pace through it —
/// where it roves; an end flagged roving keeps its time, and its sides.
void main() {
  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  test('a lane wears the dot where a key roves, and its sides at an end '
      'the flag cannot free', () {
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

  test('the dot is half as wide as the box, in its middle — smaller than '
      'the whole disc of 「부드럽게 지나감」, and filled', () {
    expect(
      keyMarkPath(KeyMark.roving, 12).getBounds(),
      const Rect.fromLTWH(3, 3, 6, 6),
    );
    expect(keyMarkIsHollow(KeyMark.roving), isFalse);
  });
}
