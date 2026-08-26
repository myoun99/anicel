import 'package:anicel/src/models/import/tvpp_camera_bake.dart';
import 'package:anicel/src/models/import/tvpp_parse.dart';
import 'package:flutter_test/flutter_test.dart';

TvppCameraPoint _point({
  double x = 0,
  double y = 0,
  int instant = 0,
  double zoom = 1,
  double rotation = 0,
}) =>
    TvppCameraPoint(
      x: x,
      y: y,
      rotationDegrees: rotation,
      zoomFactor: zoom,
      sizeX: 320,
      sizeY: 180,
      instant: instant,
      bezierBeforeX: 0,
      bezierBeforeY: 0,
      bezierAfterX: 0,
      bezierAfterY: 0,
    );

void main() {
  group('TvppCameraProfile', () {
    test('empty or two linear points = identity', () {
      const linear = TvppCameraProfile(points: []);
      expect(linear.progressAt(0.3), 0.3);
      const twoPoint = TvppCameraProfile(points: [
        TvppCameraProfilePoint(
            x: 0, y: 0, bezierBeforeX: 0, bezierBeforeY: 0, bezierAfterX: 0, bezierAfterY: 0),
        TvppCameraProfilePoint(
            x: 1, y: 1, bezierBeforeX: 0, bezierBeforeY: 0, bezierAfterX: 0, bezierAfterY: 0),
      ]);
      // Degenerate handles keep the curve on the y=x line even though the
      // parameterization is cubic.
      expect(twoPoint.progressAt(0.5), closeTo(0.5, 1e-6));
      expect(twoPoint.progressAt(0.25), closeTo(0.25, 1e-6));
    });

    test('ease handles bend the curve without leaving 0..1', () {
      const eased = TvppCameraProfile(points: [
        TvppCameraProfilePoint(
            x: 0, y: 0, bezierBeforeX: 0, bezierBeforeY: 0, bezierAfterX: 0.4, bezierAfterY: 0),
        TvppCameraProfilePoint(
            x: 1,
            y: 1,
            bezierBeforeX: -0.4,
            bezierBeforeY: 0,
            bezierAfterX: 0,
            bezierAfterY: 0),
      ]);
      expect(eased.progressAt(0), closeTo(0, 1e-6));
      expect(eased.progressAt(1), closeTo(1, 1e-6));
      expect(eased.progressAt(0.5), closeTo(0.5, 1e-6)); // symmetric
      expect(eased.progressAt(0.15), lessThan(0.1)); // slow start
      expect(eased.progressAt(0.85), greaterThan(0.9)); // slow end
      var last = 0.0;
      for (var t = 0.0; t <= 1.0; t += 0.05) {
        final p = eased.progressAt(t);
        expect(p, greaterThanOrEqualTo(last - 1e-9));
        last = p;
      }
    });
  });

  group('bakeTvppCamera', () {
    test('holds before the first key and after the last', () {
      final poses = bakeTvppCamera(
        [_point(x: 10, instant: 5), _point(x: 20, instant: 8)],
        const [],
        frameCount: 12,
      );
      expect(poses, hasLength(12));
      expect(poses[0].x, 10);
      expect(poses[4].x, 10);
      expect(poses[8].x, 20);
      expect(poses[11].x, 20);
    });

    test('a segment eased by its profile lags the linear midpoint', () {
      const easeIn = TvppCameraProfile(points: [
        TvppCameraProfilePoint(
            x: 0, y: 0, bezierBeforeX: 0, bezierBeforeY: 0, bezierAfterX: 0.6, bezierAfterY: 0),
        TvppCameraProfilePoint(
            x: 1, y: 1, bezierBeforeX: 0, bezierBeforeY: 0, bezierAfterX: 0, bezierAfterY: 0),
      ]);
      final poses = bakeTvppCamera(
        [_point(x: 0), _point(x: 100, instant: 8)],
        const [easeIn],
        frameCount: 9,
      );
      // A pure slow-start: frame 2 sits well short of the linear 25.
      expect(poses[2].x, lessThan(15));
      expect(poses[8].x, closeTo(100, 1e-6));
    });

    test('zoom and rotation interpolate along the same easing', () {
      final poses = bakeTvppCamera(
        [
          _point(zoom: 1, rotation: 0),
          _point(zoom: 2, rotation: -10, instant: 10),
        ],
        const [],
        frameCount: 11,
      );
      expect(poses[5].scale, closeTo(1.5, 1e-6));
      expect(poses[5].angleDegrees, closeTo(-5, 1e-6));
    });
  });
}
