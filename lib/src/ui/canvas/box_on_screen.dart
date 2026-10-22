import 'dart:ui' show Offset;

import '../../models/canvas_point.dart';
import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart';
import '../../services/canvas_selection_shape.dart';
import '../../services/selection_affine.dart';
import '../brush/transform_tool_options.dart';
import 'canvas_viewport_offset.dart';
import 'float_warp.dart';
import 'box_chrome.dart' show SelectionTransformChrome;
import 'box_press.dart';
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
    required this.pasteboard,
    required this.mode,
    required this.boxOpen,
    required this.warp,
  });

  final CanvasViewport viewport;

  /// The wall a press must land inside to grab the box (I-23, I-109).
  final PasteboardWall pasteboard;

  /// Which of 일반/퍼스/메쉬 is armed.
  final TransformMode mode;

  /// Whether a box is open — a closed one offers its corners whatever the
  /// mode ([scaleHandles]).
  final bool boxOpen;

  /// The open box over the float — where 퍼스 puts its quad corners.
  final FloatWarp warp;

  /// The warp's own points as drawn — a 퍼스 quad's corners or a 메쉬
  /// grid — or none in 일반 (and on a box that is not open).
  List<CanvasPoint> get _warpPoints =>
      warp.placedMeshPoints ?? warp.placedCorners ?? const [];

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

  /// The box's outline as it is DRAWN, on the canvas: a 메쉬 grid's warped
  /// boundary, a 퍼스 quad, or the affine box — the one polygon the chrome
  /// strokes and a press asks 「inside?」 of.
  ///
  /// 🚨★★★F-412 (유저 2026-10-19): 「자유변형으로 그림 크게 조정하면, 사각형
  /// 도구 ui 밖을 클릭한게 아닌데도 회전이 작동함. 그림 조정되기 전 박스를
  /// 기준으로 작동해서 그 밖을 회전으로 삼아버리는 버그인듯. 일반변형은
  /// 문제없으니 그부분 법 통일하면서 해결」. The quad and the grid were drawn
  /// along their own points while the press asked the affine box their
  /// corners had been pulled away from, so the grown picture's inside was
  /// the turn. What you see is what you grab (F-262), in every mode.
  List<CanvasPoint> outline(
    SelectionAffine affine,
    double width,
    double height,
  ) {
    final mesh = warp.placedMeshPoints;
    if (mesh != null) {
      return warp.meshBoundary(mesh);
    }
    return warp.placedCorners ?? _boxShapeFor(affine, width, height).points;
  }

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

  /// What a press lands on — through the one order every box keeps
  /// ([boxPressAt]): the cross, then a point the warp drew or a grip, then
  /// inside the [outline], and outside is the turn.
  ///
  /// ⛔**THE WARP'S POINTS ARE HANDLES LIKE THE REST.** The layer asked them
  /// first, ahead of this order, so a 퍼스 corner or a grid point under the
  /// cross took the press from the cross drawn over it, and a 메쉬 press off
  /// every point found no move and no turn at all — three press laws for
  /// one box, one per mode.
  ///
  /// ⚠️The stage gate is the one the move already asked for — see the
  /// `onStage` check on the move path. ⛔Not a new rule: the same sentence,
  /// asked once instead of twice.
  BoxGrab? grabAt(Offset local, TransformBox box) {
    final affine = box.affine;
    final points = _warpPoints;
    final handles = scaleHandles;
    final hit = boxPressAt(
      local,
      anchor: viewport.canvasToViewportOffset(affine.anchorCanvas),
      handles: [
        for (final point in points) viewport.canvasToViewportOffset(point),
        for (final handle in handles)
          scaleHandleViewport(handle, affine, box.baseWidth, box.baseHeight),
      ],
      inside: (press) => CanvasSelectionShape(
        outline(affine, box.baseWidth, box.baseHeight),
      ).containsPoint(viewport.viewportOffsetToCanvas(press)),
      onStage: (press) {
        final at = viewport.viewportOffsetToCanvas(press);
        return pasteboard.containsPoint(x: at.x, y: at.y);
      },
    );
    return switch (hit?.press) {
      null => null,
      BoxPress.anchor => const HandleGrab(TransformHandle.anchor),
      BoxPress.handle when hit!.handle < points.length => WarpPointGrab(
        hit.handle,
      ),
      BoxPress.handle => HandleGrab(handles[hit!.handle - points.length]),
      BoxPress.inside => const HandleGrab(TransformHandle.inside),
      BoxPress.turn => const HandleGrab(TransformHandle.rotate),
      // A row's position path is bent on its row's box (I-89 ④); the tool's
      // box is handed no tangents.
      BoxPress.tangent => throw StateError('The tool box bends no path.'),
    };
  }

  /// What the ants painter draws over the box: the [outline], the handles
  /// and the anchor cross, in viewport space — what [grabAt] takes, drawn.
  ///
  /// The handles are the warp's own points (a 퍼스 quad's corners, a 메쉬
  /// grid), then the grips the mode offers ([scaleHandles]). 퍼스 keeps its
  /// edge grips under the quad, because they carry the edges and hiding
  /// them would hide half the tool; an open 메쉬 offers none.
  ///
  /// ⚠️The warp's points are the PLACED ones rather than the resample's, so
  /// the handles are on screen from the moment the mode is armed instead
  /// of appearing only once the first offset makes the warp real.
  ///
  /// ↩️THREE SHAPES were three builders, one per mode, each spelling its
  /// own outline — and the press asked a fourth, the affine box, for its
  /// inside (F-412). One outline, one list of handles: a mode differs only
  /// in which points it has.
  SelectionTransformChrome? transformChrome(
    SelectionAffine? chromeAffine,
    double chromeWidth,
    double chromeHeight,
  ) {
    if (chromeAffine == null) {
      return null;
    }
    Offset onScreen(CanvasPoint point) =>
        viewport.canvasToViewportOffset(point);
    return (
      box: [
        for (final point in outline(chromeAffine, chromeWidth, chromeHeight))
          onScreen(point),
      ],
      handles: [
        for (final point in _warpPoints) onScreen(point),
        for (final handle in scaleHandles)
          scaleHandleViewport(handle, chromeAffine, chromeWidth, chromeHeight),
      ],
      // ⚠️ONE anchor for every mode. The cross is the ROTATION's centre
      // and every mode can be turned (outside the box is the rotation,
      // whatever mode is armed), so hiding it in 퍼스/메쉬 would be a rule
      // about the modes that the rotation does not have.
      anchor: onScreen(chromeAffine.anchorCanvas),
    );
  }
}

/// What a press on the open box takes hold of ([BoxOnScreen.grabAt]).
sealed class BoxGrab {
  const BoxGrab();
}

/// One of the box's own handles: a grip, the cross, the inside (the move)
/// or the stage outside it (the turn).
final class HandleGrab extends BoxGrab {
  const HandleGrab(this.handle);

  final TransformHandle handle;
}

/// One of the warp's own points — a 퍼스 corner or a 메쉬 grid point, by
/// its index in the warp's offsets.
final class WarpPointGrab extends BoxGrab {
  const WarpPointGrab(this.index);

  final int index;
}
