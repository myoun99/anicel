import 'dart:math' as math;

import '../models/canvas_point.dart';

/// The Ctrl+T free-transform affine (P9b), canvas space:
/// `p' = R(θ) · S(sx, sy) · (p − pivot) + pivot + t` — scale about the
/// fixed [pivot] (the base box centre), rotate about the anchor, then
/// translate. Anchored handle scaling (the opposite-corner grip) is
/// expressed by compensating [tx]/[ty], so ONE composite covers every
/// handle interaction.
///
/// 🚨★★★**THE TWO CENTRES ARE TWO QUESTIONS** (유저 2026-09-20): scale is
/// 「**항상 상자의 중심**」 and rotation is 「**앵커를 기준으로**」. They
/// still ride one matrix, because rotating about the anchor is rotating
/// about the pivot plus a shift — see [appliedTx].
class SelectionAffine {
  const SelectionAffine({
    required this.pivot,
    this.sx = 1,
    this.sy = 1,
    this.rotationDegrees = 0,
    this.tx = 0,
    this.ty = 0,
    this.anchorX = 0,
    this.anchorY = 0,
  });

  final CanvasPoint pivot;
  final double sx;
  final double sy;
  final double rotationDegrees;
  final double tx;
  final double ty;

  /// WHERE THE ROTATION HAPPENS, as a displacement from [pivot].
  ///
  /// ⚠️Two doubles rather than a [CanvasPoint] for the same reason [tx] and
  /// [ty] are: a displacement is not a place, and this one has to have a
  /// const default so that 「no anchor」 needs no null anywhere.
  ///
  /// 🗣️유저 2026-09-20: 「tvp도 클튜도 **앵커포인트 별도로 둘수있어. 기본값은
  /// 중심**인데, 그걸 유저가 드래그해서 움직이는방식 … **앵커포인트는 회전시
  /// 앵커를 기준으로 회전**해」 — while 확대/축소 is 「**항상 상자의 중심**」,
  /// which is [pivot]. Two centres, because they answer two questions.
  ///
  /// ⛔**A DISPLACEMENT, NOT A POINT, in absolute canvas units.** 유저 fixed
  /// both halves the same day: 「기본값 상자안의 자리에서 **얼마나 이동됬나**」
  /// and 「**편집값은 절대값이야. 그냥 고정이야.** 용지가 어떻든간에 **무조건
  /// 같은값**으로 편집이 이루어져야되」. Zero is the box centre, so the
  /// default needs no special case anywhere.
  final double anchorX;
  final double anchorY;

  /// ⚠️The ANCHOR is not part of this. Moving it alone changes no pixel —
  /// [appliedTx] shows why: with no rotation it costs nothing — so a box
  /// whose anchor moved and nothing else still has nothing to land.
  bool get isIdentity =>
      sx == 1 && sy == 1 && rotationDegrees == 0 && tx == 0 && ty == 0;

  /// Nothing but a move: the pixels travel without being resampled.
  ///
  /// 🚨★★★**THE CHEAP PATH IS A LAW, NOT AN OPTIMISATION.** A translation
  /// carries the lifted stamp byte-exactly by moving its centre, so a drag
  /// inside the box neither resamples nor re-decodes — it is as cheap as it
  /// was when the move lived outside the affine entirely, which is what
  /// 유저's 「**가볍게 구조적으로 설계**」 asks of this round. ⛔The anchor is
  /// not consulted: with no rotation it costs nothing ([appliedTx]).
  bool get isPureTranslation =>
      sx == 1 && sy == 1 && rotationDegrees == 0;

  /// The translation the composite actually applies: [tx]/[ty] plus what
  /// the anchor costs.
  ///
  /// 🚨★★★**THE RESAMPLER NEVER LEARNS ABOUT THE ANCHOR.** Rotating about
  /// the anchor is exactly rotating about [pivot] and then shifting by
  /// `anchor − R·anchor`, so ONE composite still covers every interaction
  /// and the inverse matrix the kernel is handed keeps its shape. ⛔Giving
  /// that matrix a second centre is how a preview and its landing begin to
  /// disagree, and everything in this file exists so that they cannot.
  ///
  /// ⚠️[tx]/[ty] stay **THE USER'S MOVE** — the tool panel shows them as
  /// X/Y, and turning the box must not make those digits drift.
  double get appliedTx =>
      tx + anchorX - (anchorX * cosTheta - anchorY * sinTheta);

  double get appliedTy =>
      ty + anchorY - (anchorX * sinTheta + anchorY * cosTheta);

  double get _radians => rotationDegrees * math.pi / 180;

  /// The rotation's cosine and sine, EXACT at the quarter turns.
  ///
  /// `math.cos(pi / 2)` is 6.1e-17, not zero, and that residue is enough to
  /// make a quarter turn miss the resampler's lattice: destination pixel
  /// centres land a hair off source pixel centres, the footprint reaches a
  /// neighbour it should not, and "rotating by 90° gives back the same
  /// pixels" becomes a rounding accident rather than a guarantee. Reading
  /// the table for exact multiples of 90 makes it structural.
  ///
  /// Both the geometry ([apply], which moves the selection outline) and the
  /// pixels (the resample fold) read these, so the ants and the picture can
  /// never disagree about where the rotation went.
  double get cosTheta {
    final quarter = _exactQuarterTurn;
    return quarter == null ? math.cos(_radians) : _quarterCos[quarter];
  }

  double get sinTheta {
    final quarter = _exactQuarterTurn;
    return quarter == null ? math.sin(_radians) : _quarterSin[quarter];
  }

  /// 0/1/2/3 for an exact 0/90/180/270, null for anything in between.
  int? get _exactQuarterTurn {
    if (rotationDegrees % 90 != 0 || !rotationDegrees.isFinite) {
      return null;
    }
    final quarter = (rotationDegrees ~/ 90) % 4;
    return quarter < 0 ? quarter + 4 : quarter;
  }

  static const List<double> _quarterCos = <double>[1, 0, -1, 0];
  static const List<double> _quarterSin = <double>[0, 1, 0, -1];

  CanvasPoint apply(CanvasPoint point) {
    final lx = (point.x - pivot.x) * sx;
    final ly = (point.y - pivot.y) * sy;
    final cos = cosTheta;
    final sin = sinTheta;
    return CanvasPoint(
      x: lx * cos - ly * sin + pivot.x + appliedTx,
      y: lx * sin + ly * cos + pivot.y + appliedTy,
    );
  }

  /// [apply] run backwards: the pre-image of a canvas point.
  ///
  /// The perspective and mesh modes hold their control points as
  /// displacements in the box's OWN frame, so that rotating or scaling the
  /// box carries the warp with it instead of leaving it behind. Turning a
  /// pointer position into one of those displacements is this function.
  ///
  /// The scales cannot be zero — every writer clamps them away from it —
  /// so there is no degenerate case to guard.
  CanvasPoint applyInverse(CanvasPoint point) {
    final ux = point.x - pivot.x - appliedTx;
    final uy = point.y - pivot.y - appliedTy;
    final cos = cosTheta;
    final sin = sinTheta;
    final lx = ux * cos + uy * sin;
    final ly = -ux * sin + uy * cos;
    return CanvasPoint(x: lx / sx + pivot.x, y: ly / sy + pivot.y);
  }

  SelectionAffine copyWith({
    double? sx,
    double? sy,
    double? rotationDegrees,
    double? tx,
    double? ty,
    double? anchorX,
    double? anchorY,
  }) {
    return SelectionAffine(
      pivot: pivot,
      sx: sx ?? this.sx,
      sy: sy ?? this.sy,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      tx: tx ?? this.tx,
      ty: ty ?? this.ty,
      anchorX: anchorX ?? this.anchorX,
      anchorY: anchorY ?? this.anchorY,
    );
  }
}
