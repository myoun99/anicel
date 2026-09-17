import 'package:flutter/gestures.dart'
    show
        GestureDisposition,
        GestureMultiDragStartCallback,
        HorizontalDragGestureRecognizer,
        MultiDragGestureRecognizer,
        MultiDragPointerState,
        Offset,
        PanGestureRecognizer,
        PointerDeviceKind,
        PointerDownEvent,
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

/// The twin with no axis: a HANDLE — a transform box's corner, a gizmo's
/// crosshair — dragged anywhere. A handle is a bar in two dimensions, and
/// the law is the same one.
///
/// 🚨H24 (2026-09-15) is why it exists. The canvas a handle sits on now
/// takes the arena on the first movement itself, so a handle that waited
/// for the pan slop lost every drag to the surface under it. Deeper and just
/// as early is what keeps the handle's drag the handle's.
class OwningPanGestureRecognizer extends PanGestureRecognizer {
  OwningPanGestureRecognizer({super.debugOwner, super.supportedDevices});

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => true;
}

/// The MULTI-drag twin, for a `Draggable`: a drag SOURCE — a panel tab's
/// grip, a media pool row, a brush preset cell — takes the arena on the
/// first movement as well.
///
/// 🚨F-126 (유저 2026-09-13: 「패널을 드래그 해서 위치 움직이는 패널탭 띠,
/// 마우스로는 움직여서 패널 위치 도킹가능한데 펜으로는 불가능. 이유 확인해서
/// 법 통일」). Flutter's `ImmediateMultiDragGestureRecognizer` waits for the
/// device's hit slop — one pixel for a mouse, eighteen for a pen or a
/// finger — so a mouse's drag was accepted in the same move the press claim
/// above it asked, and a pen's never was. This is the law of this file,
/// asked of a drag source: winning is a matter of asking earlier, and no
/// distance is compared.
class OwningMultiDragGestureRecognizer extends MultiDragGestureRecognizer {
  OwningMultiDragGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
    this.stillOnTheThing,
  });

  /// 🚨★★★**WAIT UNTIL THE POINTER LEAVES WHAT IT PRESSED** — 유저 확정
  /// 2026-09-18 (`F-138-Q1`, 답 ①):
  ///
  /// > 「**미디어풀처럼 선택할 필요, 서있는 로직이 없는곳은 지금처럼 바로
  /// > 드래그, 브러시처럼 서있어야 하는곳은 누른 상자 벗어나면 시작으로**」
  ///
  /// The report was 「브러시 버튼은 **그냥 누르는순간 드래그가 발동**됨」 while
  /// the brush GROUP tolerated a shaky pen — a cell you must first STAND on
  /// cannot lose its press to a tremor.
  ///
  /// ⛔**AND IT IS NOT A DISTANCE.** 유저 2026-08-30, on finding the device's
  /// slop still being consulted for this kind of question: 「**1px 이동했는지
  /// 같은 px 이동으로 판단하는거** 설마 아직도 남아있나? … 싹 깔끔하게
  /// 걷어내」. This asks the SAME question `ControlPressClaim` asks to decide
  /// a click — 「is the pointer inside the box it pressed」 — so one predicate
  /// answers both halves and no threshold comes back.
  ///
  /// Null (the default) is 「start on the first movement」, which is what
  /// [F-126] bought and what every drag source without standing logic keeps.
  final bool Function(Offset globalPosition)? stillOnTheThing;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _FirstMovePointerState(
        event.position,
        event.kind,
        gestureSettings,
        stillOnTheThing,
      );

  @override
  String get debugDescription => 'owning multidrag';
}

class _FirstMovePointerState extends MultiDragPointerState {
  _FirstMovePointerState(
    super.initialPosition,
    super.kind,
    super.gestureSettings,
    this._stillOnTheThing,
  );

  final bool Function(Offset globalPosition)? _stillOnTheThing;

  /// The starter held back while the pointer has not left yet.
  ///
  /// 🚨**BOTH HALVES WAIT, and the second one is not obvious.** Winning the
  /// arena and STARTING the drag are two moments: when this recogniser is
  /// the arena's only member — no tap, no scroller under the pointer — the
  /// arena grants it the moment it closes, and [accepted] runs before a
  /// single move has happened. 🧪Measured: holding back only
  /// [checkForResolutionAfterMove] left a tremor dragging exactly as before.
  GestureMultiDragStartCallback? _held;

  bool get _stillOn {
    final stillOn = _stillOnTheThing;
    return stillOn != null &&
        stillOn(initialPosition + (pendingDelta ?? Offset.zero));
  }

  @override
  void checkForResolutionAfterMove() {
    if (_stillOn) {
      // Not a drag yet — the finger has not gone anywhere. ⛔A press that
      // ends here is still a press: nothing is resolved, so the tap under
      // it is untouched.
      return;
    }
    final held = _held;
    if (held != null) {
      _held = null;
      held(initialPosition);
      return;
    }
    resolve(GestureDisposition.accepted);
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (_stillOn) {
      _held = starter;
      return;
    }
    starter(initialPosition);
  }
}
