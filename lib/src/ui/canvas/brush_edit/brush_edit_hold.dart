part of '../interactive_brush_edit_canvas_view.dart';

/// A BUTTON HELD FOR THE ERASER — a mapped pen or mouse button whose press
/// erases for as long as it stays down: which pointer holds it, and what
/// the tool does when it lets go.
///
/// 🚨A collaborator carved out of `_InteractiveBrushEditCanvasViewState`
/// (the audit's SRP cut, Round 6, 2026-09-03). It reaches the view through
/// `_state`.
///
/// ↩️It held EVERY mapped button's hold until 2026-10-06 (F-299): the
/// eyedropper's — engaged in hover or in contact — and the history verbs'
/// hover edge lived here too, nine fields of it, and so answered only
/// where this view hears a press. What a mapped button does that is not
/// drawing is the panel's now (`_CanvasPanelMappedButtons`,
/// [canvasMappedActionDraws] is the line); the eraser's press IS a stroke,
/// so it stays with the view that draws it.
class _BrushEditHold {
  _BrushEditHold(this._state);

  final _InteractiveBrushEditCanvasViewState _state;

  /// The contact a mapped button erases with (PEN-7a). One at a time.
  int? _mappedHoldPointer;

  CanvasPointerRelease? _mappedHoldRelease;

  /// A BUTTON holds the tool — this view's eraser, or a pick the panel
  /// reads ([CanvasToolHolds.buttonHoldsTheTool]).
  bool get buttonHoldsTheTool => _state._toolHolds.buttonHoldsTheTool;

  void handlePointerHover(PointerHoverEvent event) {
    if (!_state.widget.editable) {
      return; // Nothing to hover OVER while standing down.
    }
    if (event.kind == PointerDeviceKind.touch) {
      return;
    }
    // The tail is read on every hover sample: that is what makes turning
    // the pen over — not touching down with it — the moment the eraser
    // arrives.
    _state._overlay.syncPenTailMapping();
  }

  /// [pointer]'s press erases: the tool follows it for as long as it stays
  /// down (the shared tool-switch path — cursor and panels follow free).
  void holdEraser(int pointer, CanvasPointerRelease release) {
    _mappedHoldPointer = pointer;
    _mappedHoldRelease = release;
    _state._toolHolds.erase = true;
    _state.widget.onTemporaryToolHold?.call(CanvasTool.eraser);
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
    _state._toolHolds.erase = false;
    _state.widget.onTemporaryToolRelease?.call(keep: keep);
  }
}
