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
}
