import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/services/selection_affine.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/canvas/box_on_screen.dart';
import 'package:anicel/src/ui/canvas/float_warp.dart';
import 'package:anicel/src/ui/canvas/selection_drag.dart';
import 'package:anicel/src/ui/canvas/transform_box.dart';

/// Where the transform box stands on the screen, read without a selection
/// layer around it: [BoxOnScreen].
///
/// Both of these were lines nothing failed for while they lived inside the
/// layer's state — every test pressed a point dead on, and none looked at
/// a closed box in 메쉬.
void main() {
  const canvas = CanvasSize(width: 400, height: 300);
  final wall = canvas.pasteboardAt(PasteboardReach.whole);

  // Zoom 1 and no pan: a canvas point is its own screen point.
  BoxOnScreen onScreen({
    required TransformMode mode,
    required bool boxOpen,
  }) => BoxOnScreen(
    viewport: CanvasViewport(),
    pasteboard: wall,
    mode: mode,
    boxOpen: boxOpen,
    warp: FloatWarp(
      box: null,
      base: null,
      float: null,
      options: TransformToolOptions(mode: mode),
      pasteboard: wall.region,
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

  /// An OPEN box over a 100×50 float at (100,100), armed in [mode] with a
  /// 2×2 grid — so its cross, at the middle, sits on the grid's middle point.
  ({BoxOnScreen screen, TransformBox box}) openBox(TransformMode mode) {
    final box = TransformBox(
      affine: SelectionAffine(pivot: CanvasPoint(x: 150, y: 125)),
      baseWidth: 100,
      baseHeight: 50,
    )..warp.syncToMode(mode, columns: 2, rows: 2);
    final options = TransformToolOptions(
      mode: mode,
      meshColumns: 2,
      meshRows: 2,
    );
    return (
      screen: BoxOnScreen(
        viewport: CanvasViewport(),
        pasteboard: wall,
        mode: mode,
        boxOpen: true,
        warp: FloatWarp(
          box: box,
          base: (left: 100, top: 100, width: 100, height: 50),
          float: null,
          options: options,
          pasteboard: wall.region,
        ),
      ),
      box: box,
    );
  }

  Object? grabbed(BoxGrab? grab) => switch (grab) {
    null => null,
    HandleGrab(:final handle) => handle,
    WarpPointGrab(:final index) => index,
  };

  final zero = CanvasPoint(x: 0, y: 0);

  // F-262 (유저 2026-10-02: 「보이는 만큼 존재하도록」). ↩️A grid point was
  // grabbed anywhere inside a 16px slack; it is the 9px square drawn for it.
  test('a grid point is grabbed on the square drawn for it — off its '
      'middle, and not beside it', () {
    final (:screen, :box) = openBox(TransformMode.mesh);

    expect(grabbed(screen.grabAt(const Offset(104, 97), box)), 0);
    expect(grabbed(screen.grabAt(const Offset(146, 103), box)), 1);
    expect(
      grabbed(screen.grabAt(const Offset(125, 110), box)),
      TransformHandle.inside,
      reason: 'between the points is the move, as inside any box',
    );
  });

  test('the cross drawn over a grid point is the cross — what is on top '
      'is what is grabbed', () {
    final (:screen, :box) = openBox(TransformMode.mesh);

    expect(
      grabbed(screen.grabAt(const Offset(150, 125), box)),
      TransformHandle.anchor,
    );
  });

  // 🚨F-412 (유저 2026-10-19): 「자유변형으로 그림 크게 조정하면, 사각형 도구
  // ui 밖을 클릭한게 아닌데도 회전이 작동함. 그림 조정되기 전 박스를
  // 기준으로 작동해서 그 밖을 회전으로 삼아버리는 버그인듯」.
  test('a 퍼스 quad pulled past its box is moved inside it and turned '
      'outside it — the quad drawn, not the box it left', () {
    final (:screen, :box) = openBox(TransformMode.perspective);
    // The top-right corner pulled 60 out: the quad's right edge runs from
    // (260,100) to (200,150).
    box.warp.corners = [zero, CanvasPoint(x: 60, y: 0), zero, zero];

    expect(
      screen.transformChrome(box.affine, 100, 50)!.box,
      contains(const Offset(260, 100)),
      reason: 'the premise: the quad is what is drawn',
    );
    expect(
      grabbed(screen.grabAt(const Offset(210, 110), box)),
      TransformHandle.inside,
      reason: 'inside the quad, past the box it was pulled from',
    );
    expect(
      grabbed(screen.grabAt(const Offset(300, 110), box)),
      TransformHandle.rotate,
      reason: 'outside the quad is the turn',
    );
  });

  test('a 메쉬 grid pulled past its box is moved inside its boundary', () {
    final (:screen, :box) = openBox(TransformMode.mesh);
    // The bottom-right point (row 2, column 2) pulled out to (260,190).
    box.warp.mesh = [
      for (var i = 0; i < 8; i += 1) zero,
      CanvasPoint(x: 60, y: 40),
    ];

    expect(
      grabbed(screen.grabAt(const Offset(210, 160), box)),
      TransformHandle.inside,
    );
    expect(
      grabbed(screen.grabAt(const Offset(300, 110), box)),
      TransformHandle.rotate,
      reason: 'and outside it is the turn, as for every box',
    );
  });
}
