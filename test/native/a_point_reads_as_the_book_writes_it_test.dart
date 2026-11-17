import 'package:anicel/src/native/qa_pen_points.dart';
import 'package:flutter_test/flutter_test.dart';

/// The numbers the book hands a point in — points.rs `Point::words`, whose
/// count the crate holds this file's to — read back as the point: the
/// crate's own case writes these same numbers.
void main() {
  test("a point reads as the book writes it, the driver's pressure last", () {
    final points = QaPenPoints.pointsOf([
      1.5, 2.25, 7, 0.5, 0.25, -1.5, 0.75, //
      3, 4, 9, double.nan, double.nan, double.nan, double.nan,
    ]);
    expect(points, [
      (
        x: 1.5,
        y: 2.25,
        at: const Duration(microseconds: 7),
        pressure: 0.5,
        tilt: 0.25,
        orientation: -1.5,
        driven: 0.75,
      ),
      (
        x: 3.0,
        y: 4.0,
        at: const Duration(microseconds: 9),
        pressure: null,
        tilt: null,
        orientation: null,
        driven: null,
      ),
    ]);
  });
}
