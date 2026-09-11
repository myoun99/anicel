// A NAMED CHANGE SET WITH ANY ONE CHANNEL FILLED IS NOT EMPTY.
//
// A survivor of the mutation campaign (2026-09-03): `isEmpty`'s `&&` chain
// became `||`, so a change set that touched only opacity read as empty and
// was dropped. This pin fills exactly one channel.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';

void main() {
  test('a change set with only opacity is not empty', () {
    expect(const TransformNamedChanges().isEmpty, isTrue);
    expect(
      const TransformNamedChanges(
        opacity: {
          'fade': (value: 0.5, interpolation: PropertyKeyInterpolation.linear),
        },
      ).isEmpty,
      isFalse,
    );
    expect(
      const TransformNamedChanges(
        rotation: {
          'turn': (value: 90, interpolation: PropertyKeyInterpolation.linear),
        },
      ).isEmpty,
      isFalse,
    );
  });
}
