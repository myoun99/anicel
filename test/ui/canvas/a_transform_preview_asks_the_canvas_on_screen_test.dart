import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';

/// While a transform drags, its preview resamples only the canvas the view
/// shows, padded — the bounds of the view's four corners on the canvas,
/// since the canvas turns and flips.
void main() {
  test('a view shows its own width across and its height down, padded', () {
    expect(
      canvasShownPadded(
        const Size(800, 300),
        (corner) => CanvasPoint(x: corner.x, y: corner.y),
        96,
      ),
      (left: -96.0, top: -96.0, right: 896.0, bottom: 396.0),
    );
  });

  test('a view turned a quarter shows its height across and its width down',
      () {
    expect(
      canvasShownPadded(
        const Size(800, 300),
        (corner) => CanvasPoint(x: corner.y, y: -corner.x),
        0,
      ),
      (left: 0.0, top: -800.0, right: 300.0, bottom: 0.0),
    );
  });

}
