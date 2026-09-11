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
  /// where the pen actually landed rather than where it had moved on to.
  PointerDownEvent? _pendingCelPress;

  /// Standing down, and something pressed: ask the shell for a cel — for a
  /// press that DRAWS.
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
  void pressAsksForACel(PointerDownEvent event) {
    if (_pendingCelPress != null) {
      return;
    }
    if (!canvasPressDraws(event, penTailActive: _state._penTailActive)) {
      return;
    }
    if (!(_state.widget.onPressNeedsCel?.call() ?? false)) {
      return;
    }
    _pendingCelPress = event;
  }

  /// Begins the held press now that there is somewhere for it to go.
  ///
  /// ⚠️Called from the MOVE and the UP rather than from a post-frame
  /// callback: those are the next events this listener receives, they carry
  /// the proof that the finger is still down, and they arrive after the
  /// rebuild for anything but an impossibly fast tap. A move that beats the
  /// rebuild is simply dropped and the next one tries again — the stroke
  /// still starts at the DOWN position either way.
  void resumePressThatMadeTheCel(int pointer) {
    final pending = _pendingCelPress;
    if (pending == null ||
        pending.pointer != pointer ||
        !_state.widget.editable) {
      return;
    }
    _pendingCelPress = null;
    _state._press.pointerDown(pending);
  }
}
