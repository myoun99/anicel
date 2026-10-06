import '../core/turn_trig.dart';
import '../models/canvas_point.dart';
import '../models/transform_values.dart';

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
///
/// ⚠️It is [values] AIMED AT [pivot] and nothing more: what the transform
/// does is the values', where the piece stands is the pivot's. A door that
/// carries the edit somewhere else — the record 재현 replays, the tool
/// panel, another cel — carries [values] whole ([TransformValues] has what
/// spelling them one by one cost).
class SelectionAffine {
  /// The long way round to [SelectionAffine.of], for a caller that states
  /// the numbers where it builds the affine.
  SelectionAffine({
    required CanvasPoint pivot,
    double sx = 1,
    double sy = 1,
    double rotationDegrees = 0,
    double tx = 0,
    double ty = 0,
    double anchorX = 0,
    double anchorY = 0,
  }) : this.of(
         pivot,
         TransformValues(
           sx: sx,
           sy: sy,
           rotationDegrees: rotationDegrees,
           tx: tx,
           ty: ty,
           anchorX: anchorX,
           anchorY: anchorY,
         ),
       );

  /// [values] aimed at [pivot].
  const SelectionAffine.of(this.pivot, this.values);

  final CanvasPoint pivot;

  /// Everything the transform does, and no place.
  final TransformValues values;

  double get sx => values.sx;
  double get sy => values.sy;
  double get rotationDegrees => values.rotationDegrees;
  double get tx => values.tx;
  double get ty => values.ty;
  double get anchorX => values.anchorX;
  double get anchorY => values.anchorY;

  /// Whether the transform changes no pixel ([TransformValues.isIdentity]).
  bool get isIdentity => values.isIdentity;

  /// Nothing but a move ([TransformValues.isPureTranslation]).
  bool get isPureTranslation => values.isPureTranslation;

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

  /// 🚨★★★**EVERY NUMBER THAT CHANGES THE PICTURE, AS ONE STRING — AND IT
  /// LIVES HERE.**
  ///
  /// ⛔**A CACHE KEY WRITTEN SOMEWHERE ELSE CANNOT KNOW THIS CLASS GREW.**
  /// The resample cache spelled seven of these fields by hand, in the
  /// layer. [anchorX] and [anchorY] arrived on 2026-09-20 and that string
  /// never heard about them, so two affines that differed only in WHERE
  /// THE TURN HAPPENS hashed the same and the cache answered one with the
  /// other's picture. 🗣️유저 2026-09-22 saw it: 「중심 십자가를 다른데 두고
  /// **회전시키면** … **엄청나게 깜빡이면서 원래위치랑 향하려는 위치
  /// 방향으로 서로 순간이동**해」 — a frame that hit the stale entry and a
  /// frame that recomputed, alternating.
  ///
  /// ⚠️`the_values_are_listed_whole_test` fails if a field is added to this
  /// class or to [TransformValues] and not to its string. That ratchet is
  /// the point: 「I will remember」 is what was tried and it is what broke.
  String get cacheKey => '${values.cacheKey},${pivot.x},${pivot.y}';

  /// WHERE THE CROSS IS DRAWN — the rotation's centre in canvas space.
  ///
  /// Read [appliedTx]'s composite as `R·(q − a) + a + pivot + t`, where
  /// `q = S·(p − pivot)`: the turn happens about `q = a`, so in the output
  /// the centre sits at `pivot + a + t` whatever the angle is. ⚠️That it
  /// does not depend on θ is the point — the cross must not orbit itself
  /// while the box turns.
  ///
  /// ⛔ONE DERIVATION, beside the one it comes from. The chrome, the hit
  /// test and the tool panel all ask here; none of them re-derives it.
  CanvasPoint get anchorCanvas =>
      CanvasPoint(x: pivot.x + anchorX + tx, y: pivot.y + anchorY + ty);

  /// The rotation's cosine and sine, EXACT at the quarter turns
  /// ([turnSin] has the table and why it is one).
  ///
  /// Both the geometry ([apply], which moves the selection outline) and the
  /// pixels (the resample fold) read these, so the ants and the picture can
  /// never disagree about where the rotation went.
  double get cosTheta => turnCos(rotationDegrees);

  double get sinTheta => turnSin(rotationDegrees);

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

  /// Other values on the same pivot — how a door that changed the edit
  /// hands it back.
  SelectionAffine withValues(TransformValues values) =>
      SelectionAffine.of(pivot, values);

  SelectionAffine copyWith({
    double? sx,
    double? sy,
    double? rotationDegrees,
    double? tx,
    double? ty,
    double? anchorX,
    double? anchorY,
  }) => withValues(
    values.copyWith(
      sx: sx,
      sy: sy,
      rotationDegrees: rotationDegrees,
      tx: tx,
      ty: ty,
      anchorX: anchorX,
      anchorY: anchorY,
    ),
  );
}
