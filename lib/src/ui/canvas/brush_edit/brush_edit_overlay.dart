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

  /// Engages or releases the tail mapping as this view's hover or contact
  /// finds the pen — the holds' one sync ([CanvasToolHolds.syncPenTail]),
  /// through this view's road to the shell.
  void syncPenTailMapping() => _state._toolHolds.syncPenTail(
    hold: _state.widget.onTemporaryToolHold,
    release: _state.widget.onTemporaryToolRelease,
  );

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
