// A RANGE SELECTION MUST COVER FRAMES, AND TWO LANE SELECTIONS BUILT ALIKE
// ARE THE SAME SELECTION.
//
// Two survivors of the mutation campaign (2026-09-03): the range assert's
// `>` became `>=` (an empty range was accepted) and the lane equality's
// `identical || fields` became `identical && fields` (only the very same
// object was equal to itself). Nothing noticed; these pins do.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';

void main() {
  test('a frame range selection refuses to be empty', () {
    expect(
      () => TimelineFrameRangeSelection(
        layerId: const LayerId('l'),
        startIndex: 3,
        endIndexExclusive: 3,
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('two lane selections with the same fields are equal', () {
    // Not `const`: a const selection canonicalises to ONE object and the
    // identity shortcut would answer for the field comparison under test.
    // A runtime-built list keeps the constructor call non-constant.
    TimelineLaneSelection build() => TimelineLaneSelection(
      layerId: const LayerId('l'),
      laneId: 'lane',
      startIndex: 2,
      endIndexExclusive: 6,
      laneIds: List.of(['lane', 'other']),
    );
    final a = build();
    final b = build();
    expect(identical(a, b), isFalse, reason: 'fixture: two objects');
    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
  });
}
