import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../widgets/axis_bar_gesture.dart';
import 'value_control_pointers.dart';

/// 🚨★★★A PRESS THAT LANDS ON A CONTROL BELONGS TO THAT CONTROL.
///
/// The law is in CLAUDE.md and 유저 has stated it three times — 2026-08-14
/// for sliders (「슬라이더위에서 조작하기 시작하면 슬라이더조작하는거고 **그
/// 외가 스크롤인거야**」), 08-28 for buttons, and 08-29:
///
/// > 「**터치 좌표가 버튼인데 거기서 움직였다고 스크롤이 발생하는게 심각한
/// > 버그야**」
///
/// This widget IS the law's code. It takes the WEAK claim — a button owns
/// its TAP, not every drag from it — which is enough, because
/// [EagerPanGestureRecognizer] declines any pointer either claim holds.
///
/// ⛔IT DOES NOT LIVE IN THE TIMELINE. It used to, as `RailControlPointer`
/// in `layer_label_controls.dart`, and the name plus the address is why the
/// x-sheet's toggles, the top strip's blend lock and the toolbar's 1·2·3·4·N
/// were still bare on 2026-08-29: a surface that is not the rail does not go
/// looking in a rail file for a rule that turns out to be the whole app's.
/// [AppIconButton] wrote the same three lines a second time for the same
/// reason. One home, so a button anywhere can wear it.
///
/// ⚠️Nesting is safe and the rail relies on it: the claims are `Set`s, so a
/// second claim on the same pointer is a no-op and both wrappers release on
/// the same event ([RailSwipeColumnPointer] adds the strong claim over this
/// one).
///
/// 🚨★★★AND IT TAKES THE DRAG, so the law reaches FLUTTER'S scrollers too.
///
/// The claim alone was only half the law. [EagerPanGestureRecognizer] asks
/// it and stands down — but a `Scrollable`'s own drag recogniser asks
/// nobody, so a drag that began on a button still scrolled the list under
/// it. That is the reported bug word for word, and it was fixed only
/// against the app's own pans:
///
/// > 「**터치 좌표가 버튼인데 거기서 움직였다고 스크롤이 발생하는게
/// > 심각한 버그야**」
///
/// ⛔The fix is NOT a device rule. Which devices may drag-scroll only moves
/// the problem between them — the moment a finger acts as a pointer
/// (터치 묘화), it gets the rival back. The question is WHAT WAS PRESSED,
/// and it has to be answered before any scroller's slop is reached.
///
/// So this mounts the recognisers from [axis_bar_gesture.dart], which
/// accept on the FIRST MOVEMENT: hit testing runs deepest-first, so the
/// control has already taken the arena by the time an ancestor scroller
/// reaches its threshold. 「Winning is a matter of asking earlier, not of
/// asking harder」. The drag is ABSORBED — a button's drag is nobody's
/// verb, and absorbing it is exactly what 「스크롤 애초에 발동 안 하도록」
/// means.
///
/// ⛔EXCEPT where the press IS a drag verb. A swipe column takes the STRONG
/// claim ([RailSwipeColumnPointer]) because a drag from its button paints
/// the column; absorbing there would kill the very gesture the strong claim
/// exists to protect. The recognisers below decline that pointer, the same
/// way [EagerPanGestureRecognizer] declines a claimed one — and the order
/// works out because pointer-down dispatch is deepest-first, so the strong
/// claim is already set when these are offered the pointer.
class ControlPressClaim extends StatelessWidget {
  const ControlPressClaim({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.deferToChild,
      gestures: <Type, GestureRecognizerFactory>{
        _ControlOwnsHorizontalDrag:
            GestureRecognizerFactoryWithHandlers<_ControlOwnsHorizontalDrag>(
              _ControlOwnsHorizontalDrag.new,
              // ⛔A no-op handler is REQUIRED, not decoration:
              // `DragGestureRecognizer.isPointerAllowed` returns FALSE when
              // every callback is null, so a recogniser with nothing to
              // report is never even offered the pointer. 🧪Measured: with
              // `(r) {}` the absorb silently did nothing and the list
              // scrolled from a button exactly as before.
              (recognizer) => recognizer.onStart = (_) {},
            ),
        _ControlOwnsVerticalDrag:
            GestureRecognizerFactoryWithHandlers<_ControlOwnsVerticalDrag>(
              _ControlOwnsVerticalDrag.new,
              (recognizer) => recognizer.onStart = (_) {},
            ),
      },
      child: Listener(
        onPointerDown: (event) => claimTapForControl(event.pointer),
        onPointerUp: (event) => releaseTapForControl(event.pointer),
        // ⛔Cancel too: a claim that outlives its gesture silently deafens
        // every later press handed the same pointer id.
        onPointerCancel: (event) => releaseTapForControl(event.pointer),
        child: child,
      ),
    );
  }
}

/// The absorbing pair. They report nothing and change nothing — holding the
/// pointer IS the whole job, and it is what stops an ancestor scroller from
/// starting on a control.
/// The absorbing pair. They report nothing and change nothing — holding the
/// pointer IS the whole job, and it is what stops an ancestor scroller from
/// starting on a control.
///
/// 🚨★★★THE STRONG CLAIM IS CHECKED AT ACCEPT TIME, NOT AT `addPointer`.
///
/// The first draft declined in `isPointerAllowed`, mirroring
/// [EagerPanGestureRecognizer]. It killed every swipe column, and the
/// reason is the nesting: a swipe column is
/// `RailSwipeColumnPointer` → strong-claim `Listener` → the BUTTON, and the
/// button mounts a [ControlPressClaim] of its OWN, deeper than that
/// Listener. Pointer-down dispatch is deepest-first, so the inner
/// recogniser is offered the pointer BEFORE the strong claim is set — it
/// saw an unclaimed pointer and absorbed the swipe.
///
/// Accepting is the later moment, and by the first MOVE every down handler
/// on the path has run. So the question is asked there instead, where the
/// answer is complete.
class _ControlOwnsHorizontalDrag extends OwningHorizontalDragGestureRecognizer {
  int? _pointer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _pointer = event.pointer;
    super.addAllowedPointer(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      !_standsDown(_pointer) &&
      super.hasSufficientGlobalDistanceToAccept(
        pointerDeviceKind,
        deviceTouchSlop,
      );
}

class _ControlOwnsVerticalDrag extends OwningVerticalDragGestureRecognizer {
  int? _pointer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _pointer = event.pointer;
    super.addAllowedPointer(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      !_standsDown(_pointer) &&
      super.hasSufficientGlobalDistanceToAccept(
        pointerDeviceKind,
        deviceTouchSlop,
      );
}

/// ⛔A drag from here is somebody's VERB (a swipe column, a slider): the
/// weak claim stands down so the thing that owns it can run.
bool _standsDown(int? pointer) =>
    pointer != null && valueControlOwnsPointer(pointer);

/// 🚨★★★A DRAG FROM HERE IS THIS THING'S VERB — the STRONG claim, in one
/// place.
///
/// [ControlPressClaim] says 「the TAP is mine」 and absorbs the drag, which
/// is right for a button: a drag from a button is nobody's verb, so nothing
/// should happen. A slider, a splitter and a swipe column are the other
/// case — the drag IS the thing they do — and they say so with this.
///
/// What it buys, in one sentence each:
/// * [EagerPanGestureRecognizer] declines the pointer at `addPointer`, so
///   no edit pan above starts from a press that landed here;
/// * [ControlPressClaim]'s absorbing recognisers stand down at accept time,
///   so the drag reaches whatever mounted this.
///
/// ⛔It was written THREE times before this — `field_slider`,
/// `dock_edge_splitter` and the rail's swipe column each carried the same
/// four lines. Three copies of one law is how the day comes that one of
/// them learns something the others do not ([[no-copy-to-share]]).
///
/// ⚠️It does NOT mount the drag recogniser. What the drag DOES is the
/// caller's — a slider moves a value, a splitter moves an edge, a swipe
/// column paints its rows — and the recognisers for that live in
/// [axis_bar_gesture.dart], where accepting on the first movement is the
/// half that beats an ancestor scroller.
class DragVerbClaim extends StatelessWidget {
  const DragVerbClaim({
    super.key,
    required this.child,
    this.behavior = HitTestBehavior.deferToChild,
  });

  final Widget child;

  /// Opaque where the claim must cover its own padding — a splitter grip is
  /// mostly empty space and still has to be claimable.
  final HitTestBehavior behavior;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: behavior,
      // Claimed HERE because hit-test dispatch runs deepest-first, so the
      // claim is already standing by the time anything above is offered the
      // same event and asks.
      onPointerDown: (event) => claimPointerForValueControl(event.pointer),
      onPointerUp: (event) => releasePointerForValueControl(event.pointer),
      // ⛔Cancel too: a claim that outlives its gesture would silently
      // deafen whichever later pan is handed the same id.
      onPointerCancel: (event) => releasePointerForValueControl(event.pointer),
      child: child,
    );
  }
}
