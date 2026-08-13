import 'package:flutter/gestures.dart'
    show
        HorizontalDragGestureRecognizer,
        PointerDeviceKind,
        VerticalDragGestureRecognizer;

/// 🚨★★★ **THE LAW: A PRESS THAT LANDS ON A BAR BELONGS TO THAT BAR.**
///
/// 유저 확정 2026-08-14, ⛔재론 금지:
/// > 「**슬라이더위에서 조작하기 시작하면 슬라이더조작하는거고 그 외가
/// > 스크롤인거야**」
///
/// Every gesture from that press is the bar's — scrolling included, with no
/// exception, no direction test, and nothing to decide afterwards.
///
/// ## What was here before, and why it is gone
///
/// A bar dragged along one axis — a slider's track, a splitter's grip —
/// usually sits inside a `Scrollable` that scrolls along the other. The old
/// answer was *not to win the arena but to not need it*: read the pointer
/// raw, and when the arena cancelled, ask whether the rival had travelled
/// far enough ACROSS this bar's axis to have earned it.
///
/// That question cost two bugs and several rounds. On a slider it could not
/// even be asked — a straight-down drag moves 0 along the bar's own axis, so
/// a mouse (1px hit slop) handed the row's pan a walkover with no race to
/// judge. On a splitter it fired mid-drag: a fast pull puts more travel in
/// each event, the cross-axis component cleared the rival's slop, and the
/// grip let go with the button still down (T30, 「마우스 여전히 클릭도중인데도」).
///
/// ⛔And the case it was protecting — a finger resting on a slider while the
/// panel scrolls under it — **was never a real gesture.** It was an
/// assumption written down as if it were a decision. 유저: 「태블릿에서
/// 슬라이더 위에 손가락을 얹고 패널을 스크롤하는게 실제로 쓰겟냐?
/// **절대로안하니까 다신하지마.**」 Do not resurrect it, and do not invent a
/// new cost of the same shape.
///
/// ## How the law is kept
///
/// The recognisers below accept on the FIRST MOVEMENT instead of at a slop.
/// Hit testing runs deepest-first, so a bar is offered each move before its
/// ancestors and has already accepted by the time any scrollable reaches its
/// own threshold. **Winning is a matter of asking earlier, not of asking
/// harder** — which is why this needs no new number and no new question.

/// A horizontal drag that takes the arena on the first movement, whatever
/// direction that movement is in.
///
/// The direction not mattering is the point: a slider dragged straight DOWN
/// moves 0 along its own axis, so a threshold on |dx| can never be crossed
/// and the rival wins by walkover rather than by racing. Accepting on any
/// motion removes the walkover. The value still only follows |dx| — the
/// recogniser reports `primaryDelta` from its own axis — so a vertical drag
/// holds the pointer and changes nothing, which is exactly "you are
/// operating the slider now".
class OwningHorizontalDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {
  OwningHorizontalDragGestureRecognizer({super.debugOwner});

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => true;
}

/// The vertical twin of [OwningHorizontalDragGestureRecognizer].
class OwningVerticalDragGestureRecognizer
    extends VerticalDragGestureRecognizer {
  OwningVerticalDragGestureRecognizer({super.debugOwner});

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => true;
}
