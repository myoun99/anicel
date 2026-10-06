part of '../brush_canvas_panel.dart';

/// WHAT A MAPPED BUTTON DOES THAT IS NOT DRAWING — the history verbs a pen
/// or mouse button fires, and the pick it holds the eyedropper for — read
/// where every press on the canvas passes, so one code answers under every
/// tool, with or without a cel to draw on.
///
/// 🗣️F-299 (유저 2026-10-05): 「어떤 도구 들고있던 규칙 만들지말고 법 통일해서
/// 작동하도록」.
///
/// ↩️These lived in the DRAWING VIEW (PEN-7a · PEN-11 · R26 #19/#20 ·
/// R27 #17), which hears a press only while a drawing tool is armed over a
/// cel. Under the selection, the transform, the cut, the shape fill and the
/// guide — whose layers lie over it — and on a frame with no cel, a button
/// mapped to the eyedropper did nothing (measured 2026-10-06: four roads to
/// the eyedropper × ten tools).
///
/// The line is [canvasMappedActionDraws]. A mapped press that DRAWS — the
/// eraser's — stays the drawing view's: the stroke starts with that press
/// and carries the erase in its own settings. One that does not is read
/// here, as the pan already was one layer up
/// ([CanvasViewportGestureLayer]).
///
/// ⛔A hold is the TOOL, held (유저 2026-09-11, I-15: 「누르는동안 툴
/// 바뀌도록. 툴 바껴서 해당툴을 사용한다는 심플한 규칙」). The pick it makes
/// is the eyedropper's own ([_CanvasPanelTap.eyedropperPick]), and whatever
/// a change of tool does to the tool in hand it does here too — nothing in
/// this file asks which tool that is.
class _CanvasPanelMappedButtons {
  _CanvasPanelMappedButtons(this._state);

  final _BrushCanvasPanelState _state;

  /// The pick a button holds; null when none does.
  ///
  /// ONE field for the two ways it is engaged — a press while the pen
  /// hovers, a press in contact — because a hold is one or the other: the
  /// contact takes over a hover-engaged hold (R26 #19/#20: one hold
  /// session, one release). ↩️They were two sets of fields, the hover's
  /// cleared by hand where the contact took over.
  _MappedPick? _pick;

  /// Buttons seen on the latest HOVER event — the hover-press edge's memory
  /// (PEN-11: the S-Pen and Wacom report a barrel press while the pen
  /// hovers, and a rising mapped button acts without needing contact — the
  /// S-Pen's hover window blocks touch, so the pen carries its own undo).
  int _lastHoverButtons = 0;

  /// Buttons last seen in CONTACT, per pointer — the in-contact counterpart
  /// of [_lastHoverButtons] (R27 #17).
  final Map<int, int> _lastContactButtons = {};

  /// Whether this canvas reads [event]'s buttons at all: a finger has none,
  /// and content that takes no tool takes no mapped button either
  /// (playback — T28-c 「뭘 누르든 입력이 존재하면 정지」,
  /// [BrushCanvasPanel.toolInputEnabled]).
  bool _reads(PointerEvent event) =>
      _state.widget.toolInputEnabled &&
      event.kind != PointerDeviceKind.touch;

  /// A stroke or a drag is in flight on this canvas. Nothing here takes the
  /// tool from under one.
  bool get _busy =>
      _state._strokeActive ||
      _state._selectionDragActive ||
      _state._transformDragActive;

  bool get _penTail => _state._toolHolds.penTail;

  void hover(PointerHoverEvent event) {
    if (!_reads(event)) {
      return;
    }
    final buttons = canvasPressButtons(event);
    final before = _lastHoverButtons;
    _lastHoverButtons = buttons;
    final pick = _pick;
    if (pick is _HoverPick && (before & ~buttons & pick.buttons) != 0) {
      _letGo();
    }
    final pressed = canvasMappedButtonBits(buttons & ~before);
    final mapping = canvasMappingForButtons(pressed, penTailActive: _penTail);
    switch (mapping?.action) {
      case CanvasPointerAction.undo:
        _state.widget.onInvokeAction?.call(EditorActionIds.undo);
      case CanvasPointerAction.redo:
        _state.widget.onInvokeAction?.call(EditorActionIds.redo);
      case CanvasPointerAction.eyedropper:
        // R26 #19/#20: the pen's barrel button is a right-click that never
        // touches the surface — it produces no pointer DOWN — and the tool
        // switch is what brings the eyedropper's cursor and live swatch
        // up. The pick itself happens on contact ([down]).
        if (_pick == null) {
          _hold(_HoverPick(mapping!.release, pressed));
        }
      case CanvasPointerAction.eraser ||
          CanvasPointerAction.pan ||
          CanvasPointerAction.none ||
          null:
        break;
    }
  }

  void down(PointerDownEvent event) {
    if (!_reads(event)) {
      return;
    }
    // 🚨A press that landed on a control is that control's (CLAUDE.md,
    // `control_press_claim`) — this listener is an ancestor of every
    // control floating on the canvas, so the claim is already recorded.
    if (controlOwnsTap(event.pointer)) {
      return;
    }
    final mapping = canvasMappingFor(event, penTailActive: _penTail);
    if (mapping == null || _busy || _pick is _ContactPick) {
      return;
    }
    switch (mapping.action) {
      case CanvasPointerAction.undo:
        // Not again when the press already fired from the hover edge and
        // the tip then touched with the button still held.
        if (!_heldSinceHover(event)) {
          _state.widget.onInvokeAction?.call(EditorActionIds.undo);
        }
      case CanvasPointerAction.redo:
        if (!_heldSinceHover(event)) {
          _state.widget.onInvokeAction?.call(EditorActionIds.redo);
        }
      case CanvasPointerAction.eyedropper:
        _hold(_ContactPick(mapping.release, event.pointer));
        _pickAt(event);
      // The eraser's press draws: the drawing view's. The pan is the
      // viewport gesture layer's.
      case CanvasPointerAction.eraser ||
          CanvasPointerAction.pan ||
          CanvasPointerAction.none:
        break;
    }
  }

  bool _heldSinceHover(PointerDownEvent event) =>
      (_lastHoverButtons & canvasMappedButtonBits(canvasPressButtons(event))) !=
      0;

  void move(PointerMoveEvent event) {
    if (!_reads(event) || controlOwnsTap(event.pointer)) {
      return;
    }
    _riseInContact(event);
    // A held pick samples LIVE along the whole drag (PEN-7a: 「누르는 동안
    // 해당 색을 뽑는다」) — 유저 확정, one law for every dropper: 「클릭중이면
    // 색 바뀌도록 … 같은법으로. 드래그중 계속샘플」.
    final pick = _pick;
    if (pick is _ContactPick && pick.pointer == event.pointer) {
      _pickAt(event);
    }
  }

  /// R27 #17: a mapped button can also rise DURING contact — some pen
  /// drivers report the barrel bit a moment after the tip lands rather than
  /// on the down event, and the hover edge never sees it then. Only while
  /// nothing is in flight, so a live stroke or drag is never hijacked
  /// mid-line.
  void _riseInContact(PointerMoveEvent event) {
    final buttons = canvasPressButtons(event);
    final before = _lastContactButtons[event.pointer] ?? 0;
    _lastContactButtons[event.pointer] = buttons;
    final pressed = canvasMappedButtonBits(buttons & ~before);
    if (pressed == 0 || _pick != null || _busy) {
      return;
    }
    final mapping = canvasMappingForButtons(pressed, penTailActive: _penTail);
    if (mapping?.action == CanvasPointerAction.eyedropper) {
      _hold(_ContactPick(mapping!.release, event.pointer));
    }
  }

  /// [event]'s pointer is gone — lifted or cancelled.
  ///
  /// ⛔Behind no gate: what a press took, its ending gives back, whatever
  /// the canvas has become since (F-232 — an ending that stood behind a
  /// gate left the tool held).
  void up(PointerEvent event) {
    _lastContactButtons.remove(event.pointer);
    final pick = _pick;
    if (pick is _ContactPick && pick.pointer == event.pointer) {
      _letGo();
    }
  }

  /// Takes the tool for [pick] — through the shell's one hold, the same a
  /// held key takes it through ([TemporaryTool]), so the cursor, the panels
  /// and the per-tool settings follow.
  void _hold(_MappedPick pick) {
    _pick = pick;
    _state._toolHolds.pick = true;
    _state.widget.onTemporaryToolHold?.call(CanvasTool.eyedropper);
  }

  /// Ends the hold: the tool springs back, or stays, as the mapping says.
  void _letGo() {
    final keep = _pick?.release == CanvasPointerRelease.keep;
    _pick = null;
    _state._toolHolds.pick = false;
    _state.widget.onTemporaryToolRelease?.call(keep: keep);
  }

  void _pickAt(PointerEvent event) => _state._tap.eyedropperPick()?.call(
    _state._viewportState.canvasPointOf(event),
  );
}

/// A pick a mapped button holds, and what the tool does when it lets go.
sealed class _MappedPick {
  const _MappedPick(this.release);

  final CanvasPointerRelease release;
}

/// Engaged by a press while the pen HOVERS: it ends when those [buttons]
/// come up again in hover — or a contact takes it over.
final class _HoverPick extends _MappedPick {
  const _HoverPick(super.release, this.buttons);

  final int buttons;
}

/// Engaged in CONTACT: it ends when [pointer] lifts.
final class _ContactPick extends _MappedPick {
  const _ContactPick(super.release, this.pointer);

  final int pointer;
}
