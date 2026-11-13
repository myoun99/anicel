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

  /// A box over a 100×50 float at (100,100), armed in [mode] with a 2×2
  /// grid — so its cross, at the middle, sits on the grid's middle point.
  /// Whether anything has opened it is not this view's to know.
  ({BoxOnScreen screen, TransformBox box}) boxIn(TransformMode mode) {
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
      // Zoom 1 and no pan: a canvas point is its own screen point.
      screen: BoxOnScreen(
        viewport: CanvasViewport(),
        pasteboard: wall,
        mode: mode,
        warp: FloatWarp(
          box: box,
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

  const corners = [
    TransformHandle.topLeft,
    TransformHandle.topRight,
    TransformHandle.bottomRight,
    TransformHandle.bottomLeft,
  ];
  const edges = [
    TransformHandle.topEdge,
    TransformHandle.rightEdge,
    TransformHandle.bottomEdge,
    TransformHandle.leftEdge,
  ];

  // 🗣️F-586 (유저 2026-11-12): 「매쉬변형, 변형시작해야 내부 사각형들 뜨는데,
  // 그냥 매쉬변형인 상태면 뜨도록」. ↩️A box not open yet was lent its four
  // corners whatever the mode, for want of a grid to open it by.
  test('the grips are the mode\'s and nothing is lent — a 메쉬 box is held '
      'by its grid, a 퍼스 quad by its corners and its edges', () {
    expect(boxIn(TransformMode.normal).screen.scaleHandles, [
      ...corners,
      ...edges,
    ]);
    expect(boxIn(TransformMode.perspective).screen.scaleHandles, edges);
    expect(boxIn(TransformMode.mesh).screen.scaleHandles, isEmpty);

    expect(
      boxIn(TransformMode.mesh).screen.transformChrome()!.handles,
      hasLength(9),
      reason: 'the 2×2 grid\'s nine points, and no grip beside them',
    );
    expect(
      boxIn(TransformMode.perspective).screen.transformChrome()!.handles,
      hasLength(8),
      reason: 'the quad\'s four corners and its four edges',
    );
  });

  test('with no box there is nothing drawn and nothing to press', () {
    final none = BoxOnScreen(
      viewport: CanvasViewport(),
      pasteboard: wall,
      mode: TransformMode.mesh,
      warp: FloatWarp(
        box: null,
        float: null,
        options: const TransformToolOptions(mode: TransformMode.mesh),
        pasteboard: wall.region,
      ),
    );
    expect(none.transformChrome(), isNull);
    expect(none.grabAt(const Offset(150, 125)), isNull);
  });

  // F-262 (유저 2026-10-02: 「보이는 만큼 존재하도록」). ↩️A grid point was
  // grabbed anywhere inside a 16px slack; it is the 9px square drawn for it.
  test('a grid point is grabbed on the square drawn for it — off its '
      'middle, and not beside it', () {
    final screen = boxIn(TransformMode.mesh).screen;

    expect(grabbed(screen.grabAt(const Offset(104, 97))), 0);
    expect(grabbed(screen.grabAt(const Offset(146, 103))), 1);
    expect(
      grabbed(screen.grabAt(const Offset(125, 110))),
      TransformHandle.inside,
      reason: 'between the points is the move, as inside any box',
    );
  });

  test('the cross drawn over a grid point is the cross — what is on top '
      'is what is grabbed', () {
    final screen = boxIn(TransformMode.mesh).screen;

    expect(
      grabbed(screen.grabAt(const Offset(150, 125))),
      TransformHandle.anchor,
    );
  });

  // 🚨F-412 (유저 2026-10-19): 「자유변형으로 그림 크게 조정하면, 사각형 도구
  // ui 밖을 클릭한게 아닌데도 회전이 작동함. 그림 조정되기 전 박스를
  // 기준으로 작동해서 그 밖을 회전으로 삼아버리는 버그인듯」.
  test('a 퍼스 quad pulled past its box is moved inside it and turned '
      'outside it — the quad drawn, not the box it left', () {
    final (:screen, :box) = boxIn(TransformMode.perspective);
    // The top-right corner pulled 60 out: the quad's right edge runs from
    // (260,100) to (200,150).
    box.warp.corners = [zero, CanvasPoint(x: 60, y: 0), zero, zero];

    expect(
      screen.transformChrome()!.box,
      contains(const Offset(260, 100)),
      reason: 'the premise: the quad is what is drawn',
    );
    expect(
      grabbed(screen.grabAt(const Offset(210, 110))),
      TransformHandle.inside,
      reason: 'inside the quad, past the box it was pulled from',
    );
    expect(
      grabbed(screen.grabAt(const Offset(300, 110))),
      TransformHandle.rotate,
      reason: 'outside the quad is the turn',
    );
  });

  test('a 메쉬 grid pulled past its box is moved inside its boundary', () {
    final (:screen, :box) = boxIn(TransformMode.mesh);
    // The bottom-right point (row 2, column 2) pulled out to (260,190).
    box.warp.mesh = [
      for (var i = 0; i < 8; i += 1) zero,
      CanvasPoint(x: 60, y: 40),
    ];

    expect(
      grabbed(screen.grabAt(const Offset(210, 160))),
      TransformHandle.inside,
    );
    expect(
      grabbed(screen.grabAt(const Offset(300, 110))),
      TransformHandle.rotate,
      reason: 'and outside it is the turn, as for every box',
    );
  });
}
