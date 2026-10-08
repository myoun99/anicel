import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../input/control_press_claim.dart';
import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../text/app_strings.dart';
import '../widgets/app_icon_button.dart';
import 'canvas_capsule.dart';

/// How far a target pill stands off its target's edge.
const double targetPillGap = 8;

/// Where a pill [pill] big stands for [target]: under it, centred on it.
///
/// 🗣️I-79-Q1 (유저 2026-10-08): 「위치는 대상 사각형의 위쪽 가운데. 즉
/// 변형도구는 지금 위치가 사각형 오른쪽밑인데 사각형 위 가운데로 바뀔뿐.
/// 멀어지지않음. 아니 그냥 위쪽 가운데 말고 아래쪽 가운데로 하자」 — the
/// pill a canvas verb wears stands under what the verb works on: the
/// transform tool's box, and the canvas or the camera frame being resized
/// (I-79 · I-80).
///
/// ↩️The transform box's 확정/취소 stood at its bottom-RIGHT (유저
/// 2026-09-22: 「위치는 위가아니라 클튜처럼 아래」) until the pill became
/// one for every verb.
///
/// With no room under the target it steps INSIDE, over the same edge — the
/// answer on `transform-confirm-bar-placement`: 「위가 막히면 상자 안쪽으로
/// 들어간다」. ⛔And it never leaves [room]: on a tablet the pill is the only
/// way out of the verb, so it stays where a finger can reach it — but it
/// never stops belonging to its target either, which is why it steps inside
/// rather than parking at an edge of its own.
Offset targetPillOffset({
  required Rect target,
  required Size pill,
  required Rect room,
}) {
  final under = target.bottom + targetPillGap;
  final top = under + pill.height <= room.bottom
      ? under
      : target.bottom - targetPillGap - pill.height;
  final left = target.center.dx - pill.width / 2;
  return Offset(
    left.clamp(room.left, math.max(room.left, room.right - pill.width)),
    top.clamp(room.top, math.max(room.top, room.bottom - pill.height)),
  );
}

/// The pill a canvas verb wears over its [target]: [children] side by side
/// in a [CanvasCapsule], placed by [targetPillOffset].
///
/// 🗣️I-79 (유저 2026-10-06): 「캔버스 내부 알약은 다른곳에서도 쓰니
/// 공용화. 예를들어 변형도구 체크버튼도 이 공용화된거 쓰도록 디자인 변경」 —
/// the capsule and its anatomy are the view pill's own.
///
/// Fills its parent and lays the pill out against it, so it MEASURES the
/// pill rather than trusting a number for it.
class CanvasTargetPill extends StatelessWidget {
  const CanvasTargetPill({
    super.key,
    required this.keyValue,
    required this.target,
    required this.children,
  });

  final String keyValue;

  /// What the verb works on, in this widget's own coordinates.
  final Rect target;

  /// Bar buttons (`AppIconButtonSize.bar`), the view pill's.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => CustomSingleChildLayout(
    delegate: _UnderTheTarget(target, CanvasPillRoom.coverOf(context)),
    // 🚨A PRESS ON THE PILL IS THE PILL'S, its rim included (CLAUDE.md: 「컨트롤
    // 위에서 시작한 제스처는 그 컨트롤의 것이다」). The verb's own layer is
    // an ancestor and hears the press too, and to the transform tool a
    // press outside its box is the rotation — so the rim between the
    // buttons would turn the box. Nothing fires; the claim is the point.
    child: ControlPressClaim(
      onPressed: null,
      child: CanvasCapsule(
        keyValue: keyValue,
        height: CanvasCapsule.barPillHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: CanvasCapsule.barPillEnd),
            ...children,
            const SizedBox(width: CanvasCapsule.barPillEnd),
          ],
        ),
      ),
    ),
  );
}

/// 확정 and 취소, the pill's last two: ✓ the verb Enter reaches too
/// ([EditorActionIds.confirm]), ✕ Escape's
/// ([EditorActionIds.selectionTransformCancel]) — keyed
/// `<keyPrefix>-confirm` and `<keyPrefix>-cancel`. [changed] lights the ✓
/// (its ON state) while what the pill stands under has changes to land.
///
/// ★THE PAIR, WRITTEN ONCE (I-80, 2026-10-08): the transform box's pill,
/// the canvas adjusted on the canvas (I-79) and the camera frame adjusted
/// on the canvas each spelled the two buttons out, and the third made it
/// one.
///
/// ⛔**THE APP'S ONE BUTTON** (「앱에 버튼은 한 종류」), reused rather than
/// re-made — 유저 2026-09-22: 「확정/취소버튼은 **우리 ui 있는거
/// 재사용할수있는거 하고** 아니면 우리스타일로 맞춰서 공용화해서 만들고」.
///
/// ↩️It was a private Material + InkWell + [ControlPressClaim] circle in
/// the selection layer, wearing the session's red/green. That is a second
/// button to keep in step with the app's forever, and the colour was chrome
/// talking about chrome — which [AppIconButton] already refuses (see its
/// `danger`). The pair says what it is with its ICON, and the box, the
/// ink, the tooltip and the press law all come from the one widget.
List<Widget> targetPillVerbs(
  String keyPrefix, {
  required VoidCallback? onConfirm,
  required VoidCallback onCancel,
  bool changed = false,
}) => [
  AppIconButton(
    keyValue: '$keyPrefix-confirm',
    shortcuts: const [EditorActionIds.confirm],
    tooltip: AppText.strings.commonApply,
    icon: const Icon(Icons.check),
    isSelected: changed,
    onPressed: onConfirm,
  ),
  AppIconButton(
    keyValue: '$keyPrefix-cancel',
    shortcuts: const [EditorActionIds.selectionTransformCancel],
    tooltip: AppText.strings.commonCancel,
    icon: const Icon(Icons.close),
    onPressed: onCancel,
  ),
];

/// What the canvas's pills keep out from under: the edges of the panel's
/// tool layers that something else stands on — a panel lying on the floor,
/// the panel's own capsules.
///
/// Given ONCE, around every tool the panel raises a pill from (the
/// transform box's 확정/취소, the canvas adjusted on the canvas), the way
/// the floor's cover is given to whatever lies on the floor
/// (`CanvasFloorInsets`): where a pill may stand is a question about where
/// it is. ↩️The selection layer was handed it as a parameter of its own.
class CanvasPillRoom extends InheritedWidget {
  const CanvasPillRoom({
    super.key,
    required this.cover,
    required super.child,
  });

  final EdgeInsets cover;

  /// The cover over [context]'s tools — none where no panel gives one.
  static EdgeInsets coverOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasPillRoom>()?.cover ??
      EdgeInsets.zero;

  @override
  bool updateShouldNotify(CanvasPillRoom oldWidget) =>
      oldWidget.cover != cover;
}

class _UnderTheTarget extends SingleChildLayoutDelegate {
  const _UnderTheTarget(this.target, this.cover);

  final Rect target;
  final EdgeInsets cover;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => targetPillOffset(
    target: target,
    pill: childSize,
    room: cover.deflateRect(Offset.zero & size),
  );

  @override
  bool shouldRelayout(_UnderTheTarget oldDelegate) =>
      oldDelegate.target != target || oldDelegate.cover != cover;
}
