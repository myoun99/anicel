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

  /// Every button bit that is NOT the primary contact (R27 #17 / R28).
  ///
  /// The mapping used to recognise EXACTLY `kSecondaryButton` and
  /// `kTertiaryButton`. A stylus barrel that a driver reports on any other
  /// bit — Windows Ink and the Wacom driver have several configurations —
  /// then fell through every branch in silence, which is the shape of the
  /// "와콤 펜은 우클릭버튼인거 확인했는데 툴이 아예 안 바뀜" report. Treating
  /// any non-primary bit as the secondary mapping costs nothing (the
  /// primary contact is the only one that draws) and stops the behaviour
  /// depending on which bit a driver happens to pick.
  static const int _nonPrimaryButtons = ~kPrimaryButton;

  /// The secondary-ish bits of [buttons]: null when only the primary (or
  /// nothing) is down.
  static int _mappedButtonBits(int buttons) => buttons & _nonPrimaryButtons;

  /// The canvas mapping row for a secondary-button press (PEN-7a); null =
  /// not a mapped press (primary drawing input, or touch).
  CanvasPointerMapping? mappedPointerActionFor(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      return null;
    }
    return _state._mappingForButtons(
      _mappedButtonBits(effectiveButtons(event)),
    );
  }

  /// The buttons to BELIEVE for [event].
  ///
  /// A driver sidecar that speaks for this moment WINS — the same
  /// contract [_state._pressure.normalizedPressure] already follows, and for the same
  /// reason: the OS path can be lying about what the pen just did.
  ///
  /// The lie this catches: Windows Ink hands a Wacom barrel press to a
  /// legacy window (Flutter never asks for WM_POINTER) as a PHANTOM PEN
  /// TAP — kind stylus, pressure exactly 0.0, the PRIMARY button down,
  /// on its own pointer id, while the pen is still hovering. Taken
  /// literally that is a drawing contact, so the barrel never reached
  /// its mapping AND the phantom opened a real stroke on top of it.
  ///
  /// Note this is a truth source, not a fingerprint: nothing here
  /// guesses from pressure being 0. A device with no pressure at all
  /// reports 0 for every honest contact it ever makes, so reading the
  /// zero as "must be a barrel press" would turn every stroke on such a
  /// tablet into a button press.
  int effectiveButtons(PointerEvent event) =>
      PenSidecars.freshButtons() ?? event.buttons;

  /// Buttons seen on the latest HOVER event — the PEN-11 hover-press
  /// edge detector's memory (S-Pen/Wacom report barrel presses while
  /// hovering; a rising mapped button fires one-shot actions without
  /// needing contact — the S-Pen hover window blocks touch, so the pen
  /// carries its own undo).
  int _lastHoverButtons = 0;

  bool mappedButtonHeldSinceHover(PointerDownEvent event) =>
      (_lastHoverButtons & _mappedButtonBits(effectiveButtons(event))) != 0;

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
    final buttons = effectiveButtons(event);
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
    final pressedBits = _mappedButtonBits(pressed);
    final mapping = _state._mappingForButtons(pressedBits);
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
    final buttons = effectiveButtons(event);
    final previous = _lastContactButtons[event.pointer] ?? 0;
    final pressed = buttons & ~previous;
    _lastContactButtons[event.pointer] = buttons;
    if (pressed == 0 ||
        _mappedHoldPointer != null ||
        _hoverToolHoldActive ||
        _state._activeDrawingPointer != null) {
      return;
    }
    final mapping = _state._mappingForButtons(_mappedButtonBits(pressed));
    if (mapping == null || mapping.action != CanvasPointerAction.eyedropper) {
      return;
    }
    _mappedHoldPointer = event.pointer;
    _mappedHoldRelease = mapping.release;
    _mappedHoldIsEyedropper = true;
    _state.widget.onTemporaryToolHold?.call(CanvasTool.eyedropper);
    final pickPosition = _state._canvasPositionFromLocal(event.localPosition);
    if (_state._isInsidePasteboard(pickPosition)) {
      _state.widget.onAltPick?.call(pickPosition);
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
