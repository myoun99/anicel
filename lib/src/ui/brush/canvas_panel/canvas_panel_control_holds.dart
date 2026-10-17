part of '../brush_canvas_panel.dart';

/// The pointers a control over the tools is holding — the CONTROL
/// entrance's own record ([_PanelBuild._toolDeck]). From a control's press
/// to its lift the tool's entrance takes no pointer at all.
///
/// 🚨A gesture that began on a control is the control's to its end
/// (CLAUDE.md — 유저 08-14 · 08-28 · 08-29: 「터치 좌표가 버튼인데 거기서
/// 움직였다고 스크롤이 발생하는게 심각한 버그야」). A pressed mouse's cursor is
/// asked of whatever lies under it at every move — the binding hit-tests a
/// pressed move afresh for the mouse tracker — so a drag that outran its
/// handle onto the canvas wore the tool's cursor there: under the outline,
/// none at all, the system's hidden and no aim to draw the outline at.
///
/// ⚠️The lift is heard on the POINTER'S ROUTE, not through a widget: a
/// control can be rebuilt away under the press it holds (an adjust that
/// lands on the lift), and a hold that missed its lift would leave the
/// tools deaf for good.
class _ControlHolds {
  final Set<int> _pointers = <int>{};

  bool get held => _pointers.isNotEmpty;

  void hold(PointerDownEvent event) {
    if (_pointers.add(event.pointer)) {
      GestureBinding.instance.pointerRouter.addRoute(event.pointer, _heard);
    }
  }

  void _heard(PointerEvent event) {
    if (event is! PointerUpEvent && event is! PointerCancelEvent) {
      return;
    }
    _let(event.pointer);
    // Nothing is rebuilt for the entrance to open — it asks [held] at the
    // hit test — so a frame is asked for: its mouse-tracker pass finds the
    // entrance under a resting hand again, and the aim is noted on entering.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _let(int pointer) {
    if (_pointers.remove(pointer)) {
      GestureBinding.instance.pointerRouter.removeRoute(pointer, _heard);
    }
  }

  void dispose() => _pointers.toList().forEach(_let);
}
