import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/canvas_traces.dart';

/// Which of every canvas's traces the window's verbs answer for: the one
/// the user is in the middle of — of those open, the one last added to or
/// taken back from (F-380: a viewer keeps a trace of its own).
void main() {
  late CanvasSelectionCommands canvas;
  late CanvasSelectionCommands viewer;
  late CanvasTraces traces;

  setUp(() {
    canvas = CanvasSelectionCommands();
    viewer = CanvasSelectionCommands();
    traces = CanvasTraces([canvas, viewer]);
  });

  CanvasPoint at(double x) => CanvasPoint(x: x, y: x);

  test('the open trace is the one last added to, wherever it is', () {
    expect(traces.open, isNull);

    viewer.addPolygonPoint(at(1));
    canvas.addPolygonPoint(at(2));
    expect(traces.open, same(canvas));

    viewer.addPolygonPoint(at(3));
    expect(traces.open, same(viewer));
  });

  test('…or the one last taken back from', () {
    canvas
      ..addPolygonPoint(at(1))
      ..addPolygonPoint(at(2));
    viewer.addPolygonPoint(at(3));

    canvas.undoPolygonPoint();
    expect(traces.open, same(canvas));
  });

  test('a redo goes to the trace last taken back from, open or not', () {
    canvas.addPolygonPoint(at(1));
    viewer
      ..addPolygonPoint(at(2))
      ..undoPolygonPoint();
    expect(traces.open, same(canvas), reason: 'the viewer has none open');
    expect(traces.toRedo, same(viewer));

    canvas
      ..addPolygonPoint(at(3))
      ..undoPolygonPoint();
    expect(traces.toRedo, same(canvas));

    viewer.redoPolygonPoint();
    expect(traces.open, same(viewer), reason: 'put back is touched too');
  });
}
