// THREE EDITS OF A PROPERTY TRACK: A RANGE SHIFT MAY LAND ON FRAME 0, AND
// THE NAMED-VALUE WRITES TOUCH ONLY KEYS WHOSE VALUE DIFFERS.
//
// Three survivors of the mutation campaign (2026-09-03): the shift's
// floor `< 0` became `<= 0` (a key could no longer land on frame 0), and
// both named writes' `!=` became `==` (they rewrote the keys that already
// matched and skipped the ones that changed). Nothing noticed; these pins
// do.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/property_track.dart';

PropertyTrack<double> _track(Map<int, PropertyKey<double>> keys) =>
    PropertyTrack(keys: keys);

void main() {
  group('withRangedKeysShifted', () {
    test('a key may land on frame 0', () {
      final track = _track({2: const PropertyKey(1.0)});
      final shifted = track.withRangedKeysShifted(
        rangeStartIndex: 2,
        rangeEndIndexExclusive: 3,
        frameDelta: -2,
      );
      expect(shifted, isNotNull);
      expect(shifted!.keys.keys, [0]);
    });

    test('a key may not land below frame 0 or on another key', () {
      final track = _track({
        1: const PropertyKey(1.0),
        3: const PropertyKey(3.0),
      });
      expect(
        track.withRangedKeysShifted(
          rangeStartIndex: 1,
          rangeEndIndexExclusive: 2,
          frameDelta: -2,
        ),
        isNull,
      );
      expect(
        track.withRangedKeysShifted(
          rangeStartIndex: 1,
          rangeEndIndexExclusive: 2,
          frameDelta: 2,
        ),
        isNull,
      );
    });
  });

  group('named values', () {
    final track = _track({
      0: const PropertyKey(1.0, name: 'a'),
      4: const PropertyKey(2.0, name: 'b'),
      8: const PropertyKey(2.0, name: 'a'),
    });

    test('withNamedValue rewrites every key of that name whose value '
        'differs and leaves the rest', () {
      final next = track.withNamedValue('a', 2.0);
      expect(next.keys[0]!.value, 2.0, reason: 'was 1.0, changes');
      expect(next.keys[8]!.value, 2.0, reason: 'already 2.0, untouched');
      expect(next.keys[4]!.value, 2.0, reason: 'another name, untouched');
      expect(identical(track.withNamedValue('b', 2.0), track), isTrue);
    });

    test('withNamedValues applies each name once, changed keys only', () {
      final next = track.withNamedValues({'a': 5.0, 'zz': 9.0});
      expect(next.keys[0]!.value, 5.0);
      expect(next.keys[8]!.value, 5.0);
      expect(next.keys[4]!.value, 2.0);
      expect(identical(track.withNamedValues({'b': 2.0}), track), isTrue);
    });
  });
}
