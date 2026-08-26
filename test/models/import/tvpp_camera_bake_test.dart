import 'package:anicel/src/models/import/tvpp_camera_bake.dart';
import 'package:anicel/src/models/import/tvpp_parse.dart';
import 'package:flutter_test/flutter_test.dart';

TvppCameraPoint _point({
  double x = 0,
  double y = 0,
  int instant = 0,
  int flags = 15,
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
      flags: flags,
      bezierBeforeX: 0,
      bezierBeforeY: 0,
      bezierAfterX: 0,
      bezierAfterY: 0,
    );

TvppCameraChannels _position(List<TvppCameraProfile> profiles) =>
    TvppCameraChannels(
      position: profiles,
      rotation: const [],
      zoom: const [],
      size: const [],
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

    test('a handle is a RAW offset, and a zero handle stays at its '
        'anchor', () {
      // Two segments; the second is 0.8 wide in x. Solving x(u)=0.5 on
      // P0=(0.2,0.5), C1=P0, C2=(0.5,1), P3=(1,1) gives y ≈ 0.822217
      // (solved independently). The Δ-scaled reading — C2=(0.6,1) —
      // gives 0.790121; the PROFILE_CAL 4_handle bake recovered the
      // stored handle raw to three decimals, so raw is the pin.
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
      expect(profile.progressAt(0.5), closeTo(0.822217, 5e-4));
    });

    test('a mode=1 (線形) profile is a polyline — its stored handles are '
        'ignored', () {
      // Both curve types materialize the auto-smooth handles into the
      // file; the type alone picks the evaluator. 6_multipoint_line
      // (mode 1) bakes the straight lines between its points while
      // 7_multipoint_spline bakes the same handles as a bezier.
      const profile = TvppCameraProfile(mode: 1, points: [
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
      // Linear between (0.2, 0.5) and (1, 1): 0.5 + 0.375·0.5. The
      // bezier reading of the same points gives 0.822217 — the handle
      // must not bend a 線形 curve.
      expect(profile.progressAt(0.5), closeTo(0.6875, 1e-9));
    });

    test('progress clamps to [0, 1] when the curve overshoots', () {
      // The calibration curve: a handle pushes the bezier above 1
      // mid-segment; TVPaint's own bake flatlines at the key value.
      const overshooting = TvppCameraProfile(points: [
        TvppCameraProfilePoint(
            x: 0, y: 0, bezierBeforeX: 0, bezierBeforeY: 0, bezierAfterX: 0.3, bezierAfterY: 3.0),
        TvppCameraProfilePoint(
            x: 1, y: 1, bezierBeforeX: 0, bezierBeforeY: 0, bezierAfterX: 0, bezierAfterY: 0),
      ]);
      expect(overshooting.progressAt(0.5), 1.0);
      expect(overshooting.progressAt(0.95), 1.0);
    });
  });

  group('bakeTvppCamera', () {
    test('holds before the first key; the END key is reached one frame '
        'past its instant (the +1 belongs to the whole path)', () {
      final poses = bakeTvppCamera(
        [_point(x: 10, instant: 5), _point(x: 20, instant: 8)],
        TvppCameraChannels.none,
        frameCount: 12,
      );
      expect(poses, hasLength(12));
      expect(poses[0].x, 10);
      expect(poses[5].x, 10);
      // L = 3, so frame k advances 3/4 of a frame of path time: the pan
      // runs through the key's own frame and lands on the next one.
      expect(poses[6].x, closeTo(12.5, 1e-6));
      expect(poses[8].x, closeTo(17.5, 1e-6));
      expect(poses[9].x, 20);
      expect(poses[11].x, 20);
    });

    test('an INTERIOR key is passed between frames — segments stretch '
        'proportionally, they do not each gain a frame', () {
      // Keys at 0, 24, 48: PROFILE_CAL 2_point_added measured the frame
      // AT the middle key sitting at 48/49 of segment one — one global
      // warp p = k·L/(L+1), not a per-segment span+1.
      final poses = bakeTvppCamera(
        [
          _point(x: 0, instant: 0),
          _point(x: 100, instant: 24),
          _point(x: 300, instant: 48),
        ],
        TvppCameraChannels.none,
        frameCount: 50,
      );
      expect(poses[24].x, closeTo(100 * 48 / 49, 1e-6));
      expect(poses[25].x,
          closeTo(100 + 200 * (25 * 48 / 49 - 24) / 24, 1e-6));
      expect(poses[49].x, closeTo(300, 1e-6),
          reason: 'p(49) = L exactly — the end key lands');
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
        _position(const [TvppCameraProfile(points: []), easeIn]),
        frameCount: 11,
      );
      expect(eased[2].x, lessThan(12), reason: 'well short of the linear 20');
      expect(eased[10].x, closeTo(100, 1e-6));

      // The same curve on the SOURCE key is the editor default there —
      // it must not ease the segment (SKK: reading it was 601px wrong).
      final ignored = bakeTvppCamera(
        points,
        _position(const [easeIn, TvppCameraProfile(points: [])]),
        frameCount: 11,
      );
      expect(ignored[5].x, closeTo(50, 1e-6), reason: 'linear');
    });

    test('channels are independent tracks: a rotation keyed on its own '
        'key animates straight through the position keys', () {
      // PROFILE_CAL 5_custom: rotation keyed only at instant 40 (flags
      // 15) runs from the path start, ignoring the position-only key at
      // 34 (flags 1), and holds one frame past its own instant.
      final poses = bakeTvppCamera(
        [
          _point(x: 0, instant: 0),
          _point(x: 100, instant: 34, flags: 1),
          _point(x: 200, rotation: -7, instant: 40),
          _point(x: 300, instant: 48, flags: 1),
        ],
        TvppCameraChannels.none,
        frameCount: 50,
      );
      // Rotation track = keys 0 and 40; frame 40 sits at p = 40·48/49.
      expect(poses[40].angleDegrees, closeTo(-7 * (40 * 48 / 49) / 40, 1e-6));
      expect(poses[41].angleDegrees, closeTo(-7, 1e-6),
          reason: 'p(41) is past the rotation key — held');
      expect(poses[49].angleDegrees, closeTo(-7, 1e-6),
          reason: 'the position-only end key does not reset rotation');
      // Position still uses all four position-keyed points.
      expect(poses[49].x, closeTo(300, 1e-6));
    });

    test('zoom and rotation interpolate along the same easing when '
        'keyed together', () {
      final poses = bakeTvppCamera(
        [
          _point(zoom: 1, rotation: 0),
          _point(zoom: 2, rotation: -10, instant: 9),
        ],
        TvppCameraChannels.none,
        frameCount: 11,
      );
      expect(poses[5].scale, closeTo(1.5, 1e-6));
      expect(poses[5].angleDegrees, closeTo(-5, 1e-6));
      expect(poses[10].scale, closeTo(2, 1e-6));
    });
  });
}
