// A COMBINE MODE READS BACK FROM ITS NAME, AND AN ADD STEP WIDENS THE
// REGION: A POINT INSIDE ONLY THE ADDED SHAPE IS INSIDE THE REGION.
//
// Two survivors of the mutation campaign (2026-09-03): `fromJson`'s
// `mode.name == value` became `!=` (every name parsed to the first mode
// that was NOT it) and `containsPoint`'s add rule `inside || hit` became
// `inside && hit` (an add step could only ever shrink). Nothing noticed.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';

CanvasSelectionShape _square(double left, double top, double size) =>
    CanvasSelectionShape([
      CanvasPoint(x: left, y: top),
      CanvasPoint(x: left + size, y: top),
      CanvasPoint(x: left + size, y: top + size),
      CanvasPoint(x: left, y: top + size),
    ]);

void main() {
  test('every combine mode reads back from its own name', () {
    for (final mode in SelectionCombineMode.values) {
      expect(SelectionCombineMode.fromJson(mode.name), mode);
    }
    expect(
      SelectionCombineMode.fromJson('no-such-mode'),
      SelectionCombineMode.defaultMode,
    );
  });

  test('a point inside only the added shape is inside the region', () {
    final region = CanvasSelectionRegion([
      CanvasSelectionStep(_square(0, 0, 10), SelectionCombineMode.replace),
      CanvasSelectionStep(_square(20, 20, 10), SelectionCombineMode.add),
    ]);
    expect(region.containsPoint(CanvasPoint(x: 25, y: 25)), isTrue);
    expect(region.containsPoint(CanvasPoint(x: 5, y: 5)), isTrue);
    expect(region.containsPoint(CanvasPoint(x: 15, y: 15)), isFalse);
  });
}
