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

  /// Standing down, and something pressed: ask the shell for a cel.
  ///
  /// ⛔PRIMARY contact only, the rule the stroke path keeps as well: a
  /// mapped barrel/middle press means pan or undo, and none of those wants
  /// a block made underneath it.
  void pressAsksForACel(PointerDownEvent event) {
    if (_pendingCelPress != null) {
      return;
    }
    if (event.buttons != 0 && (event.buttons & kPrimaryButton) == 0) {
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
    _state._handlePointerDown(pending);
  }
}
