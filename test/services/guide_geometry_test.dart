import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/services/guide_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

CanvasPoint _point(double x, double y) => CanvasPoint(x: x, y: y);

void _expectPoint(CanvasPoint actual, double x, double y) {
  expect(actual.x, closeTo(x, 1e-9));
  expect(actual.y, closeTo(y, 1e-9));
}

/// A vertical axis — the plain left/right mirror, and the reason 90° rather
/// than 0° is the symmetry default: [GuideAxis] measures the LINE, and the
/// eye level it shares a type with is horizontal at 0°.
GuideAxis _verticalAxis(double x) =>
    GuideAxis(origin: _point(x, 50), angleDegrees: 90);

SymmetryShape _symmetry({
  required GuideAxis axis,
  int lineCount = 2,
  bool lineSymmetry = true,
}) => SymmetryShape(
  axis: axis,
  lineCount: lineCount,
  lineSymmetry: lineSymmetry,
);

GuideAxis _horizon(double x, double y, double angle) =>
    GuideAxis(origin: _point(x, y), angleDegrees: angle);

PerspectiveShape _perspective(
  List<VanishingPoint> points, {
  bool snapEnabled = true,
  bool constrainToEyeLevel = true,
}) => PerspectiveShape(
  vanishingPoints: points,
  eyeLevel: GuideAxis(origin: _point(0, 100), angleDegrees: 0),
  snapEnabled: snapEnabled,
  constrainToEyeLevel: constrainToEyeLevel,
);

void main() {
  group('symmetryTransforms', () {
    test('produces exactly lineCount copies in both modes', () {
      for (final count in [2, 4, 6, 8, 16]) {
        expect(
          symmetryTransforms(
            _symmetry(axis: _verticalAxis(0), lineCount: count),
          ).length,
          count,
          reason: 'mirrored ×$count',
        );
      }
      for (final count in [2, 3, 5, 16]) {
        expect(
          symmetryTransforms(
            _symmetry(
              axis: _verticalAxis(0),
              lineCount: count,
              lineSymmetry: false,
            ),
          ).length,
          count,
          reason: 'rotational ×$count',
        );
      }
    });

    test('the original is always first and untouched', () {
      final transforms = symmetryTransforms(
        _symmetry(axis: _verticalAxis(100), lineCount: 6),
      );

      expect(transforms.first.isIdentity, isTrue);
      _expectPoint(transforms.first.apply(_point(7, 9)), 7, 9);
    });

    test('a vertical axis mirrors left to right', () {
      final transforms = symmetryTransforms(
        _symmetry(axis: _verticalAxis(100), lineCount: 2),
      );

      expect(transforms.length, 2);
      // A point 50 to the right of the axis lands 50 to its left, same height.
      _expectPoint(transforms[1].apply(_point(150, 30)), 50, 30);
      _expectPoint(transforms[1].apply(_point(20, 30)), 180, 30);
    });

    test('a point ON the axis is its own mirror', () {
      final transforms = symmetryTransforms(
        _symmetry(axis: _verticalAxis(100), lineCount: 2),
      );

      _expectPoint(transforms[1].apply(_point(100, 400)), 100, 400);
    });

    test('mirrored copies alternate handedness, rotational ones never flip', () {
      final mirrored = symmetryTransforms(
        _symmetry(axis: _verticalAxis(0), lineCount: 4),
      );
      final rotational = symmetryTransforms(
        _symmetry(axis: _verticalAxis(0), lineCount: 4, lineSymmetry: false),
      );

      expect(
        mirrored.where((transform) => transform.flipsHandedness).length,
        2,
      );
      expect(
        rotational.where((transform) => transform.flipsHandedness).length,
        0,
        reason: 'rotational symmetry copies nothing mirrored — the reason '
            '"mirror" would be the wrong name for the feature',
      );
    });

    test('count 4 mirrored is the quadrant: x-mirror, 180°, y-mirror', () {
      final transforms = symmetryTransforms(
        _symmetry(
          axis: GuideAxis(origin: _point(100, 100), angleDegrees: 90),
          lineCount: 4,
        ),
      );

      final images = transforms
          .map((transform) => transform.apply(_point(150, 130)))
          .toList();

      _expectPoint(images[0], 150, 130);
      _expectPoint(images[1], 50, 130);
      _expectPoint(images[2], 50, 70);
      _expectPoint(images[3], 150, 70);
    });

    test('rotational count 2 is a half turn, not a mirror', () {
      final transforms = symmetryTransforms(
        _symmetry(
          axis: GuideAxis(origin: _point(0, 0), angleDegrees: 90),
          lineCount: 2,
          lineSymmetry: false,
        ),
      );

      _expectPoint(transforms[1].apply(_point(10, 5)), -10, -5);
    });

    test('rotation turns clockwise, matching the transform lanes', () {
      // Screen coordinates run y-down, so +90° takes +x onto +y.
      final transform = GuideTransform.rotation(_point(0, 0), 90);

      _expectPoint(transform.apply(_point(1, 0)), 0, 1);
    });

    test('every copy of a 16-line kaleidoscope is distinct', () {
      final transforms = symmetryTransforms(
        _symmetry(axis: _verticalAxis(100), lineCount: maxSymmetryLineCount),
      );

      final images = transforms
          .map((transform) => transform.apply(_point(137, 211)))
          .map((point) => '${point.x.toStringAsFixed(6)},'
              '${point.y.toStringAsFixed(6)}')
          .toSet();

      expect(images.length, maxSymmetryLineCount);
    });
  });

  group('angle conventions', () {
    // The tip angle is measured the other way round from an axis angle
    // (visual counter-clockwise in y-down space), so the two maps are one
    // function conjugated by negation — pinned on the values, not on the
    // relation, so a slip in either sign shows up as a wrong number.
    final reflection = GuideTransform.reflection(_point(100, 50), 90);
    final rotation = GuideTransform.rotation(_point(0, 0), 90);

    test('a vertical mirror sends an axis at 30° to 150°', () {
      expect(reflection.mapAxisAngleDegrees(30), closeTo(150, 1e-9));
    });

    test('a vertical mirror sends a tip at 30° to 150° too', () {
      // Up-and-right leans become up-and-left leans; -30° would be the
      // mirror across a HORIZONTAL axis and a bitmap tip would come out
      // upside down.
      expect(reflection.mapTipAngleDegrees(30), closeTo(150, 1e-9));
    });

    test('a quarter turn clockwise turns an axis by +90 and a tip by -90', () {
      expect(rotation.mapAxisAngleDegrees(0), closeTo(90, 1e-9));
      expect(rotation.mapTipAngleDegrees(0), closeTo(-90, 1e-9));
      expect(rotation.mapTipAngleDegrees(30), closeTo(-60, 1e-9));
    });

    test('a collapsing map keeps the angle it was given, in both '
        'conventions', () {
      const collapse = GuideTransform(0, 0, 0, 0, 5, 5);
      expect(collapse.mapAxisAngleDegrees(37), 37);
      expect(collapse.mapTipAngleDegrees(37), 37);
      expect(collapse.mapTipAngleDegrees(-140), -140);
    });

    test('the tip map is the axis map conjugated by negation', () {
      for (final transform in [
        reflection,
        rotation,
        GuideTransform.rotation(_point(3, 4), -37),
        GuideTransform.reflection(_point(0, 0), 20),
      ]) {
        for (final angle in [0.0, 30.0, 95.0, -140.0, 179.5]) {
          expect(
            transform.mapTipAngleDegrees(angle),
            closeTo(-transform.mapAxisAngleDegrees(-angle), 1e-9),
            reason: '$transform at $angle',
          );
        }
      }
    });
  });

  group('snap candidates', () {
    test('every vanishing point of every snapping guide is a candidate', () {
      // A two-point perspective with only one live vanishing point could
      // not draw a box, so both must be offered.
      final shapes = [
        _perspective([
          VanishingPointAt(_point(-500, 100)),
          VanishingPointAt(_point(500, 100)),
        ]),
        _perspective([VanishingPointTowards(dx: 0, dy: 1)]),
      ];

      expect(snapCandidatesAt(shapes, _point(0, 200)).length, 3);
    });

    test('a vanishing point under the stroke start is skipped, not crashed', () {
      final shapes = [
        _perspective([
          VanishingPointAt(_point(10, 10)),
          VanishingPointAt(_point(500, 100)),
        ]),
      ];

      expect(snapCandidatesAt(shapes, _point(10, 10)).length, 1);
    });

    test('picks the candidate closest in angle', () {
      final candidates = snapCandidatesAt([
        _perspective([
          VanishingPointTowards(dx: 1, dy: 0),
          VanishingPointTowards(dx: 0, dy: 1),
        ]),
      ], _point(0, 0));

      final horizontal = chooseSnapCandidate(candidates, dx: 0.97, dy: 0.24);
      final vertical = chooseSnapCandidate(candidates, dx: 0.24, dy: 0.97);

      expect(horizontal!.dx, closeTo(1, 1e-12));
      expect(vertical!.dy, closeTo(1, 1e-12));
    });

    test('a stroke drawn AWAY from the vanishing point picks the same ray', () {
      // A ray family is a set of lines, and a line has no forward.
      final candidates = snapCandidatesAt([
        _perspective([VanishingPointAt(_point(1000, 0))]),
      ], _point(0, 0));

      final towards = chooseSnapCandidate(candidates, dx: 1, dy: 0);
      final away = chooseSnapCandidate(candidates, dx: -1, dy: 0);

      expect(towards, isNotNull);
      expect(away, towards);
    });

    test('ties go to the earlier guide, every time', () {
      // Two guides naming the SAME direction: the choice must not depend on
      // how the doubles happened to round.
      final candidates = snapCandidatesAt([
        _perspective([VanishingPointAt(_point(0, -100))]),
        _perspective([VanishingPointTowards(dx: 0, dy: -1)]),
      ], _point(0, 0));

      expect(candidates.length, 2);
      for (var run = 0; run < 50; run += 1) {
        expect(chooseSnapCandidate(candidates, dx: 0, dy: -1), candidates.first);
      }
    });

    test('there is no threshold — an off-axis stroke still snaps', () {
      // A cutoff would make the same gesture snap sometimes and not others.
      final candidates = snapCandidatesAt([
        _perspective([VanishingPointTowards(dx: 1, dy: 0)]),
      ], _point(0, 0));

      expect(chooseSnapCandidate(candidates, dx: 0, dy: 1), isNotNull);
    });

    test('no candidates yields no lock', () {
      expect(chooseSnapCandidate(const [], dx: 1, dy: 0), isNull);
    });

    test('projection puts a point on the ray through the stroke start', () {
      final candidate = snapCandidatesAt([
        _perspective([VanishingPointAt(_point(100, 0))]),
      ], _point(0, 0)).single;

      _expectPoint(candidate.project(_point(40, 999)), 40, 0);
      _expectPoint(candidate.project(_point(-40, -999)), -40, 0);
    });
  });

  group('eye level', () {
    test('projects a point onto the horizon', () {
      final axis = GuideAxis(origin: _point(0, 100), angleDegrees: 0);

      _expectPoint(projectOntoAxis(axis, _point(250, 900)), 250, 100);
    });

    test('a dragged vanishing point lands on the eye level when constrained', () {
      final shape = _perspective([VanishingPointAt(_point(0, 0))]);

      _expectPoint(
        constrainedVanishingPointTarget(shape, _point(600, 480)),
        600,
        100,
      );
    });

    test('an unconstrained drag lands where it was dropped', () {
      final shape = _perspective(
        [VanishingPointAt(_point(0, 0))],
        constrainToEyeLevel: false,
      );

      _expectPoint(
        constrainedVanishingPointTarget(shape, _point(600, 480)),
        600,
        480,
      );
    });

    test('turning the constraint on does not move existing geometry', () {
      // The constraint binds the NEXT drag. Sweeping stored points onto the
      // horizon would have to throw away two-line definitions.
      final lines = VanishingPointFromLines(
        GuideLine(a: _point(0, 0), b: _point(10, 10)),
        GuideLine(a: _point(0, 10), b: _point(10, 0)),
      );
      final shape = _perspective([lines]);

      expect(shape.vanishingPoints.single, lines);
      expect(shape.vanishingPoints.single.resolve().position!.y, closeTo(5, 1e-9));
    });
  });

  // 유저 (guide-sym): 「소실점 아이레벨 고정 시 아이레벨을 움직이면 소실점도」 —
  // the other half of the constraint. The horizon's move is bound here, the
  // point's drag in `constrainedVanishingPointTarget`.
  group('movedEyeLevel', () {
    test('sliding the horizon carries the vanishing points with it', () {
      final shape = _perspective([VanishingPointAt(_point(300, 100))]);

      final moved = movedEyeLevel(shape, _horizon(50, 130, 0));

      _expectPoint(
        moved.vanishingPoints.single.resolve().position!,
        350,
        130,
      );
    });

    test('tilting the horizon turns them about its origin', () {
      final shape = _perspective([VanishingPointAt(_point(300, 100))]);

      final moved = movedEyeLevel(shape, _horizon(0, 100, 90));

      _expectPoint(moved.vanishingPoints.single.resolve().position!, 0, 400);
    });

    test('a carried point is still ON the horizon afterwards', () {
      // The invariant the flag names, checked rather than assumed: whatever
      // the motion, the point and its projection onto the new eye level are
      // the same place.
      final shape = _perspective([VanishingPointAt(_point(300, 100))]);

      for (final axis in [
        _horizon(50, 130, 0),
        _horizon(0, 100, 90),
        _horizon(-40, 20, 37),
      ]) {
        final moved = movedEyeLevel(shape, axis);
        final at = moved.vanishingPoints.single.resolve().position!;
        final onLine = projectOntoAxis(moved.eyeLevel, at);
        _expectPoint(onLine, at.x, at.y);
      }
    });

    test('a point at INFINITY turns with the horizon but does not slide', () {
      final shape = _perspective([VanishingPointTowards(dx: 0, dy: 1)]);

      final slid = movedEyeLevel(shape, _horizon(50, 130, 0));
      expect(slid.vanishingPoints.single, VanishingPointTowards(dx: 0, dy: 1));

      final tilted = movedEyeLevel(shape, _horizon(0, 100, 90));
      final turned = tilted.vanishingPoints.single as VanishingPointTowards;
      expect(turned.dx, closeTo(-1, 1e-9));
      expect(turned.dy, closeTo(0, 1e-9));
    });

    test('a two-line definition arrives as two moved lines', () {
      // ⛔Not flattened to the bare crossing: the lines the user drew are
      // what lets them grab one later and slide the convergence.
      final shape = _perspective([
        VanishingPointFromLines(
          GuideLine(a: _point(0, 0), b: _point(10, 10)),
          GuideLine(a: _point(0, 10), b: _point(10, 0)),
        ),
      ]);

      final moved = movedEyeLevel(shape, _horizon(50, 130, 0));

      final carried = moved.vanishingPoints.single as VanishingPointFromLines;
      _expectPoint(carried.first.a, 50, 30);
      _expectPoint(carried.first.b, 60, 40);
      _expectPoint(carried.second.a, 50, 40);
      _expectPoint(carried.second.b, 60, 30);
    });

    test('with the constraint off the horizon moves alone', () {
      // A deliberately-broken horizon is a real drawing.
      final shape = _perspective(
        [VanishingPointAt(_point(300, 100))],
        constrainToEyeLevel: false,
      );

      final moved = movedEyeLevel(shape, _horizon(50, 130, 25));

      expect(moved.eyeLevel, _horizon(50, 130, 25));
      _expectPoint(
        moved.vanishingPoints.single.resolve().position!,
        300,
        100,
      );
    });
  });
}
