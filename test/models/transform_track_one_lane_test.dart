// ONE KEYED LANE MAKES A TRANSFORM TRACK NON-EMPTY AND ITS FRAME KEYED.
//
// Two survivors of the mutation campaign (2026-09-03): `keyframeAt`'s "any
// lane keyed" `||` became `&&`, and `isEmpty`'s "every lane empty" `&&`
// became `||` — a track keyed on position alone then read as empty and
// unkeyed — and nothing noticed, because every test keyed all five lanes
// at once through withKeyframe. These pins key one lane.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';

void main() {
  final positionOnly = TransformTrack().copyWith(
    position: PropertyTrack(keys: {0: PropertyKey(CanvasPoint(x: 3, y: 4))}),
  );

  test('a track keyed on position alone is not empty', () {
    expect(positionOnly.isEmpty, isFalse);
    expect(TransformTrack().isEmpty, isTrue);
  });

  test('the frame that holds the one key is keyed', () {
    expect(positionOnly.keyframeAt(0), isNotNull);
    expect(positionOnly.keyframeAt(1), isNull);
  });
}
