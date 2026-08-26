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
    test('holds before the first key; a key is REACHED one frame past '
        'its instant (SKK oracle: 99.7% on the key frame itself)', () {
      final poses = bakeTvppCamera(
        [_point(x: 10, instant: 5), _point(x: 20, instant: 8)],
        const [],
        frameCount: 12,
      );
      expect(poses, hasLength(12));
      expect(poses[0].x, 10);
      expect(poses[5].x, 10);
      // Span is (8 - 5) + 1 = 4: the pan runs through the key's own
      // frame and lands on the next one.
      expect(poses[6].x, closeTo(12.5, 1e-6));
      expect(poses[8].x, closeTo(17.5, 1e-6));
      expect(poses[9].x, 20);
      expect(poses[11].x, 20);
    });

    test("a segment's easing comes from its DESTINATION key's profile",
        () {
      const easeIn = TvppCameraProfile(points: [
        TvppCameraProfilePoint(
            x: 0, y: 0, bezierBeforeX: 0, bezierBeforeY: 0, bezierAfterX: 0.6, bezierAfterY: 0),
        TvppCameraProfilePoint(
            x: 1, y: 1, bezierBeforeX: 0, bezierBeforeY: 0, bezierAfterX: 0, bezierAfterY: 0),
      ]);
      final points = [_point(x: 0), _point(x: 100, instant: 9)];

      // The authored curve on the destination key: slow start.
      final eased = bakeTvppCamera(
        points,
        const [TvppCameraProfile(points: []), easeIn],
        frameCount: 11,
      );
      expect(eased[2].x, lessThan(12), reason: 'well short of the linear 20');
      expect(eased[10].x, closeTo(100, 1e-6));

      // The same curve on the SOURCE key is the editor default there —
      // it must not ease the segment (SKK: reading it was 601px wrong).
      final ignored = bakeTvppCamera(
        points,
        const [easeIn, TvppCameraProfile(points: [])],
        frameCount: 11,
      );
      expect(ignored[5].x, closeTo(50, 1e-6), reason: 'linear');
    });

    test('a profile handle is a FRACTION of its segment, not a raw '
        'offset', () {
      // Two segments; the second is 0.8 wide in x. A -0.5 before-handle
      // means half of THAT segment. Under the raw reading the control
      // would sit at x = 0.6 - 0.5·0.8... the two disagree at t = 0.5.
      const profile = TvppCameraProfile(points: [
        TvppCameraProfilePoint(
            x: 0, y: 0, bezierBeforeX: 0, bezierBeforeY: 0, bezierAfterX: 0, bezierAfterY: 0),
        TvppCameraProfilePoint(
            x: 0.2, y: 0.5, bezierBeforeX: 0, bezierBeforeY: 0, bezierAfterX: 0, bezierAfterY: 0),
        TvppCameraProfilePoint(
            x: 1,
            y: 1,
            bezierBeforeX: -0.5,
            bezierBeforeY: 0,
            bezierAfterX: 0,
            bezierAfterY: 0),
      ]);
      // Δ-scaled: C2 = (1 - 0.5·0.8, 1) = (0.6, 1). Solving x(u) = 0.5
      // on P0=(0.2,0.5), C1=P0, C2=(0.6,1), P3=(1,1) gives y ≈ 0.790121
      // (solved independently); the raw reading, C2=(0.5,1), gives
      // 0.822217 — the pin tells them apart.
      expect(profile.progressAt(0.5), closeTo(0.790121, 5e-4));
    });

    test('zoom and rotation interpolate along the same easing', () {
      final poses = bakeTvppCamera(
        [
          _point(zoom: 1, rotation: 0),
          _point(zoom: 2, rotation: -10, instant: 9),
        ],
        const [],
        frameCount: 11,
      );
      expect(poses[5].scale, closeTo(1.5, 1e-6));
      expect(poses[5].angleDegrees, closeTo(-5, 1e-6));
      expect(poses[10].scale, closeTo(2, 1e-6));
    });
  });
}
