import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/ui/brush/guide_panels.dart';

/// The two guide factories the library list mints from — nothing named
/// them (the audit's untested-file pass, 2026-09-05).
///
/// Both are about where a guide is BORN, which is what the user sees the
/// instant they press add: a symmetry axis through the middle, and a
/// two-pointer whose vanishing points sit outside the frame — a two-pointer
/// with both points on the paper is a fish-eye.
void main() {
  const canvas = CanvasSize(width: 1920, height: 1080);

  test('🚨a fresh symmetry guide stands in the MIDDLE', () {
    final guide = newSymmetryGuide(const GuideId('s-1'), canvas, 'Symmetry 1');
    final shape = guide.shape as SymmetryShape;

    expect(shape.axis.origin.x, 960);
    expect(shape.axis.origin.y, 540);
  });

  test('🚨its axis reads 90° — GuideAxis measures the LINE, and the eye '
      'level it shares a type with is horizontal at 0°, so a mirror down '
      'the middle is the perpendicular one', () {
    final guide = newSymmetryGuide(const GuideId('s-1'), canvas, 'S');

    expect((guide.shape as SymmetryShape).axis.angleDegrees, 90);
  });

  test('the name it is given is the name it wears', () {
    expect(
      newSymmetryGuide(const GuideId('s-1'), canvas, '좌우 대칭').name,
      '좌우 대칭',
    );
  });

  test('a fresh perspective guide puts its horizon through the middle', () {
    final guide = newPerspectiveGuide(
      const GuideId('p-1'),
      canvas,
      'Perspective 1',
    );
    final shape = guide.shape as PerspectiveShape;

    for (final point in shape.vanishingPoints) {
      expect(
        point.resolve().y,
        540,
        reason: 'both points sit on one horizon, or it is not a horizon',
      );
    }
  });

  test('🚨its two vanishing points sit OUTSIDE the frame — a two-pointer '
      'with both points on the paper is a fish-eye', () {
    final guide = newPerspectiveGuide(const GuideId('p-1'), canvas, 'P');
    final shape = guide.shape as PerspectiveShape;

    expect(shape.vanishingPoints, hasLength(2));
    expect(
      shape.vanishingPoints.first.resolve().x,
      lessThan(0),
      reason: 'well off the left edge',
    );
    expect(
      shape.vanishingPoints.last.resolve().x,
      greaterThan(canvas.width),
      reason: 'well off the right edge',
    );
  });

  test('the two points are placed symmetrically about the frame', () {
    final guide = newPerspectiveGuide(const GuideId('p-1'), canvas, 'P');
    final shape = guide.shape as PerspectiveShape;
    final left = shape.vanishingPoints.first.resolve().x;
    final right = shape.vanishingPoints.last.resolve().x;

    expect(
      (canvas.width / 2) - left,
      closeTo(right - (canvas.width / 2), 0.001),
    );
  });

  test('a TALL canvas gets its own middle, not the last one\'s', () {
    const tall = CanvasSize(width: 400, height: 2000);
    final symmetry =
        newSymmetryGuide(const GuideId('s-1'), tall, 'S').shape
            as SymmetryShape;
    final perspective =
        newPerspectiveGuide(const GuideId('p-1'), tall, 'P').shape
            as PerspectiveShape;

    expect(symmetry.axis.origin.x, 200);
    expect(symmetry.axis.origin.y, 1000);
    expect(perspective.vanishingPoints.first.resolve().y, 1000);
  });
}
