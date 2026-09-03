// A PERSPECTIVE GUIDE SNAPS AND SHOWS ITS EYE LEVEL UNLESS TOLD NOT TO.
//
// A survivor of the mutation campaign (2026-09-03): `PerspectiveShape`'s
// `snapEnabled` default flipped to false and every new perspective guide
// stopped snapping. The constructor defaults are the contract; this pins
// them.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/drawing_guide.dart';

void main() {
  test('a perspective guide snaps and shows its eye level by default', () {
    final shape = PerspectiveShape(
      vanishingPoints: [VanishingPointAt(CanvasPoint(x: 100, y: 50))],
      eyeLevel: GuideAxis(origin: CanvasPoint(x: 0, y: 50), angleDegrees: 0),
    );
    expect(shape.snapEnabled, isTrue);
    expect(shape.eyeLevelVisible, isTrue);
  });
}
