part of '../interactive_brush_edit_canvas_view.dart';

/// A HELD BUTTON — a mapped pen or mouse button held during contact or
/// while hovering, standing in for a tool (the eyedropper first) until it
/// is released: which pointer holds it, what it maps to, and the buttons
/// last seen in contact and in hover.
///
/// 🚨A collaborator carved out of `_InteractiveBrushEditCanvasViewState`
/// (the audit's SRP cut, Round 6, 2026-09-03). Measured before cutting:
/// nine fields of its own and the four methods that read them most. It
/// reaches the view through `_state`.
class _BrushEditHold {
  _BrushEditHold(this._state);

  final _InteractiveBrushEditCanvasViewState _state;

  /// The live mapped-hold session (PEN-7a): a secondary-button press
  /// whose canvas mapping switched the tool temporarily. One at a time;
  /// eyedropper holds pick continuously through the move stream.
  int? _mappedHoldPointer;

  CanvasPointerRelease? _mappedHoldRelease;

  bool _mappedHoldIsEyedropper = false;

  /// Buttons seen on the latest HOVER event — the PEN-11 hover-press
  /// edge detector's memory (S-Pen/Wacom report barrel presses while
  /// hovering; a rising mapped button fires one-shot actions without
  /// needing contact — the S-Pen hover window blocks touch, so the pen
  /// carries its own undo).
  int _lastHoverButtons = 0;

  bool mappedButtonHeldSinceHover(PointerDownEvent event) {
    final bits = canvasMappedButtonBits(canvasPressButtons(event));
    return (_lastHoverButtons & bits) != 0;
  }

  /// R26 #19/#20: a mapped HOLD tool (eyedropper) engaged from a hover
  /// button press — a Wacom barrel button pressed while the pen hovers
  /// never produced a pointer DOWN, so the mapping silently did nothing
  /// and no eyedropper UI appeared. The tool switches on the press edge
  /// and springs back on the release edge.
  bool _hoverToolHoldActive = false;

  CanvasPointerRelease? _hoverToolHoldRelease;

  int _hoverToolHoldButton = 0;

  void handlePointerHover(PointerHoverEvent event) {
    if (!_state.widget.editable) {
      return; // Nothing to hover OVER while standing down.
    }
    if (event.kind == PointerDeviceKind.touch) {
      return;
    }
    final buttons = canvasPressButtons(event);
    final previousButtons = _lastHoverButtons;
    final pressed = buttons & ~previousButtons;
    final released = previousButtons & ~buttons;
    _lastHoverButtons = buttons;
    if (_hoverToolHoldActive && (released & _hoverToolHoldButton) != 0) {
      final keep = _hoverToolHoldRelease == CanvasPointerRelease.keep;
      _hoverToolHoldActive = false;
      _hoverToolHoldRelease = null;
      _hoverToolHoldButton = 0;
      _state.widget.onTemporaryToolRelease?.call(keep: keep);
    }
    // The tail is read on every hover sample: that is what makes turning
    // the pen over — not touching down with it — the moment the eraser
    // arrives.
    _state._overlay.syncPenTailMapping();
    final pressedBits = canvasMappedButtonBits(pressed);
    final mapping = canvasMappingForButtons(
      pressedBits,
      penTailActive: _state._penTailActive,
    );
    if (mapping == null) {
      return;
    }
    switch (mapping.action) {
      case CanvasPointerAction.undo:
        _state.widget.onInvokeAction?.call('edit-undo');
      case CanvasPointerAction.eyedropper:
        // R26 #19/#20: engage the eyedropper on the HOVER press edge —
        // the pen barrel button is a right-click that never touches the
        // surface, and the tool switch is what brings the eyedropper's
        // cursor + live swatch up. The pick itself still happens on
        // contact (the mapped-down path below).
        if (!_hoverToolHoldActive && _mappedHoldPointer == null) {
          _hoverToolHoldActive = true;
          _hoverToolHoldRelease = mapping.release;
          _hoverToolHoldButton = pressedBits;
          _state.widget.onTemporaryToolHold?.call(CanvasTool.eyedropper);
        }
      case CanvasPointerAction.redo:
        _state.widget.onInvokeAction?.call('edit-redo');
      case CanvasPointerAction.eraser ||
          CanvasPointerAction.pan ||
          CanvasPointerAction.none:
        break;
    }
  }

  /// Buttons last seen on a CONTACT event, per pointer — the in-contact
  /// counterpart of [_lastHoverButtons] (R27 #17).
  final Map<int, int> _lastContactButtons = {};

  void handleMappedButtonRiseDuringContact(PointerMoveEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      return;
    }
    final buttons = canvasPressButtons(event);
    final previous = _lastContactButtons[event.pointer] ?? 0;
    final pressed = buttons & ~previous;
    _lastContactButtons[event.pointer] = buttons;
    if (pressed == 0 ||
        _mappedHoldPointer != null ||
        _hoverToolHoldActive ||
        _state._activeDrawingPointer != null) {
      return;
    }
    final mapping = canvasMappingForButtons(
      canvasMappedButtonBits(pressed),
      penTailActive: _state._penTailActive,
    );
    if (mapping == null || mapping.action != CanvasPointerAction.eyedropper) {
      return;
    }
    _mappedHoldPointer = event.pointer;
    _mappedHoldRelease = mapping.release;
    _mappedHoldIsEyedropper = true;
    _state.widget.onTemporaryToolHold?.call(CanvasTool.eyedropper);
    final pickPosition = _state._canvasPositionFromLocal(event.localPosition);
    if (_state._isInsidePasteboard(pickPosition)) {
      _state.widget.onHoldPick?.call(pickPosition);
    }
  }

  /// Ends an active mapped hold (pointer up/cancel): tells the shell to
  /// spring the tool back or keep it, per the mapping.
  void releaseMappedHold(int pointer) {
    if (pointer != _mappedHoldPointer) {
      return;
    }
    final keep = _mappedHoldRelease == CanvasPointerRelease.keep;
    _mappedHoldPointer = null;
    _mappedHoldRelease = null;
    _mappedHoldIsEyedropper = false;
    _state.widget.onTemporaryToolRelease?.call(keep: keep);
  }
}
