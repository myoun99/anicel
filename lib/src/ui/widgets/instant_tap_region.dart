import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/widgets.dart';

import '../input/value_control_pointers.dart';

/// A primary tap that does NOT wait out the double-tap window.
///
/// Registering `onDoubleTap` anywhere makes the single tap wait for the
/// gesture arena to resolve — about 300ms after a quick tap — because until
/// the window closes the arena cannot know a second tap is not coming. The
/// user's report is the plain one: "아무것도 안 했는데 300ms나 반응성
/// 느려지는 거잖아."
///
/// The fix is not to give up the double tap. It is to take the primary
/// action off the arena entirely, which the timeline cells worked out first
/// and this widget lifts out of them:
///
/// * pen and mouse act on the pointer DOWN — nothing to wait for, and a
///   press that turns into a drag has already done the harmless half
///   (picking the thing you were about to drag);
/// * touch acts on the pointer UP, and only if the finger stayed within
///   [travelSlop] — so a press that becomes a scroll is a scroll, not a
///   pick. Handing touch the same instant DOWN is what made the timeline's
///   first scroll touch keep moving the playhead (UI-R23 feedback #2).
///
/// Register the double tap on a `GestureDetector` *inside* [child] as
/// usual; it keeps working, and it no longer costs the single tap anything.
class InstantTapRegion extends StatefulWidget {
  const InstantTapRegion({
    super.key,
    required this.onTap,
    required this.child,
    this.onPressDown,
    this.onSettledTap,
    this.pressSeeksFor,
    this.travelSlop = 12,
    this.behavior = HitTestBehavior.deferToChild,
  });

  /// The primary action, with the press position in this region's own
  /// coordinates — the cells resolve which frame was hit from it.
  final void Function(Offset localPosition) onTap;

  /// Fired on the pointer DOWN whatever the device, before [onTap] may or
  /// may not run. For bookkeeping a later double tap will need: the
  /// timeline's double-tap gate records WHICH cell was pressed here,
  /// because the double-tap recognizer only reports the second tap's
  /// position.
  final void Function(Offset localPosition)? onPressDown;

  /// Fired on the RELEASE, and only when the pointer never travelled past
  /// [travelSlop] — 「this press turned out to be a tap」.
  ///
  /// 🚨T10 needs two different things at two different moments, which is why
  /// [onTap] alone could not carry it (유저 확정 2026-08-14):
  ///
  /// | moment | what happens |
  /// |---|---|
  /// | DOWN | the active target moves, and the selection is cleared if the press landed OUTSIDE it |
  /// | RELEASE, no travel | the selection is cleared — 「클릭하고 떼면 뭐든 비우게」 |
  ///
  /// ⛔Clearing on the down unconditionally kills the MOVE drag that starts
  /// inside a selection, and clearing only on the release leaves a range
  /// drag that started outside one carrying the old selection all the way —
  /// and a drag has travel, so that one would never clear at all.
  ///
  /// This fires whether or not [onTap] already ran on the down, so a caller
  /// can use both: the down is the pick, the settled release is the tap.
  final void Function(Offset localPosition)? onSettledTap;

  /// Whether [kind] may act on the DOWN. Defaults to "everything but a
  /// finger"; the timeline passes its own gate, which follows the
  /// touch-scroll preference.
  final bool Function(PointerDeviceKind kind)? pressSeeksFor;

  /// How far a finger may travel and still count as a tap.
  final double travelSlop;

  final HitTestBehavior behavior;
  final Widget child;

  @override
  State<InstantTapRegion> createState() => _InstantTapRegionState();
}

class _InstantTapRegionState extends State<InstantTapRegion> {
  /// The live primary pointer, tracked for EVERY device now — a pen and a
  /// mouse used to be forgotten the moment they acted on the down, because
  /// nothing downstream cared what happened next. [onSettledTap] does.
  int? _pointer;
  Offset? _downAt;
  Offset? _downLocal;

  /// Whether this pointer has left [InstantTapRegion.travelSlop] behind. It
  /// is remembered rather than acted on, because the two callbacks want it
  /// at different times: the touch [onTap] is cancelled outright, while
  /// [onSettledTap] only needs to know at the release.
  bool _travelled = false;

  /// Whether this pointer's [InstantTapRegion.onTap] already ran on the
  /// down. The release reads it to decide whether the primary action is
  /// still owed — a finger's is, a pen's is not.
  bool _actedOnDown = false;

  bool _actsOnDown(PointerDeviceKind kind) =>
      widget.pressSeeksFor?.call(kind) ?? kind != PointerDeviceKind.touch;

  bool _isPrimary(PointerDownEvent event) =>
      event.buttons == 0 || (event.buttons & kPrimaryButton) != 0;

  void _forget() {
    _pointer = null;
    _downAt = null;
    _downLocal = null;
    _travelled = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: widget.behavior,
      onPointerDown: (event) {
        if (!_isPrimary(event)) {
          return;
        }
        // 🚨★★★ 유저 #1 (2026-08-14): 「액티브 레이어가 아닌 다른 레이어의
        // 버튼 누르면 작동안함. 불투명도 슬라이더는 한번 움직이고 드래그가
        // 풀림 … 레이어에 있는 **모든 버튼이나 편집이** 그럼」.
        //
        // ★The law is already written, one file over: 「a press that lands
        // on a CONTROL belongs to that control」
        // ([value_control_pointers.dart]). Only the pan recogniser was
        // asking. This region — the rail row's PICK — was not, so a press
        // on a row's button did both: it worked the button AND moved the
        // drawing target, which rebuilt the row out from under the gesture
        // that was still running. A tap survived that (it had already
        // fired); a slider drag did not, and the button on a non-active row
        // lost its release.
        //
        // Dispatch is deepest-first, so a control that claims on down has
        // claimed by the time this runs.
        if (controlOwnsTap(event.pointer)) {
          return;
        }
        // Tracked whatever the device: the release still has something to
        // say ([onSettledTap]) even when the down already acted.
        _pointer = event.pointer;
        _downAt = event.position;
        _downLocal = event.localPosition;
        _travelled = false;
        _actedOnDown = _actsOnDown(event.kind);
        widget.onPressDown?.call(event.localPosition);
        if (_actedOnDown) {
          widget.onTap(event.localPosition);
        }
      },
      onPointerMove: (event) {
        final downAt = _downAt;
        if (event.pointer == _pointer &&
            downAt != null &&
            (event.position - downAt).distance > widget.travelSlop) {
          _travelled = true;
        }
      },
      onPointerUp: (event) {
        if (event.pointer != _pointer) {
          return;
        }
        final local = _downLocal ?? event.localPosition;
        final travelled = _travelled;
        final actedOnDown = _actedOnDown;
        _forget();
        // A finger that stayed put still owes the primary action, which the
        // down deliberately withheld from it.
        if (!actedOnDown && !travelled) {
          widget.onTap(local);
        }
        // And whoever acted, a press that did not travel was a TAP.
        if (!travelled) {
          widget.onSettledTap?.call(local);
        }
      },
      onPointerCancel: (event) {
        if (event.pointer == _pointer) {
          _forget();
        }
      },
      child: widget.child,
    );
  }
}
