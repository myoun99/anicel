import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_policy.dart';

/// R27 #12: the row axis of a move drag has a deadband. A fast horizontal
/// sweep wobbles vertically; on the old half-cell rounding every wobble
/// handed the step to the row-change path, where an incompatible landing
/// HOLDS — the block stopped following the pointer mid-sweep.
void main() {
  const rowExtent = 28.0;

  int rows(double dy) =>
      timelineRowStepDelta(accumulatedDelta: dy, rowExtent: rowExtent);

  test('a wobble under three quarters of a row stays on the row', () {
    expect(rows(0), 0);
    expect(rows(6), 0);
    expect(rows(14), 0, reason: 'half a row used to already step');
    expect(rows(20), 0);
    expect(rows(-14), 0);
    expect(rows(-20), 0);
  });

  test('a deliberate row change still lands one row per row', () {
    expect(rows(21), 1);
    expect(rows(28), 1);
    expect(rows(49), 2);
    expect(rows(56), 2);
    expect(rows(-21), -1);
    expect(rows(-28), -1);
    expect(rows(-56), -2);
  });

  test('the FRAME axis keeps its half-cell rounding — only rows changed', () {
    expect(
      commaDragFrameDelta(accumulatedDelta: 14, frameCellExtent: rowExtent),
      1,
    );
    expect(
      commaDragFrameDelta(accumulatedDelta: -14, frameCellExtent: rowExtent),
      -1,
    );
  });
}
