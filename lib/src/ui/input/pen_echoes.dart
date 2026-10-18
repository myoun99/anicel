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
/// while a pen is in range over the window — Windows gives the cursor to
/// the pen then too.
final class PenEchoes {
  final Set<int> _pensInRange = {};

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
    if (event is PointerRemovedEvent) {
      _pensInRange.remove(event.device);
    } else {
      _pensInRange.add(event.device);
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
}
