import 'package:flutter/gestures.dart';

/// 🚨★★★**A PEN IN RANGE HAS NO MOUSE** — on Windows, where the OS echoes
/// the pen as a mouse and the echo must not come in.
///
/// 🗣️F-400 (유저 2026-10-18): 「오로지 와콤 펜으로만 작동중이었는데 마우스
/// 호버가 섞인다던가 … 다른 입력이 섞이는게 문제인듯」 · 「근본/구조적으로
/// 해결」. Windows hands the pen over twice: as pointer messages, which the
/// engine reports as the pen, and as mouse messages promoted from them,
/// which carry a signature the engine drops (Flutter 3.47.4,
/// `flutter_window.cc`). But the cursor follows the pen, and the mouse
/// moves Windows itself sends for it carry none — so they come in as a
/// MOUSE, at the pen's point, and while the tip is down with the left
/// button Windows holds for it. A move with a button and no press before
/// it is a PRESS to the engine, one that never records itself as down, so
/// every such move is another press under a new pointer and none is ever
/// lifted (`flutter_windows_view.cc`, `pointer_data_packet_converter.cc`).
///
/// What that did, read off the inspector and the framework's source: a
/// frame block dragged by the pen took the echo's press as the pointer it
/// follows — a drag follows the LATEST pointer to join it
/// (`MultitouchDragStrategy.latestPointer`), and an echo never moves — so
/// the block stopped under a pen still pressed and moving. And the census
/// cancelled each echo as a press whose lift was lost (the red `touch
/// cancel` rows), which is what F-232's undo lock had been all along.
///
/// So while a pen is in range — from the first event it sends to its
/// removal, the span Windows gives it the cursor — a mouse's hovers and
/// presses are its echo and do not come in:
///
///   * an echo's press stays out through its own lift, however late — the
///     pen may leave first;
///   * a press the mouse began before any pen came is the mouse's to its
///     end;
///   * the mouse's arrival and removal always come in — the mouse tracker
///     keeps a device by them — and a wheel is never an echo.
///
/// ⛔By the kind the ENGINE gave, not the pen law's (`PenSidecars.kindOf`):
/// to that law an echo of the pen IS the pen, and that is why it goes —
/// the pen has said it already.
///
/// ⚠️What it costs, taken knowingly (F-400-Q1): a real mouse is not heard
/// while a pen is in range over the window and speaking — Windows gives the
/// cursor to the pen then too.
///
/// 🚨★★★F-427 (유저 2026-10-21): 「펜으로는 그리거나 패널열거나 다
/// 가능한데 마우스로 아무 조작도 안먹히는 상황이 찾아옴」. The range ends
/// at the pen's removal, and a window Windows has disabled — under a file
/// dialog the pen tapped open — hears no pen leave: the app held the pen in
/// range until it restarted, and kept every real mouse out as its echo. So
/// when the window hears again, every pen the record holds leaves
/// ([leavesUnheard]; `windows/runner/flutter_window.cpp` says why).
///
/// 🚨★★★F-520 (유저 2026-10-31): 「가끔 마우스가 앱 내에서 인식이 안되는
/// 버그 … 해당 상황에서 펜으로는 정상적으로 작동 … 마우스만 무시됨」 —
/// F-427's words with no dialog behind them, and not reproduced: every other
/// way a pen goes that `tool/probe/pen_probe_main.dart` can drive was heard
/// leaving. So the range no longer rests on a leave being heard. An echo
/// comes right behind its pen: a mouse that goes on speaking for a [silence]
/// with no pen saying a word is no echo, and the pens it spoke over have
/// gone ([leavesShownBy]).
final class PenEchoes {
  /// How long a mouse speaks alone before it is taken for one (F-520).
  /// ⚠️Picked, not measured: far past the gap between a moving pen's events,
  /// and a wait a hand on a dead mouse can bear.
  static const silence = Duration(seconds: 1);

  /// Each pen in range, by device, and the last of its events — what its
  /// leave is made from where the app could not hear it ([leavesUnheard]).
  final Map<int, PointerEvent> _pensInRange = {};

  /// When the mouse began speaking since a pen last did, and its last word.
  ({Duration began, Duration last})? _mouseAlone;

  /// Each mouse's press an echo began, kept out through its lift. ONE per
  /// mouse: the engine makes every further echo a new pointer and never
  /// speaks of the one before it again — and as no pointer comes twice, a
  /// lifted one left here keeps nothing else out.
  final Map<int, int> _echoPresses = {};

  /// Whether [event] comes in — false for the pen's echo.
  bool admit(PointerEvent event) => switch (event.kind) {
    PointerDeviceKind.stylus ||
    PointerDeviceKind.invertedStylus => _notePen(event),
    PointerDeviceKind.mouse => !_isEcho(event),
    _ => true,
  };

  bool _notePen(PointerEvent event) {
    _mouseAlone = null;
    if (event is PointerRemovedEvent) {
      _pensInRange.remove(event.device);
    } else {
      _pensInRange[event.device] = event;
    }
    return true;
  }

  bool _isEcho(PointerEvent event) => switch (event) {
    PointerHoverEvent() => _pensInRange.isNotEmpty,
    PointerDownEvent() => _pressed(event),
    PointerMoveEvent() || PointerUpEvent() || PointerCancelEvent() =>
      _echoPresses[event.device] == event.pointer,
    _ => false,
  };

  bool _pressed(PointerDownEvent event) {
    if (_pensInRange.isEmpty) {
      return false;
    }
    _echoPresses[event.device] = event.pointer;
    return true;
  }

  /// The leave of every pen in range, made from its last event — for a
  /// window that could not hear them go. Each comes in through [admit], as
  /// a pen's own leave does, so the record lets the pen go with it.
  List<PointerRemovedEvent> leavesUnheard() => [
    for (final last in _pensInRange.values)
      PointerRemovedEvent(
        viewId: last.viewId,
        timeStamp: last.timeStamp,
        kind: last.kind,
        device: last.device,
        position: last.position,
      ),
  ];

  /// The leaves [event] shows went unheard, ahead of it — every pen's, when
  /// it is a mouse's word and the mouse has been speaking a whole [silence]
  /// since a pen last did.
  ///
  /// ⛔Timed by the mouse's own words, not from the pen's last event: an echo
  /// can run ahead of its pen's next move, however long the pen rested — and
  /// so a pause of a [silence] starts the count over, or the echo the pen
  /// left behind it and that one would make a proof between them.
  List<PointerRemovedEvent> leavesShownBy(PointerEvent event) {
    if (event.kind != PointerDeviceKind.mouse) {
      return const [];
    }
    final now = event.timeStamp;
    final before = _mouseAlone;
    final began = before == null || now - before.last >= silence
        ? now
        : before.began;
    _mouseAlone = (began: began, last: now);
    return now - began < silence ? const [] : leavesUnheard();
  }
}
