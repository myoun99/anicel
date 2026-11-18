part of '../interactive_brush_edit_canvas_view.dart';

/// A PRESS ON AN EMPTY CELL — the pen down that first has to make the
/// cel it will draw on, parked until the cel exists and then resumed as
/// the stroke it was.
///
/// 🚨A collaborator carved out of `_InteractiveBrushEditCanvasViewState`
/// (the audit's SRP cut, Round 6, 2026-09-03). Measured before cutting:
/// one field of its own and the two methods that park and resume it. It
/// reaches the view through `_state`.
class _BrushEditCelPress {
  _BrushEditCelPress(this._state);

  final _InteractiveBrushEditCanvasViewState _state;

  /// I-10: the press that MADE the cel, waiting for the cel to arrive.
  ///
  /// ⚠️Held rather than acted on, because the two are a frame apart: the
  /// block is created inside the down event, the rebuild that hands us the
  /// new frame happens after it, and only then is there a surface to ink.
  /// The stroke begins at the position stored here, so the line starts
  /// where the pen actually landed rather than where it had moved on to —
  /// and goes on through every move it made while it waited.
  ///
  /// 🚨ONE FIELD for the press and its moves: forgetting the press
  /// forgets its moves with it, so no wait hands its moves to the next.
  ({PointerDownEvent down, List<PointerMoveEvent> moves})? _pendingCelPress;

  /// A mark pressed where it makes its cel first
  /// ([InteractiveBrushEditCanvasView.marksMakeTheirCel]): ask the shell for
  /// one — for a press that DRAWS — and park the press until it is here.
  /// True when the press is parked.
  ///
  /// ⛔Only what the stroke path would draw with: a mapped barrel/middle
  /// press means pan or undo, and none of those wants a block made
  /// underneath it. This asked its own copy of half that rule — 「is the
  /// primary bit down?」 — so a barrel held with the tip, which the stroke
  /// path hands to its mapping, still asked (and, with the auto-frame on,
  /// made a block). [canvasPressDraws] is the stroke path's readings in its
  /// order (🗣️I-15 follow-up, 유저 2026-09-11: 「브러시로 그리는 로직이
  /// 발생하는 상황이 아닌데 프레임 존재하지 않는다는 메시지뜨니 …
  /// 근본적/구조적으로 해결」).
  bool pressAsksForACel(PointerDownEvent event) {
    if (_pendingCelPress != null) {
      return false;
    }
    if (!canvasPressDraws(event, penTailActive: _state._toolHolds.penTail)) {
      return false;
    }
    // Nor for a fill beyond the wall, which does nothing there — so it
    // makes no cel and explains no silence. The fill's own answer
    // (`fillSpendsNothingAt`), not a copy of it.
    if (_state._press.fillSpendsNothingAt(
      _state._canvasPositionFromLocal(event.localPosition),
    )) {
      return false;
    }
    if (!(_state.widget.onPressNeedsCel?.call() ?? false)) {
      return false;
    }
    _pendingCelPress = (down: event, moves: []);
    return true;
  }

  /// Begins the held press now that there is somewhere for it to go, and
  /// hands it the moves it made while it waited.
  ///
  /// ⚠️Called from the MOVE and the UP rather than from a post-frame
  /// callback: those are the next events this listener receives, they carry
  /// the proof that the finger is still down, and they arrive after the
  /// rebuild for anything but an impossibly fast tap.
  ///
  /// 🚨A MOVE THAT BEATS THE REBUILD IS KEPT, not dropped: every point the
  /// OS saw goes into the line (H56, [PenPath]) — and a kept move still
  /// carries the points its message merged. 🗣️F-611 (유저 2026-11-18,
  /// 아이폰 1093): 「처음구간이 직선으로 이어짐. 곡선으로 동그라미
  /// 그렸는데 첫 구간이 동그란선이 아니고 직선임」 — the moves made while
  /// the cel was being made never reached the line, and the stroke joined
  /// its DOWN to the first move after the wait with one straight step (a
  /// circle at 120 Hz held for 12 moves came in to 0.78 of its radius: the
  /// chord). ↩️「A move that beats the rebuild is simply dropped and the
  /// next one tries again — the stroke still starts at the DOWN position
  /// either way.」
  void resumePressThatMadeTheCel(PointerEvent event) {
    final pending = _pendingCelPress;
    if (pending == null || pending.down.pointer != event.pointer) {
      return;
    }
    if (!_state.widget.editable) {
      if (event is PointerMoveEvent) {
        pending.moves.add(event);
      }
      return;
    }
    _pendingCelPress = null;
    _state._press.pointerDown(pending.down);
    pending.moves.forEach(_state._press.pointerMove);
  }
}
