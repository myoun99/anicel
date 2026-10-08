import 'dart:math' as math;

import '../core/wrap_degrees.dart';
import '../models/canvas_point.dart';
import 'selection_affine.dart';

/// 🚨★★★**THE BOX LAW — the numbers a transform box's drags solve** (F-222
/// ①). 🗣️유저 2026-09-29: 「변형툴,카메라레이어,트랜스폼등fx. 등등 캔버스에
/// 표시되는 변형 사각형 ui? 이거 전부 다 다르니까, 싹 하나로 통일」.
///
/// The transform tool's box, the camera frame and the layer's fx box each
/// solved their own drags — the move, the turn, the scale — with no helper
/// in common. This is where those solves live: the transform tool is the
/// first user of all of them, and the TURN is already every box's.
abstract final class TransformBoxLaw {
  /// A HAND drag's travel in whole canvas pixels.
  ///
  /// 🗣️유저 2026-09-22: 「캔버스쪽 직접 손으로 끌어서 이동하는거는 소수점은
  /// 이동안되게. 즉 스냅. 15다음이 15.2 이런식말고 16되도록」. The TOTAL
  /// travel is rounded, never each step, so a slow drag cannot drift.
  ///
  /// ⛔Typed values are not rounded (「확대축소는 소수점 이동해도 되는데」):
  /// the split is by ENTRANCE — a hand on the canvas — and by nothing else.
  /// ↩️The drag that opened the box snapped and a second drag inside the
  /// already-open box did not, which split the law by whether a box was open.
  static CanvasPoint wholePixels(CanvasPoint travel) =>
      CanvasPoint(x: travel.x.roundToDouble(), y: travel.y.roundToDouble());

  /// The pointer's angle about [centre], in CANVAS degrees (clockwise, y
  /// down).
  static double angleAbout(CanvasPoint centre, CanvasPoint pointer) =>
      math.atan2(pointer.y - centre.y, pointer.x - centre.x) * 180 / math.pi;

  /// One move of a TURN drag: the pointer's angle about [centre] now, and
  /// how far the hand has turned since [lastAngle] — the wrapped difference,
  /// so a turn stays continuous across the ±180° seam and whole extra turns
  /// count (0 → 360 keys are meaningful: poses lerp as they are).
  ///
  /// 🚨★★★**CANVAS ANGLES, NOT SCREEN ANGLES.** A turn measured on the
  /// canvas is the turn the canvas makes, however the VIEW is rotated or
  /// flipped. ↩️The camera lever measured on screen and turned the step
  /// round under a horizontal flip only, so a vertical flip (or both) turned
  /// the camera against the hand; the layer box measured on screen and never
  /// folded at all, so its value jumped a whole turn at the seam.
  static ({double angle, double turned}) turn({
    required CanvasPoint centre,
    required CanvasPoint pointer,
    required double lastAngle,
  }) {
    final angle = angleAbout(centre, pointer);
    return (angle: angle, turned: wrapDegrees(angle - lastAngle));
  }

  /// Where the [grabbed] handle (its base-local position) would be if it
  /// moved exactly as far as the pointer has since the press — the point
  /// [scaled] is handed, so a press that landed off the handle moves it by
  /// the hand's travel and not onto the hand (F-127: a pen always moves, so
  /// a handle put under the pointer jumped on the first move).
  static CanvasPoint pressDisplaced(
    SelectionAffine start,
    CanvasPoint grabbed,
    CanvasPoint startPointer,
    CanvasPoint pointer,
  ) {
    final atPress = start.apply(
      CanvasPoint(x: start.pivot.x + grabbed.x, y: start.pivot.y + grabbed.y),
    );
    return CanvasPoint(
      x: atPress.x + pointer.x - startPointer.x,
      y: atPress.y + pointer.y - startPointer.y,
    );
  }

  /// Solves a scale drag: the [grabbed] handle (base-local) lands on
  /// [pointer] — the press-displaced point ([pressDisplaced]) — while one
  /// point of the box stays where it is (its motion folds into the
  /// translation).
  ///
  /// 🚨★★★**THE BOX'S CENTRE BY DEFAULT ([aboutCentre]), THE OPPOSITE
  /// HANDLE OTHERWISE.** 🗣️유저 2026-09-22: 「**확대/축소의 기준점은 항상
  /// 상자의 중심**이야 … 일반변형에서 꼭짓점 이동하면 **그림 자체가 중심점
  /// 기준으로 커져** … 지금 반대쪽 꼭짓점 그대로 두고 현재 꼭짓점만 키우는게
  /// 클튜방식이야. 그래서 **tvp방식인 전체 크게하도록** … 그걸 **수정자가
  /// 아니라 일반 로직으로 적용**하고, **수정자로서 클튜방식의 현재꼭짓점만
  /// 늘리는 로직** 두도록」. ↩️It was a persistent SETTING
  /// (`TransformAnchor`) that Alt inverted, because a hold 「cannot be the
  /// whole answer on a tablet」 (2026-08-29); 유저 answered that differently
  /// on 09-22 — the modifier got a TOUCH entrance instead — so the setting
  /// went and the default is the one they named.
  ///
  /// [uniform] scales both axes by one factor, so a corner keeps the
  /// proportions the box has — whatever an edge middle or a mirror made
  /// them. The aspect ratio is locked by the MODE, not by a modifier:
  /// 일반변형 preserves it by definition, and Shift no longer locks anything
  /// — 유저 08-13, once 일반 became the default: 「어차피 일반변형이 종횡비
  /// 유지해서 수정자 기능 필요없을거같은데」.
  ///
  /// ⚠️「Non-uniform scaling lives on 퍼스's edge handles」 is no longer
  /// true (F-42): in 퍼스 an edge handle carries the edge's two quad corners,
  /// so this solve never sees one. Corrected rather than deleted, because a
  /// reader who remembers it would otherwise look here for a path that moved.
  static SelectionAffine scaled(
    SelectionAffine start,
    CanvasPoint grabbed,
    CanvasPoint pointer, {
    required bool aboutCentre,
    required bool uniform,
  }) {
    final anchorLocal = aboutCentre
        ? CanvasPoint(x: 0, y: 0)
        : CanvasPoint(x: -grabbed.x, y: -grabbed.y);
    final anchorCanvas = start.apply(
      CanvasPoint(
        x: start.pivot.x + anchorLocal.x,
        y: start.pivot.y + anchorLocal.y,
      ),
    );
    final radians = start.rotationDegrees * math.pi / 180;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    // v = R(−θ)·(pointer − anchor): the pointer in the box's local frame.
    final dx = pointer.x - anchorCanvas.x;
    final dy = pointer.y - anchorCanvas.y;
    final vx = dx * cos + dy * sin;
    final vy = -dx * sin + dy * cos;

    var sx = start.sx;
    var sy = start.sy;
    if (grabbed.x != anchorLocal.x) {
      sx = vx / (grabbed.x - anchorLocal.x);
    }
    if (grabbed.y != anchorLocal.y) {
      sy = vy / (grabbed.y - anchorLocal.y);
    }
    if (uniform && grabbed.x != anchorLocal.x && grabbed.y != anchorLocal.y) {
      // One factor for both axes, chosen as the least-squares projection of
      // the pointer onto the anchor→handle diagonal: the one that puts the
      // handle as close to the pointer as scaling both axes alike can.
      //
      // It used to take max(|sx|, |sy|), which is the LARGER axis rather
      // than the closest fit — so a drag that was not exactly along the
      // diagonal pulled the short axis up to the long one. That grows the
      // box past where the hand is, and it grows the resample with it: the
      // output area a pointer move costs is proportional to sx·sy, and the
      // measured penalty was 1.11× ten degrees off the diagonal, 1.33× at
      // twenty-five, 2× at fifty
      // (`test/services/transform_drag_cost_benchmark_test.dart`).
      //
      // The projection is a weighted mean of the two axis scales instead
      // of their max, so it always sits BETWEEN them: the box follows the
      // hand, and the cost follows the box. Signs need no special case
      // either — dragging past the anchor makes the projection negative
      // on its own, which is the mirror it should be.
      //
      // 🚨★★★**ONE FACTOR FOR BOTH AXES, NOT ONE SCALE.** The handle stands
      // at `S·g` from the anchor, and the fit is onto THAT diagonal, so the
      // box keeps the proportions it has. ↩️It projected onto `g` and wrote
      // the result to both axes, which is the same thing only while the two
      // scales agree — and 일반변형 has had edge middles since 09-22 and a
      // mirror since 08-13. Measured 2026-10-06 (F-256 · F-265): touching a
      // corner after an edge had stretched one axis snapped the box to one
      // scale (75×50 → 64.5×64.5), and after a 좌우반전 it projected a
      // mirrored handle onto an unmirrored diagonal and collapsed the
      // picture to 1%.
      final hx = start.sx * (grabbed.x - anchorLocal.x);
      final hy = start.sy * (grabbed.y - anchorLocal.y);
      final factor = (vx * hx + vy * hy) / (hx * hx + hy * hy);
      sx = start.sx * factor;
      sy = start.sy * factor;
    }
    sx = clampScale(sx);
    sy = clampScale(sy);

    // Anchor compensation: R·(S_old∘o − S_new∘o) folds into t.
    final dLocalX = start.sx * anchorLocal.x - sx * anchorLocal.x;
    final dLocalY = start.sy * anchorLocal.y - sy * anchorLocal.y;
    return start.copyWith(
      sx: sx,
      sy: sy,
      tx: start.tx + dLocalX * cos - dLocalY * sin,
      ty: start.ty + dLocalX * sin + dLocalY * cos,
    );
  }

  /// A scale kept off zero (and off NaN/∞): every inverse the box takes —
  /// the resample's, the warp's — divides by it.
  static double clampScale(double scale) {
    if (scale.isNaN || !scale.isFinite) {
      return 0.01;
    }
    if (scale.abs() < 0.01) {
      return scale.isNegative ? -0.01 : 0.01;
    }
    return scale;
  }
}
