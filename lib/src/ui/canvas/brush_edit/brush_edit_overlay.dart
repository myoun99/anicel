part of '../interactive_brush_edit_canvas_view.dart';

/// THE STROKE OVERLAY — the dabs drawn above the canvas while a stroke
/// is live, queued and flushed in batches, and the pen tail that erases
/// — as its own object.
///
/// 🚨A collaborator carved out of `_InteractiveBrushEditCanvasViewState`
/// (the audit's SRP cut, 2026-09-02). It reaches the State through
/// `_state` and rebuilds through `_rebuild`.
class _BrushEditOverlay {
  _BrushEditOverlay(this._state);

  final _InteractiveBrushEditCanvasViewState _state;

  ActiveStrokeOverlayModel get _overlayModel =>
      _state.widget.overlayModel ?? _state._ownedOverlayModel;

  void queueOverlayDabs(List<BrushDab> newDabs) {
    if (newDabs.isEmpty) {
      return;
    }
    _state._pendingOverlayDabs.addAll(newDabs);
    if (_state._overlayFlushScheduled) {
      return;
    }
    _state._overlayFlushScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _state._overlayFlushScheduled = false;
      if (_state.mounted) {
        flushPendingOverlayDabs();
      } else {
        _state._pendingOverlayDabs.clear();
      }
    });
    // Pointer samples can arrive while no frame is scheduled (nothing else
    // animating); make sure the flush frame actually happens.
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void flushPendingOverlayDabs() {
    if (_state._pendingOverlayDabs.isEmpty) {
      return;
    }
    final batch = List<BrushDab>.of(_state._pendingOverlayDabs);
    _state._pendingOverlayDabs.clear();
    _appendOverlayDabs(batch);
  }

  /// Whether a stroke starting NOW is a tail erase — the tool switch is
  /// asynchronous, so the stroke's own settings snapshot has to carry
  /// the substitution exactly as the barrel-eraser path does.
  bool get penTailErases =>
      _state._penTailActive &&
      AppInput.settings.value.canvasPenTail.action ==
          CanvasPointerAction.eraser;

  /// Engages or releases the tail mapping from the HID observer's view of
  /// which end of the pen is down.
  ///
  /// FLIP-scoped by design, not contact-scoped: the switch happens when
  /// the pen is turned OVER, so one flip covers a whole erasing pass and
  /// the eraser's own size and settings are on screen before the first
  /// stroke — rather than the tool panel blinking brush⇄eraser once per
  /// stroke. A device whose driver reports no hover degrades to
  /// per-contact switching for free: its first report IS the contact.
  ///
  /// A null reading (no observer, non-Windows, or the report aged out)
  /// HOLDS the current state rather than releasing — losing sight of the
  /// pen is not the same as the pen being turned back over.
  void syncPenTailMapping() {
    final inverted = PenSidecars.freshInverted();
    if (inverted == null || inverted == _state._penTailActive) {
      return;
    }
    final mapping = AppInput.settings.value.canvasPenTail;
    if (inverted) {
      // A barrel hold that is already running owns the tool.
      if (_state._hold._hoverToolHoldActive || _state._hold._mappedHoldPointer != null) {
        return;
      }
      final tool = switch (mapping.action) {
        CanvasPointerAction.eraser => CanvasTool.eraser,
        CanvasPointerAction.eyedropper => CanvasTool.eyedropper,
        // pan/undo/redo/none have no tail meaning: those are momentary
        // verbs, and the tail is a state that can last minutes.
        _ => null,
      };
      if (tool == null) {
        return;
      }
      _state._penTailActive = true;
      _state.widget.onTemporaryToolHold?.call(tool);
      return;
    }
    _state._penTailActive = false;
    _state.widget.onTemporaryToolRelease?.call(
      keep: mapping.release == CanvasPointerRelease.keep,
    );
  }

  /// Starts a stroke: whatever the overlay still holds belonged to the
  /// stroke that just ended and was handed over at its commit.
  ///
  /// 🪦Until 2026-09-17 this had to KEEP the tiles covering for committed
  /// tiles whose pen-up handoff had missed (the "stand-ins"), because
  /// dropping them put those coordinates back on the painter's stale
  /// fallback — the PRE-stroke tile — and the stroke the user had just
  /// finished vanished in tile-shaped patches until its decodes landed. A
  /// committed tile pictures itself inside the paint now, so nothing is
  /// covering for anything and a reset takes nothing away.
  void beginStrokeOverlay() => resetOverlay();

  /// Clears the visible overlay and its tile images.
  void resetOverlay() => _overlayModel.reset();

  void _appendOverlayDabs(List<BrushDab> newDabs) {
    if (newDabs.isEmpty) {
      return;
    }
    final rasterizer = _state._liveRasterizer;
    if (rasterizer == null) {
      return;
    }
    final from = _overlayModel.dabs.length;
    _overlayModel.dabs.addAll(newDabs);
    final region = rasterizer.blendFrom(_overlayModel.dabs, from: from);
    if (region != null) {
      _overlayModel.updateRegion(source: rasterizer, region: region);
    }
  }
}
