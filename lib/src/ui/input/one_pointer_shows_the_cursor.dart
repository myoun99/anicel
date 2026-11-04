import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RendererBinding;

/// THE SYSTEM HAS ONE CURSOR, AND IT IS THE POINTER THAT MOVED LAST.
///
/// 🗣️F-562 (유저 2026-11-04): 「변형도구 사용시, 꼭짓점 끄는 그런 캔버스쪽
/// 조작할때, 손가락커서가 될때가있고 아닐때가있음 … 로직 입구가 제대로
/// 통일안되있는거같은데 손가락으로 안바뀌도록 제대로통일」.
///
/// Every entrance to the transform box asks the cursor of ONE place — the
/// tool's region on the canvas, which defers there, so the arrow — and the
/// box itself names none. The hand came from somewhere else: Flutter keeps a
/// cursor for each DEVICE and asks the system for one only when that
/// device's changes, while the system shows whichever was asked for last.
/// The Windows embedder reports a pen and a mouse as two devices (the pen
/// through `WM_POINTER`, the mouse as device 0), and a device stays where it
/// was last seen after the hand has gone to the other one. So a mouse
/// resting on 적용 — dead until the box holds a change — went live under the
/// pen's first drag of a corner, and its hand went up; the pen's arrow had
/// not changed, so it was never asked for again.
///
/// ⇒ A pointer that moves takes the system's cursor: every other pointer
/// the tracker holds is told it has left, as it has for the system, and
/// one that comes back is a new arrival, whose cursor is asked for afresh.
///
/// ⛔The kinds the tracker follows, and only those (`MouseTracker`): a
/// finger and a pen's eraser end wear no cursor of their own.
class OnePointerShowsTheCursor {
  /// The last event of each pointer the tracker holds, by device.
  final Map<int, PointerEvent> _held = <int, PointerEvent>{};

  bool _listening = false;

  void listen() {
    if (_listening) {
      return;
    }
    _listening = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_heard);
  }

  void dispose() {
    if (!_listening) {
      return;
    }
    _listening = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_heard);
    _held.clear();
  }

  void _heard(PointerEvent event) {
    if (event.kind != PointerDeviceKind.mouse &&
        event.kind != PointerDeviceKind.stylus) {
      return;
    }
    if (event is PointerRemovedEvent) {
      _held.remove(event.device);
      return;
    }
    for (final left in [
      for (final other in _held.values)
        if (other.device != event.device) other,
    ]) {
      _held.remove(left.device);
      RendererBinding.instance.mouseTracker.updateWithEvent(
        PointerRemovedEvent(
          viewId: left.viewId,
          timeStamp: event.timeStamp,
          kind: left.kind,
          device: left.device,
          position: left.position,
        ),
        null,
      );
    }
    _held[event.device] = event;
  }
}
