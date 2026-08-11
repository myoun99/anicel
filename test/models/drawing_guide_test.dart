import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:flutter_test/flutter_test.dart';

CanvasPoint _point(double x, double y) => CanvasPoint(x: x, y: y);

GuideAxis _verticalAxis({double x = 100, double y = 100}) =>
    GuideAxis(origin: _point(x, y), angleDegrees: 90);

DrawingGuide _symmetry({
  String id = 'sym',
  int lineCount = 2,
  bool lineSymmetry = true,
}) => DrawingGuide(
  id: GuideId(id),
  name: 'Symmetry',
  shape: SymmetryShape(
    axis: _verticalAxis(),
    lineCount: lineCount,
    lineSymmetry: lineSymmetry,
  ),
);

DrawingGuide _perspective({String id = 'persp', bool snapEnabled = true}) =>
    DrawingGuide(
      id: GuideId(id),
      name: 'Perspective',
      shape: PerspectiveShape(
        vanishingPoints: [VanishingPointAt(_point(500, 100))],
        eyeLevel: GuideAxis(origin: _point(0, 100), angleDegrees: 0),
        snapEnabled: snapEnabled,
      ),
    );

void main() {
  group('HomogeneousPoint', () {
    test('a finite point names the direction towards it', () {
      const vanishing = HomogeneousPoint.at(100, 0);

      final direction = vanishing.directionFrom(_point(0, 0));

      expect(direction, isNotNull);
      expect(direction!.dx, closeTo(1, 1e-12));
      expect(direction.dy, closeTo(0, 1e-12));
    });

    test('a point at infinity names the same direction from anywhere', () {
      const vanishing = HomogeneousPoint.towards(0, 3);

      final near = vanishing.directionFrom(_point(0, 0))!;
      final far = vanishing.directionFrom(_point(9999, -4242))!;

      expect(near.dx, closeTo(0, 1e-12));
      expect(near.dy, closeTo(1, 1e-12));
      expect(far.dx, closeTo(near.dx, 1e-12));
      expect(far.dy, closeTo(near.dy, 1e-12));
    });

    test('is infinite exactly when w is zero', () {
      expect(const HomogeneousPoint.towards(1, 0).isInfinite, isTrue);
      expect(const HomogeneousPoint.at(1, 0).isInfinite, isFalse);
      expect(const HomogeneousPoint.towards(1, 0).position, isNull);
      expect(const HomogeneousPoint(10, 20, 2).position, _point(5, 10));
    });

    test('a vanishing point under the stroke start names no direction', () {
      expect(const HomogeneousPoint.at(7, 7).directionFrom(_point(7, 7)), isNull);
    });

    test('a vanishing point far outside the canvas still yields a unit ray', () {
      // Squaring these before scaling would overflow to infinity and the
      // direction would come back NaN.
      const vanishing = HomogeneousPoint.at(1e170, 1e170);

      final direction = vanishing.directionFrom(_point(0, 0));

      expect(direction, isNotNull);
      final length =
          direction!.dx * direction.dx + direction.dy * direction.dy;
      expect(length, closeTo(1, 1e-9));
    });
  });

  group('VanishingPoint', () {
    test('two crossing lines meet at their intersection', () {
      final vanishing = VanishingPointFromLines(
        GuideLine(a: _point(0, 0), b: _point(10, 10)),
        GuideLine(a: _point(0, 10), b: _point(10, 0)),
      );

      final position = vanishing.resolve().position;

      expect(position, isNotNull);
      expect(position!.x, closeTo(5, 1e-9));
      expect(position.y, closeTo(5, 1e-9));
    });

    test('two PARALLEL lines resolve to a point at infinity', () {
      // The reason the sum type carries lines rather than a baked point:
      // parallel is not an error case here, it is the infinite vanishing
      // point falling out with no tolerance to tune.
      final vanishing = VanishingPointFromLines(
        GuideLine(a: _point(0, 0), b: _point(10, 0)),
        GuideLine(a: _point(0, 50), b: _point(10, 50)),
      );

      final resolved = vanishing.resolve();

      expect(resolved.isInfinite, isTrue);
      final direction = resolved.directionFrom(_point(3, 3))!;
      expect(direction.dy, closeTo(0, 1e-12));
      expect(direction.dx.abs(), closeTo(1, 1e-12));
    });

    test('a direction must be finite and non-zero', () {
      expect(() => VanishingPointTowards(dx: 0, dy: 0), throwsArgumentError);
      expect(
        () => VanishingPointTowards(dx: double.infinity, dy: 1),
        throwsArgumentError,
      );
      expect(
        () => VanishingPointTowards(dx: double.nan, dy: 1),
        throwsArgumentError,
      );
    });

    test('a vertical family is expressible exactly', () {
      // "세로 퍼스는 항상 수직" — this has to be exact, which is why the
      // direction case is first-class instead of two almost-parallel lines.
      final vertical = VanishingPointTowards(dx: 0, dy: 1);

      final direction = vertical.resolve().directionFrom(_point(42, -17))!;

      expect(direction.dx, 0);
      expect(direction.dy, 1);
    });

    test('round-trips through JSON in every variant', () {
      final variants = <VanishingPoint>[
        VanishingPointAt(_point(1, 2)),
        VanishingPointTowards(dx: 0, dy: 1),
        VanishingPointFromLines(
          GuideLine(a: _point(0, 0), b: _point(1, 1)),
          GuideLine(a: _point(0, 1), b: _point(1, 0)),
        ),
      ];

      for (final variant in variants) {
        expect(VanishingPoint.fromJson(variant.toJson()), variant);
      }
    });

    test('rejects an unknown variant tag', () {
      expect(
        () => VanishingPoint.fromJson({'type': 'somewhere'}),
        throwsArgumentError,
      );
    });
  });

  group('SymmetryShape', () {
    test('rejects counts outside 2…16', () {
      expect(
        () => SymmetryShape(axis: _verticalAxis(), lineCount: 1),
        throwsArgumentError,
      );
      expect(
        () => SymmetryShape(axis: _verticalAxis(), lineCount: 17),
        throwsArgumentError,
      );
    });

    test('rejects an odd count while mirroring', () {
      expect(
        () => SymmetryShape(
          axis: _verticalAxis(),
          lineCount: 3,
          lineSymmetry: true,
        ),
        throwsArgumentError,
      );
      expect(
        SymmetryShape(
          axis: _verticalAxis(),
          lineCount: 3,
          lineSymmetry: false,
        ).lineCount,
        3,
      );
    });

    test('turning mirroring on from an odd count steps down, never up', () {
      final rotational = SymmetryShape(
        axis: _verticalAxis(),
        lineCount: 15,
        lineSymmetry: false,
      );

      final mirrored = rotational.copyWith(lineSymmetry: true);

      expect(mirrored.lineCount, 14);
      expect(mirrored.lineCount, lessThanOrEqualTo(maxSymmetryLineCount));
    });

    test('turning mirroring on at the ceiling stays at the ceiling', () {
      final rotational = SymmetryShape(
        axis: _verticalAxis(),
        lineCount: maxSymmetryLineCount,
        lineSymmetry: false,
      );

      expect(rotational.copyWith(lineSymmetry: true).lineCount, 16);
    });

    test('round-trips through JSON', () {
      final shape = SymmetryShape(
        axis: GuideAxis(origin: _point(3, 4), angleDegrees: 33),
        lineCount: 6,
        lineSymmetry: true,
      );

      expect(GuideShape.fromJson(shape.toJson()), shape);
    });
  });

  group('PerspectiveShape', () {
    test('carries one to three vanishing points', () {
      GuideAxis eyeLevel() => GuideAxis(origin: _point(0, 0), angleDegrees: 0);

      expect(
        () => PerspectiveShape(vanishingPoints: [], eyeLevel: eyeLevel()),
        throwsArgumentError,
      );
      expect(
        () => PerspectiveShape(
          vanishingPoints: [
            VanishingPointAt(_point(1, 1)),
            VanishingPointAt(_point(2, 2)),
            VanishingPointAt(_point(3, 3)),
            VanishingPointAt(_point(4, 4)),
          ],
          eyeLevel: eyeLevel(),
        ),
        throwsArgumentError,
      );
    });

    test('round-trips through JSON', () {
      final shape = PerspectiveShape(
        vanishingPoints: [
          VanishingPointAt(_point(900, 100)),
          VanishingPointTowards(dx: 0, dy: 1),
        ],
        eyeLevel: GuideAxis(origin: _point(0, 100), angleDegrees: 2),
        snapEnabled: false,
        eyeLevelVisible: false,
        constrainToEyeLevel: false,
      );

      expect(GuideShape.fromJson(shape.toJson()), shape);
    });
  });

  group('CutGuides', () {
    test('the acting symmetry must exist and be a symmetry guide', () {
      expect(
        () => CutGuides(
          guides: [_symmetry()],
          activeSymmetryId: const GuideId('missing'),
        ),
        throwsArgumentError,
      );
      expect(
        () => CutGuides(
          guides: [_perspective()],
          activeSymmetryId: const GuideId('persp'),
        ),
        throwsArgumentError,
      );
    });

    test('deleting the acting guide clears the pointer instead of throwing', () {
      final guides = CutGuides(
        guides: [_symmetry(), _perspective()],
        activeSymmetryId: const GuideId('sym'),
      );

      final afterDelete = guides.copyWith(guides: [_perspective()]);

      expect(afterDelete.activeSymmetryId, isNull);
      expect(afterDelete.actingSymmetry, isNull);
    });

    test('acting symmetry ignores visibility', () {
      // A guide can steer the brush while its drawing is hidden — the same
      // way perspective snapping does.
      final guides = CutGuides(
        guides: [_symmetry().copyWith(visible: false)],
        activeSymmetryId: const GuideId('sym'),
      );

      expect(guides.actingSymmetry, isNotNull);
    });

    test('only one symmetry acts even when several are kept', () {
      final guides = CutGuides(
        guides: [
          _symmetry(id: 'a'),
          _symmetry(id: 'b'),
          _symmetry(id: 'c'),
        ],
        activeSymmetryId: const GuideId('b'),
      );

      expect(guides.symmetryGuides.length, 3);
      expect(guides.actingSymmetry, guides.guideFor(const GuideId('b'))!.shape);
    });

    test('snapping perspectives keep list order and skip switched-off ones', () {
      final guides = CutGuides(
        guides: [
          _perspective(id: 'a', snapEnabled: true),
          _perspective(id: 'b', snapEnabled: false),
          _perspective(id: 'c', snapEnabled: true),
        ],
      );

      expect(guides.snappingPerspectives.length, 2);
      expect(
        guides.snappingPerspectives.first,
        guides.guideFor(const GuideId('a'))!.shape,
      );
    });

    test('a dangling active pointer in a file loads as no active guide', () {
      final json = {
        'guides': [_perspective().toJson()],
        'activeSymmetry': const GuideId('gone').toJson(),
      };

      final loaded = CutGuides.fromJson(json);

      expect(loaded.guides.length, 1);
      expect(loaded.activeSymmetryId, isNull);
    });

    test('round-trips through JSON', () {
      final guides = CutGuides(
        guides: [_symmetry(lineCount: 4), _perspective()],
        activeSymmetryId: const GuideId('sym'),
      );

      expect(CutGuides.fromJson(guides.toJson()), guides);
    });
  });

  group('Cut guides', () {
    Cut cut({CutGuides? guides}) => Cut(
      id: const CutId('c1'),
      name: 'C1',
      layers: const [],
      duration: 12,
      canvasSize: const CanvasSize(width: 1920, height: 1080),
      guides: guides,
    );

    test('defaults to none and is omitted from JSON', () {
      final json = cut().toJson();

      expect(cut().guides.isEmpty, isTrue);
      expect(json.containsKey('guides'), isFalse);
    });

    test('a file written before guides existed loads guide-free', () {
      final legacy = cut().toJson()..remove('guides');

      expect(Cut.fromJson(legacy).guides.isEmpty, isTrue);
    });

    test('round-trips guides through JSON', () {
      final withGuides = cut(
        guides: CutGuides(
          guides: [_symmetry(), _perspective()],
          activeSymmetryId: const GuideId('sym'),
        ),
      );

      expect(Cut.fromJson(withGuides.toJson()).guides, withGuides.guides);
    });

    test('guides take part in cut equality', () {
      expect(cut(), cut());
      expect(cut(guides: CutGuides(guides: [_symmetry()])), isNot(cut()));
    });
  });
}
