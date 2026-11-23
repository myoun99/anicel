import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/ui/canvas/selection_drag.dart';
import 'package:flutter_test/flutter_test.dart';

/// A lasso takes every point the OS saw ([PenPath] — a move a busy UI
/// merged hands it all of them, one step each), so a long one taken in a
/// stall grows by hundreds of points a message. ⛔It copied its whole trail
/// on every point (card every-path-takes-every-point-the-os-saw ⓐ⑧): a
/// message's points cost their count times the trail's length, and the
/// stall that merged them is exactly when the UI has none to spare.
///
/// The ants still read a fresh trail each time it grew, by identity
/// (`SelectionAntsPainter.props`) — the trail is copied once when it is
/// read, not once a point.
void main() {
  CanvasPoint p(double x, double y) => CanvasPoint(x: x, y: y);

  MarqueeDrag lassoAt(CanvasPoint at) => MarqueeDrag(
    pointer: 1,
    shapeKind: CanvasShapeKind.lasso,
    before: null,
    at: at,
    guides: CutGuides(),
    zoom: 1,
  );

  test('the trail the ants read is the same until the lasso grows, a new '
      'one after — and the one read before stays as it was', () {
    final drag = lassoAt(p(0, 0))
      ..update(p(10, 0))
      ..update(p(10, 10));
    final read = drag.openTrail;

    expect(identical(drag.openTrail, read), isTrue,
        reason: 'nothing grew: the ants have nothing new to draw');

    drag.update(p(0, 10));

    expect(identical(drag.openTrail, read), isFalse,
        reason: 'it grew: the ants must see a new trail');
    expect(read, hasLength(3), reason: 'a trail handed out never changes');
    expect(drag.openTrail, hasLength(4));
  });

  test('a message of many points costs as many steps, not as many copies '
      'of the trail', () {
    Duration traced(int points) {
      final drag = lassoAt(p(0, 0));
      final clock = Stopwatch()..start();
      for (var i = 1; i <= points; i++) {
        drag.update(p(i.toDouble(), (i % 7).toDouble()));
      }
      expect(drag.openTrail, hasLength(points + 1));
      return clock.elapsed;
    }

    Duration fastest(int points) => [
      for (var run = 0; run < 3; run++) traced(points),
    ].reduce((a, b) => a < b ? a : b);

    fastest(2000); // warms the compiler
    final short = fastest(2000);
    final long = fastest(20000);

    // Ten times the points: ten times the time if each is one step, a
    // hundred if each copies the trail. The line sits between with room
    // for a loaded machine either way.
    expect(
      long.inMicroseconds,
      lessThan(short.inMicroseconds * 30 + 2000),
      reason: '2000 points took $short, 20000 took $long',
    );
  });
}
