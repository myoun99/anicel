import 'package:flutter/gestures.dart';

import '../debug/input_inspector.dart' show InputInspector;
import 'value_control_pointers.dart';

/// A [PanGestureRecognizer] that accepts at the DIRECTIONAL hit slop
/// (~18px, [computeHitSlop]) instead of the pan slop (~36px,
/// [computePanSlop]) — UI-R22F #2.
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
  EagerPanGestureRecognizer({super.debugOwner, super.supportedDevices});

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
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
    if (valueControlOwnsPointer(event.pointer)) {
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
