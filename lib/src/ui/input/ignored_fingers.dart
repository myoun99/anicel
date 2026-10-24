import 'package:flutter/gestures.dart';

/// 🗣️I-124 (유저 2026-10-22): 「터치 존재하는 태블릿으로 사용시, 키보드 써서
/// 터치 쓸일없는데 터치가 쓸데없이 작동해서 방해하는 일이 있음. 그럴때를 위해
/// 모든 터치입력 무시하는 옵션」 — `AppInputSettings.touchIgnored`.
///
/// The fingers stay out where the platform's pointers come in
/// (`UiScaleBinding`), ahead of every listener, gesture and global route —
/// so not one of the places that reads a pointer's kind has to be taught
/// the switch, and none can forget it.
///
/// A contact is one thing from its press to its lift, so the switch is read
/// at the PRESS:
///
///   * a contact pressed while the fingers are ignored stays out through
///     its own lift — even if the switch comes off before it;
///   * a contact already on the glass when the switch goes on comes in to
///     its end — keeping out the lift of a press that came in would leave
///     it pressed for good;
///   * a finger's arrival and removal always come in — they are no contact.
///
/// ⛔By the kind the ENGINE gave, as `PenEchoes` keeps it: no reading of the
/// pen's driver turns a finger into a pen here, so a pen a platform reports
/// as a finger goes with the fingers.
///
/// ⚠️Windows still moves its own cursor to where a finger lands (D34,
/// `aimIsPromotedTouch`) — that is the OS, before the app hears a thing.
/// The fingers kept out here are counted nowhere, so no mouse is held off
/// for a finger nobody hears: the next mouse move is the mouse's.
final class IgnoredFingers {
  /// Contacts whose press came in, and those whose press stayed out — each
  /// until its lift.
  final Set<int> _heard = {};
  final Set<int> _unheard = {};

  /// Whether [event] comes in — false for a finger while [ignoring].
  bool admit(PointerEvent event, {required bool ignoring}) {
    if (event.kind != PointerDeviceKind.touch ||
        event is PointerAddedEvent ||
        event is PointerRemovedEvent) {
      return true;
    }
    final pointer = event.pointer;
    if (event is PointerDownEvent) {
      (ignoring ? _unheard : _heard).add(pointer);
      return !ignoring;
    }
    final heard = _heard.contains(pointer);
    if (heard || _unheard.contains(pointer)) {
      if (event is PointerUpEvent || event is PointerCancelEvent) {
        _heard.remove(pointer);
        _unheard.remove(pointer);
      }
      return heard;
    }
    return !ignoring;
  }
}
