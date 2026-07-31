import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/widgets.dart';

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
  int? _touchPointer;
  Offset? _touchDownAt;
  Offset? _touchDownLocal;

  bool _actsOnDown(PointerDeviceKind kind) =>
      widget.pressSeeksFor?.call(kind) ?? kind != PointerDeviceKind.touch;

  bool _isPrimary(PointerDownEvent event) =>
      event.buttons == 0 || (event.buttons & kPrimaryButton) != 0;

  void _forgetTouch() {
    _touchPointer = null;
    _touchDownAt = null;
    _touchDownLocal = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: widget.behavior,
      onPointerDown: (event) {
        if (!_isPrimary(event)) {
          return;
        }
        widget.onPressDown?.call(event.localPosition);
        if (_actsOnDown(event.kind)) {
          widget.onTap(event.localPosition);
          return;
        }
        _touchPointer = event.pointer;
        _touchDownAt = event.position;
        _touchDownLocal = event.localPosition;
      },
      onPointerMove: (event) {
        final downAt = _touchDownAt;
        if (event.pointer == _touchPointer &&
            downAt != null &&
            (event.position - downAt).distance > widget.travelSlop) {
          _forgetTouch();
        }
      },
      onPointerUp: (event) {
        if (event.pointer != _touchPointer) {
          return;
        }
        final local = _touchDownLocal ?? event.localPosition;
        _forgetTouch();
        widget.onTap(local);
      },
      onPointerCancel: (event) {
        if (event.pointer == _touchPointer) {
          _forgetTouch();
        }
      },
      child: widget.child,
    );
  }
}
