import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/ui/canvas/selection_drag.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shape tool's 「비율 고정」 on the drag itself (유저 답 I-69-Q5): what
/// the drag traces with its ratio kept is what the ants show while it runs
/// AND what is drawn when it ends — one end point, read by all three.
void main() {
  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  MarqueeDrag pressedAt100(CanvasShapeKind kind) =>
      MarqueeDrag(pointer: 1, shapeKind: kind, before: null, at: p(100, 100));

  List<(double, double)> placesOf(Iterable<CanvasPoint> points) => [
    for (final point in points) (point.x, point.y),
  ];

  const square = [
    (100.0, 100.0),
    (200.0, 100.0),
    (200.0, 200.0),
    (100.0, 200.0),
  ];
  const asDragged = [
    (100.0, 100.0),
    (200.0, 100.0),
    (200.0, 150.0),
    (100.0, 150.0),
  ];

  test('a box keeping its ratio IS the square: its outline and its path', () {
    final drag = pressedAt100(CanvasShapeKind.rect)
      ..update(p(200, 150), keepsRatio: true);

    expect(placesOf(drag.shape()!.points), square);
    expect(placesOf(drag.path()!.points), square);
    expect(drag.path()!.closed, isTrue);
  });

  test('a line keeping its ratio is drawn — and SHOWN while it is dragged — '
      'along its way', () {
    final drag = pressedAt100(CanvasShapeKind.line)
      ..update(p(220, 130), keepsRatio: true);

    expect(placesOf(drag.path()!.points), [(100.0, 100.0), (220.0, 100.0)]);
    expect(
      placesOf(drag.openTrail),
      [(100.0, 100.0), (220.0, 100.0)],
      reason: 'the ants walk the line that will be drawn, not the hand',
    );
  });

  test('it is asked at every move: the ratio comes and goes under the '
      'hand', () {
    final drag = pressedAt100(CanvasShapeKind.rect)
      ..update(p(200, 150), keepsRatio: true)
      ..update(p(200, 150));
    expect(placesOf(drag.shape()!.points), asDragged);

    drag.update(p(200, 150), keepsRatio: true);
    expect(placesOf(drag.shape()!.points), square);
  });

  test('left unsaid, a move is where the hand is', () {
    final drag = pressedAt100(CanvasShapeKind.rect)..update(p(200, 150));

    expect(placesOf(drag.shape()!.points), asDragged);
  });

  test('the lasso is the hand\'s own path, kept or not', () {
    final drag = pressedAt100(CanvasShapeKind.lasso)
      ..update(p(130, 100), keepsRatio: true)
      ..update(p(130, 140), keepsRatio: true);

    expect(placesOf(drag.openTrail), [
      (100.0, 100.0),
      (130.0, 100.0),
      (130.0, 140.0),
    ]);
  });

  test('a drag is a pen\'s unless it is said to be a finger\'s, and has '
      'gone nowhere yet', () {
    final drag = pressedAt100(CanvasShapeKind.rect);

    expect(drag.byTouch, isFalse);
    expect(drag.screenTravel, 0);
  });
}
