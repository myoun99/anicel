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
    StrokeSteps.queued();
    if (_state._overlayFlushScheduled) {
      return;
    }
    _state._overlayFlushScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _state._overlayFlushScheduled = false;
      if (_state.mounted) {
        stepPendingOverlayDabs();
      } else {
        _state._pendingOverlayDabs.clear();
      }
    });
    // Pointer samples can arrive while no frame is scheduled (nothing else
    // animating); make sure the flush frame actually happens.
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// The dabs queued since the stroke's last step, laid as its next — or,
  /// while a frame of the canvas's pictures is being drawn, held, and laid
  /// as one step once every such frame is up.
  ///
  /// 🚨★★★ONE STEP A FRAME SHOWN, NOT ONE A FRAME BUILT (card
  /// the-galaxy-tab-canvas-went-slow-on-build-1095, 2026-11-23; 🗣️관제
  /// 23:13 「한 장 사이의 점을 걸음 하나로 · 모든 플랫폼 같은 코드」): a step —
  /// its pile, its tiles landed, its write into the picture shown — went to
  /// the engine at every frame the app built, whatever the GPU had done of
  /// the last, while the screen draws one frame at a time
  /// (`ScreenTexture.present`). Where a step cost the GPU more than a frame
  /// built, the steps piled up behind the frame being drawn without end:
  /// 🗣️유저 (build 1101, Galaxy Tab) 「그을수록 같은선안에서 점점 느려지고 …
  /// 선떼고 5초뒤에 그은게 한번에 나오는정도」. Held here, nothing of the
  /// step goes anywhere: the overlay is not moved, so no tile is landed or
  /// written. The dabs are the same, in the same order — only how many
  /// a step carries changes, as it always did with the frames' pace.
  void stepPendingOverlayDabs() {
    if (_state._pendingOverlayDabs.isEmpty) {
      return;
    }
    final drawn = _state._picturesUp?.beingDrawn;
    if (drawn == null) {
      flushPendingOverlayDabs();
      return;
    }
    // Each frame built meanwhile asks again, of the same frames: the first
    // told lays what all held, and the rest find nothing.
    unawaited(
      drawn.then((_) {
        if (_state.mounted) {
          stepPendingOverlayDabs();
        } else {
          _state._pendingOverlayDabs.clear();
        }
      }),
    );
  }

  /// The dabs queued, laid now — a frame being drawn or not: what reads
  /// the stroke's tiles next needs every one ([stepPendingOverlayDabs]
  /// for the frames' own pace).
  void flushPendingOverlayDabs() {
    if (_state._pendingOverlayDabs.isEmpty) {
      return;
    }
    final batch = List<BrushDab>.of(_state._pendingOverlayDabs);
    _state._pendingOverlayDabs.clear();
    StrokeSteps.stepped(batch.length, together: _state._picturesUp);
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
