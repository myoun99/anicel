import 'package:flutter/gestures.dart';

/// 🚨★★★**IS A CONTACT DOWN — the one answer, and every way it learns that
/// a press is over.** The undo and redo doors refuse while it says yes
/// (`HistoryVerbs.contactIsDown`, 유저 F-173 「도구를 사용중이면
/// 언두/리두 작동불가」), and the autosave clock holds a fire for it.
///
/// Fed by the global pointer route, which hears every event and joins no
/// hit test. A pointer comes off it by its lift or its cancel, and nothing
/// else — and a lift can be LOST on the way. Then it said yes for good and
/// every undo door stayed shut (F-232): 🗣️유저 2026-10-02 「언두
/// 안먹는다는거, 그 뒤로 2번 발생했어. 둘 다 해결은 동일하게
/// 프로젝트설정 버튼 누르는 식으로 해결」 · 「가능하면 근본/구조적으로
/// 해결해줘」. The settings menu cured it because a route coming CANCELS
/// every pointer the Navigator saw go down. So the census learns from
/// everything that proves a press over, and lets go of that press the way
/// the route does — by cancelling it:
///
///   * the window loses the OS's focus — what is pressed here will be let
///     go somewhere else, where this window never hears it
///     ([letGoOfEverything]);
///   * a pen or a mouse HOVERS, or presses again — that hand is up, so a
///     press of it still held lost its lift ([note]). A pen that leaves the
///     tablet's range comes back as a NEW pointer, so the press it left
///     never hears its own lift.
///
/// The cancel reaches what the press reached, so a stroke in flight ends
/// the way a cancelled stroke ends, and the census hears the cancel like
/// any other — ONE way off it.
class ContactCensus {
  ContactCensus({void Function(int pointer)? cancel})
    : _cancel = cancel ?? GestureBinding.instance.cancelPointer;

  final void Function(int pointer) _cancel;

  /// Every pointer down, with its kind — the kind because a pen or a mouse
  /// that hovers says its own hand is not down — and the time it went down.
  final Map<int, ({PointerDeviceKind kind, Duration since})> _down = {};

  /// The time of the last event heard, on the events' own clock.
  Duration _lastHeard = Duration.zero;

  /// Whether any contact is down — a finger, a pen, a mouse button.
  bool get anyDown => _down.isNotEmpty;

  /// WHAT is down, for the input inspector: each contact's kind and
  /// pointer, and how long before the last event heard it went down.
  ///
  /// 🗣️F-232 (유저 2026-10-03): 「같은 상황에서 마우스로 캔버스 클릭하면
  /// 해결하는걸론 바꼈는데 펜으로는 아무리 클릭해도 해결안되」 — the press
  /// that lost its lift is of SOME kind, and which one was never measured
  /// (the law below lets a hand go only by its own hand). The press that
  /// stays is the one whose age only grows; a screenshot of this line at
  /// the moment undo does nothing says its kind.
  String get held => _down.isEmpty
      ? 'none'
      : [
          for (final down in _down.entries)
            '${down.value.kind.name}#${down.key} '
                '+${_secondsSince(down.value.since)}s',
        ].join(' · ');

  String _secondsSince(Duration since) =>
      ((_lastHeard - since).inMilliseconds / 1000).toStringAsFixed(1);

  /// One event off the global pointer route.
  void note(PointerEvent event) {
    _lastHeard = event.timeStamp;
    if (event is PointerHoverEvent || event is PointerDownEvent) {
      _letGoOfLostLifts(event);
    }
    if (event is PointerDownEvent) {
      _down[event.pointer] = (kind: event.kind, since: event.timeStamp);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _down.remove(event.pointer);
    }
  }

  /// The window lost the OS's focus: every press lets go.
  void letGoOfEverything() => _down.keys.toList().forEach(_cancel);

  /// ⛔By HAND, not by pointer or device: the pen comes back under another
  /// id. ⛔Fingers are left alone — many land at once, and one landing says
  /// nothing about another still down.
  void _letGoOfLostLifts(PointerEvent event) {
    final hand = _oneContactHand(event.kind);
    if (hand == null) {
      return;
    }
    // A hover is no contact at all, its own pointer included; a press is
    // the contact now, and every OTHER press of its hand is the lost one.
    final hovering = event is PointerHoverEvent;
    _down.entries
        .where(
          (down) =>
              _oneContactHand(down.value.kind) == hand &&
              (hovering || down.key != event.pointer),
        )
        .map((down) => down.key)
        .toList()
        .forEach(_cancel);
  }

  /// The hand a pointer kind is, when that hand holds ONE contact at a time:
  /// a mouse has one set of buttons, a pen one tip — its eraser end is the
  /// same pen. Null for the rest.
  static PointerDeviceKind? _oneContactHand(PointerDeviceKind kind) =>
      switch (kind) {
        PointerDeviceKind.mouse => PointerDeviceKind.mouse,
        PointerDeviceKind.stylus ||
        PointerDeviceKind.invertedStylus => PointerDeviceKind.stylus,
        _ => null,
      };
}
