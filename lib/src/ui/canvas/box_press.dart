import 'dart:ui' show Offset;

import 'box_chrome.dart' show boxCrossFootprint, boxHandleFootprint;

/// What a press on a transform box takes hold of.
enum BoxPress {
  /// The cross — the centre a turn and a scale keep still.
  anchor,

  /// One of the box's handles ([BoxPressHit.handle] says which).
  handle,

  /// Inside the box: the move.
  inside,

  /// Outside the box, on stage: the turn.
  turn,
}

/// Where a press landed on a box, and which handle when it is one.
typedef BoxPressHit = ({BoxPress press, int handle});

/// Where [press] lands on a box — the ONE order every box on the canvas
/// keeps (F-222, 「조작마저도 통일」): the cross, then a handle, then the
/// inside, and outside is the turn. Null when it lands on none of them.
///
/// [anchor] is null for a box that wears no cross, [handles] empty for one
/// that does not scale, and [turns] false for one that does not turn — a
/// box offers what its value can take (R5 #10).
///
/// ⚠️THE CROSS IS ON TOP, SO IT IS GRABBED FIRST. It is painted over
/// everything else, and 「what you see is what you grab」 is the only rule
/// that survives the user dragging it onto a scale handle — which nothing
/// stops them doing, because nothing clamps it.
///
/// 🚨★★★**AND WHAT YOU DO NOT SEE, YOU DO NOT GRAB** (F-262, 유저
/// 2026-10-02: 「보이는 만큼 존재하도록」). The cross and a handle are taken
/// on what the chrome draws of them ([boxCrossFootprint],
/// [boxHandleFootprint]) and nowhere round it: a press beside one is the
/// move or the turn that lives there.
///
/// 🚨★★★**OUTSIDE THE BOX IS THE ROTATION.** 유저 2026-09-22: 「우선
/// **사각형 밖 조작은 회전으로 통하도록**. 지금 있는 **회전 꼭짓점은
/// 잔재 싹 삭제**하고. 사각형 내부 조작은 지금처럼 위치이동」.
///
/// ↩️A knob stuck out of the top edge and was hit-tested first. It is gone
/// with everything that drew it — the lever, the circle, the offsets that
/// placed it — because a whole half-plane is a bigger target than a 5px
/// circle and needs no aiming.
///
/// ⚠️On stage only ([onStage]). Off the pasteboard the press is not the
/// box's at all — for every box, a row's as much as the transform tool's
/// (F-222-box-Q6 「페이스트보드 안 — 변형 도구와 같게」).
BoxPressHit? boxPressAt(
  Offset press, {
  required Offset? anchor,
  required List<Offset> handles,
  required bool Function(Offset press) inside,
  required bool Function(Offset press) onStage,
  bool turns = true,
}) {
  if (anchor != null && boxCrossFootprint(anchor).contains(press)) {
    return (press: BoxPress.anchor, handle: -1);
  }
  for (var index = 0; index < handles.length; index += 1) {
    if (boxHandleFootprint(handles[index]).contains(press)) {
      return (press: BoxPress.handle, handle: index);
    }
  }
  if (inside(press)) {
    return (press: BoxPress.inside, handle: -1);
  }
  return turns && onStage(press) ? (press: BoxPress.turn, handle: -1) : null;
}
