import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/services/guide_geometry.dart';
import 'package:anicel/src/ui/canvas/guide_overlay.dart';

/// 🚨★★★유저 (guide-sym): 「소실점 아이레벨 고정시, **아이레벨 움직이면
/// 소실점도 움직이도록. 로직부터 통일**」.
///
/// Dragging the horizon used to move the horizon and nothing else, so a
/// perspective with the constraint ON came out of the drag with its points
/// off the very line the constraint says they live on.
void main() {
  const id = GuideId('per');

  PerspectiveShape shape({
    bool constrain = true,
    double eyeY = 100,
    double angle = 0,
  }) => PerspectiveShape(
    eyeLevel: GuideAxis(
      origin: CanvasPoint(x: 100, y: eyeY),
      angleDegrees: angle,
    ),
    constrainToEyeLevel: constrain,
    vanishingPoints: [
      VanishingPointAt(CanvasPoint(x: 40, y: eyeY)),
      VanishingPointAt(CanvasPoint(x: 260, y: eyeY)),
    ],
  );

  CutGuides guidesOf(PerspectiveShape s) => CutGuides(
    guides: [DrawingGuide(id: id, name: '퍼스 1', shape: s)],
  );

  PerspectiveShape after(CutGuides guides) =>
      guides.guides.single.shape as PerspectiveShape;

  /// The signed distance of [point] from [axis] — zero means ON the line.
  double offAxis(GuideAxis axis, CanvasPoint point) {
    final projected = projectOntoAxis(axis, point);
    final dx = point.x - projected.x;
    final dy = point.y - projected.y;
    return dx * dx + dy * dy;
  }

  test('the premise: the points start ON the horizon', () {
    final s = shape();
    for (final point in s.vanishingPoints) {
      expect(
        offAxis(s.eyeLevel, (point.resolve().position)!),
        closeTo(0, 1e-9),
      );
    }
  });

  test('dragging the horizon DOWN carries the points with it', () {
    final handle = guideHandles(
      guidesOf(shape()),
    ).firstWhere((h) => h.kind == GuideHandleKind.origin);
    final moved = after(
      dragGuideHandle(guidesOf(shape()), handle, CanvasPoint(x: 100, y: 160)),
    );

    expect(moved.eyeLevel.origin.y, closeTo(160, 1e-9));
    for (final point in moved.vanishingPoints) {
      final at = point.resolve().position!;
      expect(at.y, closeTo(160, 1e-9), reason: '「아이레벨 움직이면 소실점도 움직이도록」');
      expect(
        offAxis(moved.eyeLevel, at),
        closeTo(0, 1e-9),
        reason: 'and they are still ON it',
      );
    }
    // ⚠️Their SPACING along the line is what a rigid motion keeps and a
    // re-projection would not.
    expect(
      moved.vanishingPoints.first.resolve().position!.x,
      closeTo(40, 1e-9),
    );
    expect(
      moved.vanishingPoints.last.resolve().position!.x,
      closeTo(260, 1e-9),
    );
  });

  test('rotating the horizon turns the points about its origin', () {
    final handle = guideHandles(
      guidesOf(shape()),
    ).firstWhere((h) => h.kind == GuideHandleKind.eyeLevelAngle);
    // Straight up from the origin: a quarter turn.
    final moved = after(
      dragGuideHandle(guidesOf(shape()), handle, CanvasPoint(x: 100, y: 0)),
    );

    for (final point in moved.vanishingPoints) {
      expect(
        offAxis(moved.eyeLevel, point.resolve().position!),
        closeTo(0, 1e-6),
        reason: 'still on the line after it turned',
      );
    }
  });

  test('⛔with the constraint OFF only the horizon moves', () {
    final s = shape(constrain: false);
    final handle = guideHandles(
      guidesOf(s),
    ).firstWhere((h) => h.kind == GuideHandleKind.origin);
    final moved = after(
      dragGuideHandle(guidesOf(s), handle, CanvasPoint(x: 100, y: 160)),
    );

    expect(moved.eyeLevel.origin.y, closeTo(160, 1e-9));
    for (final point in moved.vanishingPoints) {
      expect(
        point.resolve().position!.y,
        closeTo(100, 1e-9),
        reason: 'that is what turning the switch off means',
      );
    }
  });

  test('a line-defined point keeps its LINES', () {
    // ⛔The cost `constrainedVanishingPointTarget` refuses to pay: a sweep
    // onto the horizon would replace this with a bare point and throw the
    // user's two lines away. A rigid motion moves the lines instead.
    final s = PerspectiveShape(
      eyeLevel: GuideAxis(origin: CanvasPoint(x: 100, y: 100), angleDegrees: 0),
      vanishingPoints: [
        VanishingPointFromLines(
          GuideLine(a: CanvasPoint(x: 0, y: 90), b: CanvasPoint(x: 40, y: 100)),
          GuideLine(
            a: CanvasPoint(x: 0, y: 110),
            b: CanvasPoint(x: 40, y: 100),
          ),
        ),
      ],
    );
    final handle = guideHandles(
      guidesOf(s),
    ).firstWhere((h) => h.kind == GuideHandleKind.origin);
    final moved = after(
      dragGuideHandle(guidesOf(s), handle, CanvasPoint(x: 100, y: 160)),
    );

    expect(
      moved.vanishingPoints.single,
      isA<VanishingPointFromLines>(),
      reason: 'still defined by the lines the user drew',
    );
    expect(
      moved.vanishingPoints.single.resolve().position!.y,
      closeTo(160, 1e-6),
      reason: 'and the lines moved, so their meeting point did',
    );
  });
}
