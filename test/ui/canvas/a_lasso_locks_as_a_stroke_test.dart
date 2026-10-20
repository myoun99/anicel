import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/ui/canvas/selection_drag.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️I-110 (유저 2026-10-18): 「스트로크시 쉬프트 통한 스냅기능, 더 확장해서
/// 선택도구의 올가미로 선택할때도 법 통일적용해서 … 프리핸드로 하는 모든것들도
/// 스냅되도록」 — a lasso traced by any verb is locked by the stroke's own
/// lock: Shift's eight ways while it is held, the snapping perspectives'
/// rays where it is not (I-110-Q2 「따른다」); and on the select tool a
/// Shift held from before the press is the fold's (I-110-Q1 「누른 시점으로
/// 가른다」).
void main() {
  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  MarqueeDrag lassoAt(
    CanvasPoint at, {
    CutGuides? guides,
    SelectionCombineMode? combine,
    bool shiftAtThePress = false,
  }) => MarqueeDrag(
    pointer: 1,
    shapeKind: CanvasShapeKind.lasso,
    before: null,
    at: at,
    guides: guides ?? CutGuides(),
    zoom: 1,
    combine: combine,
    shiftAtThePress: shiftAtThePress,
  );

  List<(double, double)> placesOf(Iterable<CanvasPoint> points) => [
    for (final point in points) (point.x, point.y),
  ];

  test('a Shift pressed while the lasso runs locks it from where the hand '
      'stands to one of the eight ways, as a stroke\'s', () {
    final drag = lassoAt(p(100, 100))
      ..update(p(130, 110))
      ..update(p(160, 140))
      ..update(p(200, 150), shift: true)
      ..update(p(240, 156), shift: true)
      ..update(p(280, 160), shift: true);

    expect(placesOf(drag.openTrail), [
      (100.0, 100.0),
      (130.0, 110.0),
      (160.0, 140.0),
      (200.0, 140.0),
      (240.0, 140.0),
      (280.0, 140.0),
    ]);
  });

  test('let go, the lasso goes on free from where it got to', () {
    final drag = lassoAt(p(100, 100))
      ..update(p(140, 108), shift: true)
      ..update(p(160, 130));

    expect(placesOf(drag.openTrail), [
      (100.0, 100.0),
      (140.0, 100.0),
      (160.0, 130.0),
    ]);
  });

  test('🗣️I-110-Q1: the Shift the FOLD took at the press locks nothing — '
      'until it is let go and pressed again', () {
    final drag = lassoAt(
      p(100, 100),
      combine: SelectionCombineMode.add,
      shiftAtThePress: true,
    );
    drag
      ..update(p(140, 110), shift: true)
      ..update(p(180, 130))
      ..update(p(220, 140), shift: true)
      ..update(p(260, 146), shift: true);

    expect(placesOf(drag.openTrail), [
      (100.0, 100.0),
      (140.0, 110.0),
      (180.0, 130.0),
      (220.0, 130.0),
      (260.0, 130.0),
    ]);
    expect(drag.combine, SelectionCombineMode.add);
  });

  test('a verb that folds nothing is locked from the press by a Shift held '
      'before it, as a stroke is', () {
    final drag = lassoAt(p(100, 100), shiftAtThePress: true)
      ..update(p(140, 110), shift: true)
      ..update(p(180, 112), shift: true);

    expect(placesOf(drag.openTrail), [
      (100.0, 100.0),
      (140.0, 100.0),
      (180.0, 100.0),
    ]);
  });

  test('🗣️I-110-Q2: with no Shift a snapping perspective locks the lasso '
      'onto its rays', () {
    final guides = CutGuides(
      guides: [
        DrawingGuide(
          id: const GuideId('p1'),
          name: 'p1',
          shape: PerspectiveShape(
            vanishingPoints: [VanishingPointAt(p(150, 60))],
            eyeLevel: GuideAxis(origin: p(80, 60), angleDegrees: 0),
            snapEnabled: true,
          ),
        ),
      ],
    );
    final drag = lassoAt(p(10, 10), guides: guides)
      ..update(p(90, 35))
      ..update(p(120, 45));

    final traced = drag.openTrail;
    expect(traced, hasLength(3));
    for (final point in traced.skip(1)) {
      // On the ray from the press to the vanishing point (140, 50).
      expect((point.x - 10) * 50 - (point.y - 10) * 140, closeTo(0, 1e-6));
    }
  });

  test('what the lock still held when the hand lifted lands on the path', () {
    final drag = lassoAt(p(100, 100))..update(p(104, 100.5), shift: true);
    expect(
      placesOf(drag.openTrail),
      [(100.0, 100.0)],
      reason: 'too short a travel to have chosen a way: the point is held',
    );

    drag.lift();

    expect(placesOf(drag.openTrail), [(100.0, 100.0), (104.0, 100.0)]);
  });
}
