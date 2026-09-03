// SCATTER SPREADS ON BOTH AXES UNLESS A SETTING SAYS OTHERWISE — IN THE
// CONSTRUCTOR AND IN A JSON THAT PREDATES THE KEY.
//
// Two survivors of the mutation campaign (2026-09-03): the constructor
// default and the `fromJson` fallback for `scatterBothAxes` each flipped to
// false. Nothing noticed; these pins do.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_settings.dart';

void main() {
  test('scatter spreads on both axes by default', () {
    expect(BrushSettings().scatterBothAxes, isTrue);
  });

  test('a json without the key reads as both axes', () {
    final json = Map<String, dynamic>.of(BrushSettings().toJson())
      ..remove('scatterBothAxes');
    expect(BrushSettings.fromJson(json).scatterBothAxes, isTrue);
  });
}
