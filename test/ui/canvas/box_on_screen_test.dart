import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/canvas/box_on_screen.dart';
import 'package:anicel/src/ui/canvas/float_warp.dart';
import 'package:anicel/src/ui/canvas/selection_drag.dart';

/// Where the transform box stands on the screen, read without a selection
/// layer around it: [BoxOnScreen].
///
/// Both of these were lines nothing failed for while they lived inside the
/// layer's state — every test pressed a point dead on, and none looked at
/// a closed box in 메쉬.
void main() {
  const canvas = CanvasSize(width: 400, height: 300);

  // Zoom 1 and no pan: a canvas point is its own screen point.
  BoxOnScreen onScreen({
    required TransformMode mode,
    required bool boxOpen,
  }) => BoxOnScreen(
    viewport: CanvasViewport(),
    canvasSize: canvas,
    mode: mode,
    boxOpen: boxOpen,
    warp: FloatWarp(
      box: null,
      float: null,
      options: TransformToolOptions(mode: mode),
      pasteboard: canvas.pasteboardRegion,
    ),
  );

  const corners = [
    TransformHandle.topLeft,
    TransformHandle.topRight,
    TransformHandle.bottomRight,
    TransformHandle.bottomLeft,
  ];

  test('a closed box offers its corners whatever the mode — something has '
      'to be grabbable to open one', () {
    for (final mode in TransformMode.values) {
      expect(
        onScreen(mode: mode, boxOpen: false).scaleHandles,
        containsAll(corners),
        reason: '$mode',
      );
    }
    expect(
      onScreen(mode: TransformMode.mesh, boxOpen: true).scaleHandles,
      isEmpty,
      reason: 'an open 메쉬 box is held by its grid points',
    );
  });

  test('a grid point is grabbed anywhere inside the hit slack, not only '
      'dead on', () {
    final box = onScreen(mode: TransformMode.mesh, boxOpen: true);
    final points = [CanvasPoint(x: 100, y: 100)];

    expect(box.hitTestPlacedPoint(const Offset(110, 100), points), 0);
    expect(
      box.hitTestPlacedPoint(
        const Offset(100 + BoxOnScreen.handleHitRadius + 1, 100),
        points,
      ),
      isNull,
    );
  });
}
