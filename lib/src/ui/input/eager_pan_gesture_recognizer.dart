import 'package:flutter/gestures.dart';

import '../debug/input_inspector.dart' show InputInspector;
import 'value_control_pointers.dart';

/// A [PanGestureRecognizer] that accepts at the DIRECTIONAL hit slop
/// (~18px, [computeHitSlop]) instead of the pan slop (~36px,
/// [computePanSlop]) — UI-R22F #2 — or at the drag's own first step when
/// that comes sooner ([firstStepAt], F-238).
///
/// Why: the timeline's edit pans (range select/move, block moves, run
/// [+] adds, lane value scrubs) sit INSIDE scroll viewports whose
/// directional drag recognizers accept at the hit slop. A plain pan
/// needed twice the distance, so slow small drags lost the arena to the
/// scroll while fast large drags crossed both thresholds in one event
/// and won as the deeper recognizer — the "random"-feeling split. With
/// the SAME slop, the edit pan's total distance reaches the threshold no
/// later than any axis component can, and the deeper recognizer handles
/// the event first: the edit gesture now wins deterministically on its
/// hit area for every device it supports.
class EagerPanGestureRecognizer extends PanGestureRecognizer {
  EagerPanGestureRecognizer({super.debugOwner});

  /// Whether a drag pressed at `down` and now at `now` (this recogniser's
  /// local coordinates) has taken its FIRST STEP — changed the first frame
  /// it would change. It accepts there when the step comes before the hit
  /// slop above, and at the slop otherwise; a release before either is
  /// still a tap.
  ///
  /// 🗣️F-238 (유저 2026-09-29): 「블록선택하고 이동, 1코마만 움직일려해도
  /// 안되고 2콤마 움직이는만큼 커서 움직여야 2콤마 움직이고 … 1콤마만
  /// 바로바로 움직이는게 불가능함.」 ↩️A pen's drag waited out 18px and then
  /// spent all of it at once, so on cells narrower than 12px its first step
  /// was already two. What a step is belongs to the drag: a range MOVE takes
  /// one when the block would leave its seat, a SELECT when the pointer
  /// leaves the cell it pressed (F-138-Q1 「누른 상자 벗어나면 시작」).
  bool Function(Offset down, Offset now)? firstStepAt;

  /// Whether the drag this pan carries has CHANGED anything yet — asked of
  /// its owner after every move, once the owner has heard it, and told to
  /// the taps that share the pointer ([pointerDragTookAStep]).
  ///
  /// ⛔Not [firstStepAt] asked again: that is 「would a drag begun here
  /// have stepped」, read before the drag exists, and its answer moves once
  /// the drag does (a select's own anchor span turns its press into a press
  /// inside the selection). What the drag DID is the owner's to say.
  bool Function()? draggedAStep;

  Offset _down = Offset.zero;
  Offset _now = Offset.zero;

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _now = event.localPosition;
    }
    super.handleEvent(event);
    if (event is PointerMoveEvent && (draggedAStep?.call() ?? false)) {
      markPointerDragStepped(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    forgetPointerDragStep(pointer);
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      (firstStepAt?.call(_down, _now) ?? false) ||
      globalDistanceMoved.abs() >
          computeHitSlop(pointerDeviceKind, gestureSettings);

  /// T11: a press that landed on a VALUE CONTROL is that control's, and no
  /// eager pan starts from it.
  ///
  /// The eagerness is exactly what made this necessary. Accepting at the
  /// hit slop means this recognizer reaches its threshold no later than any
  /// single axis can reach a directional one — which is the whole point
  /// against a scroll view, and a walkover against a control that measures
  /// one axis only. A slider dragged straight down never moves in |dx| at
  /// all, so there is no race to settle and no arena rule that could help.
  ///
  /// Declining here rather than in a handler matters: `isPointerAllowed`
  /// runs at `addPointer`, BEFORE the arena, so the pointer is never
  /// entered and the control keeps it cleanly. Returning early from
  /// `onStart` would be far too late — by then this recognizer has already
  /// won, and the control would be dead too ([[gizmo-touch-law]]'s lesson,
  /// where the same shape produced "the gizmo does not move AND the page
  /// does not flip").
  @override
  bool isPointerAllowed(PointerEvent event) {
    // 🚨★★★EITHER CLAIM, not just the strong one (유저 2026-08-29: 「**터치
    // 좌표가 버튼인데 거기서 움직였다고 스크롤이 발생하는게 심각한
    // 버그야**」).
    //
    // This used to ask `valueControlOwnsPointer` — the strong claim, which
    // only sliders and splitters take. A button takes the WEAK one, so a
    // drag that began on a button was allowed through and became a pan:
    // the row list scrolls under the finger that pressed the eye.
    //
    // ⛔The weak claim exists because a button must NOT own drags outright
    // — the rail's eye-column swipe starts on a button and is a real verb.
    // That still works: `RailSwipeColumnPointer` takes the strong claim as
    // well, so a swipe column is untouched here and only the buttons with
    // no drag verb of their own stop leaking.
    if (controlOwnsTap(event.pointer)) {
      return false;
    }
    return super.isPointerAllowed(event);
  }

  /// The device this recognizer is actually tracking.
  ///
  /// 🚨The probes below used to hardcode [PointerDeviceKind.stylus], and
  /// that lied in the field: a user photo of `thr=18.0` was read as the
  /// threshold in play when the real one, for the mouse that produced the
  /// bug, was 1px. A whole round was spent failing to reproduce T11 on the
  /// strength of it. A probe that reports a constant is worse than no probe.
  PointerDeviceKind _kind = PointerDeviceKind.unknown;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _kind = event.kind;
    _down = _now = event.localPosition;
    super.addAllowedPointer(event);
  }

  // PEN-11 field probes (no-ops while the Input Inspector is hidden):
  // the arena verdict with the accumulated distance at that moment. An
  // 'ep rej' BELOW the hit slop means a competitor accepted before this
  // recognizer even reached its threshold — the on-device measurement
  // the desktop tests can't take.
  String _probeSuffix(PointerDeviceKind kind) {
    final threshold = computeHitSlop(kind, gestureSettings);
    return 'd=${globalDistanceMoved.abs().toStringAsFixed(1)}'
        ' thr=${threshold.toStringAsFixed(1)}'
        ' kind=${kind.name}'
        ' ts=${gestureSettings?.touchSlop?.toStringAsFixed(1)}';
  }

  @override
  void acceptGesture(int pointer) {
    InputInspector.note('ep acc ${_probeSuffix(_kind)}');
    super.acceptGesture(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    InputInspector.note('ep rej ${_probeSuffix(_kind)}');
    super.rejectGesture(pointer);
  }
}
