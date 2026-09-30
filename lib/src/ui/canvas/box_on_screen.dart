import 'dart:ui' show Offset;

import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart';
import '../../services/canvas_selection_shape.dart';
import '../../services/selection_affine.dart';
import '../brush/transform_tool_options.dart';
import 'canvas_viewport_offset.dart';
import 'float_warp.dart';
import 'selection_ants_painter.dart' show SelectionTransformChrome;
import 'selection_drag.dart';
import 'transform_box.dart';

/// The transform box as the screen shows it: which handles it wears, where
/// each one stands, what a press lands on, and the chrome the ants painter
/// draws over it.
///
/// A view of the selection layer at one moment — the viewport, the canvas,
/// the armed mode, whether a box is open and the open warp — owning none of
/// them. Where the box puts the float on the CANVAS is [FloatWarp]; this is
/// where the box stands on the SCREEN.
class BoxOnScreen {
  const BoxOnScreen({
    required this.viewport,
    required this.canvasSize,
    required this.mode,
    required this.boxOpen,
    required this.warp,
  });

  final CanvasViewport viewport;
  final CanvasSize canvasSize;

  /// Which of 일반/퍼스/메쉬 is armed.
  final TransformMode mode;

  /// Whether a box is open — a closed one offers its corners whatever the
  /// mode ([scaleHandles]).
  final bool boxOpen;

  /// The open box over the float — where 퍼스 puts its quad corners.
  final FloatWarp warp;

  /// Screen-space hit slack around a handle (≥ touch-friendly).
  static const double handleHitRadius = 16;

  int? hitTestPlacedPoint(Offset local, List<CanvasPoint>? points) {
    if (points == null) {
      return null;
    }
    for (var i = 0; i < points.length; i += 1) {
      final mapped = viewport.canvasToViewportOffset(points[i]);
      if ((local - mapped).distance <= handleHitRadius) {
        return i;
      }
    }
    return null;
  }


  /// A base-local point mapped through [affine] into viewport space.
  Offset _mapLocalToViewport(SelectionAffine affine, CanvasPoint local) {
    final canvasPoint = affine.apply(
      CanvasPoint(x: affine.pivot.x + local.x, y: affine.pivot.y + local.y),
    );
    return viewport.canvasToViewportOffset(canvasPoint);
  }

  static const List<TransformHandle> _cornerHandles = [
    TransformHandle.topLeft,
    TransformHandle.topRight,
    TransformHandle.bottomRight,
    TransformHandle.bottomLeft,
  ];

  static const List<TransformHandle> _edgeHandles = [
    TransformHandle.topEdge,
    TransformHandle.rightEdge,
    TransformHandle.bottomEdge,
    TransformHandle.leftEdge,
  ];

  /// The two QUAD corners an edge handle carries in 퍼스 (F-42).
  ///
  /// Corner order is the quad's own — TL/TR/BR/BL, as
  /// [FloatWarp.stampRectCorners] builds it — so an edge is the pair that
  /// bounds it. Null for anything that is not an edge, which is how the
  /// caller falls through to the affine path for the rotate knob and the
  /// inside grab.
  static List<int>? edgeCornerPair(TransformHandle handle) =>
      switch (handle) {
        TransformHandle.topEdge => const [0, 1],
        TransformHandle.rightEdge => const [1, 2],
        TransformHandle.bottomEdge => const [2, 3],
        TransformHandle.leftEdge => const [3, 0],
        _ => null,
      };

  /// The scale handles the armed mode offers.
  ///
  /// 일반 shows the four corners and nothing else — TVPaint's rule, and
  /// the honest one: a mid-edge handle can only mean "stretch one axis",
  /// which is exactly what this mode does not do. Offering it and then
  /// scaling both axes anyway would be a control that lies.
  ///
  /// 퍼스 keeps the edges and drops the corners from THIS list — in that
  /// mode a corner is a quad point, hit-tested before this runs.
  ///
  /// 🚨THE EDGES ARE NO LONGER SCALE THERE EITHER (F-42, 유저 2026-08-29).
  /// They stay in this list because it decides what is DRAWN and grabbable;
  /// what a grab then means is decided at the press, where 퍼스 routes an
  /// edge to its two quad corners. Non-uniform scale in 퍼스 is now "drag
  /// the two corners", which is what the user asked for — the old
  /// one-axis scale could not move the edge off its own axis at all.
  ///
  /// With NO session open the corners are added back whatever the mode,
  /// because the mode describes what an OPEN box does and something has to
  /// be grabbable to open one. Otherwise 메쉬 — whose handles are grid
  /// points that do not exist until the box does — would be a mode you
  /// could select and then never enter.
  List<TransformHandle> get scaleHandles {
    final open = switch (mode) {
      // 🚨★★★**일반변형도 변 중앙을 잡는다** — 유저 2026-09-22: 「**일반변형도
      // 자유변형처럼 각 변 중앙에 버튼? 두도록. 자유변형이랑 법 통일**해서.
      // 이제 기본조작은 어떤 꼭짓점 편집하든 중심기준 크기변형이지만,
      // **수정자통한 조작이 변 중앙의 꼭짓점 조작이 필요**해진다는게 이유임」.
      //
      // ⛔Nothing else had to change: `_dragBoxHandle` already solves all
      // eight through `_solveScaleDrag`, and the edges were only ever
      // withheld from this mode.
      TransformMode.normal => const [..._cornerHandles, ..._edgeHandles],
      TransformMode.perspective => _edgeHandles,
      TransformMode.mesh => const <TransformHandle>[],
    };
    if (boxOpen) {
      return open;
    }
    return [
      ..._cornerHandles,
      ...open.where((handle) => !_cornerHandles.contains(handle)),
    ];
  }

  /// The transformed box as a canvas-space polygon (inside = translate).
  CanvasSelectionShape _transformedBoxShape(TransformBox box) =>
      _boxShapeFor(box.affine, box.baseWidth, box.baseHeight);

  /// The box as it stood when its session opened — the untouched rectangle
  /// the transform began from, in canvas space: the TRANSFORM TOOL's own
  /// silhouette, which the green 「기존 실루엣」 line is drawn along (I-38 ·
  /// F-231 ①).
  CanvasSelectionShape startSilhouette(TransformBox box) => _boxShapeFor(
    SelectionAffine(pivot: box.affine.pivot),
    box.baseWidth,
    box.baseHeight,
  );

  CanvasSelectionShape _boxShapeFor(
    SelectionAffine affine,
    double width,
    double height,
  ) {
    return CanvasSelectionShape([
      for (final corner in [
        CanvasPoint(x: -width / 2, y: -height / 2),
        CanvasPoint(x: width / 2, y: -height / 2),
        CanvasPoint(x: width / 2, y: height / 2),
        CanvasPoint(x: -width / 2, y: height / 2),
      ])
        affine.apply(
          CanvasPoint(
            x: affine.pivot.x + corner.x,
            y: affine.pivot.y + corner.y,
          ),
        ),
    ]);
  }

  /// Where [handle] stands on screen — the ONE answer the chrome draws and the
  /// press hits.
  ///
  /// 🚨F-42 (유저 2026-08-31): 「작동은 하는데 변형툴 ui의 사각형, 상하좌우
  /// 중앙의 사각형이 따라서 안움직임. 로직통일」. In 퍼스 an edge handle
  /// carries its two QUAD corners, but it was drawn and hit at the AFFINE
  /// box's edge, so once a corner moved the handle stayed behind on a box no
  /// longer shown. Its place is its quad edge's middle now; every other handle
  /// keeps the affine box's.
  Offset scaleHandleViewport(
    TransformHandle handle,
    SelectionAffine affine,
    double width,
    double height,
  ) {
    final corners = warp.placedCorners;
    final pair = edgeCornerPair(handle);
    if (corners != null && pair != null) {
      final a = viewport.canvasToViewportOffset(corners[pair[0]]);
      final b = viewport.canvasToViewportOffset(corners[pair[1]]);
      return (a + b) / 2;
    }
    return _mapLocalToViewport(affine, handleLocal(handle, width, height)!);
  }

  TransformHandle? hitTestTransformHandle(Offset local, TransformBox box) {
    final affine = box.affine;
    // ⚠️THE CROSS IS ON TOP, SO IT IS GRABBED FIRST. It is painted over
    // everything else, and 「what you see is what you grab」 is the only
    // rule that survives the user dragging it onto a scale handle — which
    // nothing stops them doing, because nothing clamps it.
    final anchor = viewport.canvasToViewportOffset(affine.anchorCanvas);
    if ((local - anchor).distance <= handleHitRadius) {
      return TransformHandle.anchor;
    }
    for (final handle in scaleHandles) {
      final position = scaleHandleViewport(
        handle,
        affine,
        box.baseWidth,
        box.baseHeight,
      );
      if ((local - position).distance <= handleHitRadius) {
        return handle;
      }
    }
    final canvasPoint = viewport.viewportOffsetToCanvas(local);
    if (_transformedBoxShape(box).containsPoint(canvasPoint)) {
      return TransformHandle.inside;
    }
    // 🚨★★★**OUTSIDE THE BOX IS THE ROTATION.** 유저 2026-09-22: 「우선
    // **사각형 밖 조작은 회전으로 통하도록**. 지금 있는 **회전 꼭짓점은
    // 잔재 싹 삭제**하고. 사각형 내부 조작은 지금처럼 위치이동」.
    //
    // ↩️A knob stuck out of the top edge and was hit-tested first. It is
    // gone with everything that drew it — the lever, the circle, the
    // offsets that placed it — because a whole half-plane is a bigger
    // target than a 5px circle and needs no aiming.
    //
    // ⚠️On stage only. Off the pasteboard the press is not this tool's at
    // all, which is the gate the move already asked for — see the
    // `onStage` check on the move path. ⛔Not a new rule: the same
    // sentence, asked once instead of twice.
    return canvasSize.containsPasteboardPoint(
          x: canvasPoint.x,
          y: canvasPoint.y,
        )
        ? TransformHandle.rotate
        : null;
  }

  /// What the ants painter draws over the box: the outline, the grips and
  /// the anchor cross, in viewport space.
  ///
  /// THREE SHAPES, one per what the box currently IS — a mesh's warped
  /// boundary, a 퍼스 quad, or the plain affine box — and each is its own
  /// builder. ↩️They were one nested ternary holding all three record
  /// literals, which scored 29 against a warning line of 15: every reader
  /// had to unwind the whole chain to find out what one mode draws.
  SelectionTransformChrome? transformChrome(
    List<CanvasPoint>? placedMesh,
    List<CanvasPoint>? placedCorners,
    SelectionAffine? chromeAffine,
    double chromeWidth,
    double chromeHeight,
  ) {
    // ⚠️ONE anchor for all three chromes. The cross is the ROTATION's
    // centre and every mode can be turned (outside the box is the
    // rotation, whatever mode is armed), so hiding it in 퍼스/메쉬 would
    // be a rule about the modes that the rotation does not have.
    final anchor = chromeAffine == null
        ? null
        : viewport.canvasToViewportOffset(chromeAffine.anchorCanvas);
    if (placedMesh != null) {
      return _meshChrome(placedMesh, anchor);
    }
    if (chromeAffine == null) {
      return null;
    }
    // The affine box's own grips, which BOTH remaining shapes wear: 퍼스
    // keeps them under its quad, because non-uniform scaling lives there
    // and hiding them would hide half the tool.
    final grips = [
      for (final handle in scaleHandles)
        scaleHandleViewport(handle, chromeAffine, chromeWidth, chromeHeight),
    ];
    if (placedCorners != null) {
      return _quadChrome(placedCorners, grips, anchor);
    }
    return _boxChrome(chromeAffine, chromeWidth, chromeHeight, grips, anchor);
  }

  /// 메쉬: the control points ARE the handles, and the outline is the grid's
  /// warped boundary.
  SelectionTransformChrome _meshChrome(
    List<CanvasPoint> placedMesh,
    Offset? anchor,
  ) => (
    box: [
      for (final point in warp.meshBoundary(placedMesh))
        viewport.canvasToViewportOffset(point),
    ],
    handles: [
      for (final point in placedMesh) viewport.canvasToViewportOffset(point),
    ],
    anchor: anchor,
  );

  /// 퍼스: the quad, its four corners, and the affine box's grips beneath.
  SelectionTransformChrome _quadChrome(
    List<CanvasPoint> placedCorners,
    List<Offset> grips,
    Offset? anchor,
  ) => (
    box: [
      for (final point in placedCorners) viewport.canvasToViewportOffset(point),
    ],
    handles: [
      for (final point in placedCorners) viewport.canvasToViewportOffset(point),
      ...grips,
    ],
    anchor: anchor,
  );

  /// 일반: the affine box and nothing else.
  SelectionTransformChrome _boxChrome(
    SelectionAffine affine,
    double width,
    double height,
    List<Offset> grips,
    Offset? anchor,
  ) => (
    box: [
      for (final point in _boxShapeFor(affine, width, height).points)
        viewport.canvasToViewportOffset(point),
    ],
    handles: grips,
    anchor: anchor,
  );
}
