import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/wrap_degrees.dart';

/// F-222 ①: the one fold every turn drag takes its step through.
void main() {
  test('a step past the seam comes back the short way round', () {
    expect(wrapDegrees(190), -170);
    expect(wrapDegrees(-190), 170);
    expect(wrapDegrees(350), -10);
    expect(wrapDegrees(-350), 10);
  });

  test('whole extra turns fold away', () {
    expect(wrapDegrees(725), 5);
    expect(wrapDegrees(-725), -5);
  });

  test('the half turn keeps its sign, and inside the range nothing moves', () {
    expect(wrapDegrees(180), 180);
    expect(wrapDegrees(-180), -180);
    expect(wrapDegrees(0), 0);
    expect(wrapDegrees(179.5), 179.5);
    expect(wrapDegrees(-45), -45);
  });
}
