part of '../xsheet_timeline_grid.dart';

/// THE RAIL SCRUB — a press or drag on the X-sheet's rail picking a frame
/// down the page, the clamp, the auto-pan at the edge and the tracking
/// that ends with the scrub — as its own object (the layer grid has the
/// same object turned on its side).
///
/// 🚨A collaborator carved out of `_XSheetTimelineGridState` (the audit's
/// SRP cut, 2026-09-02). It reaches the State through `_state`.
class _XSheetGridRailScrub {
  _XSheetGridRailScrub(this._state);

  final _XSheetTimelineGridState _state;

  LayerRailExtent get _railExtent =>
      _state.widget.railExtent ??
      (_state._ownedRailExtent ??= LayerRailExtent());

  int? _frameIndexForRailLocalY(double localY) {
    // Shared frame/x conversion policy; the rail's local y is the "x".
    return frameIndexFromLocalX(
      localX: localY,
      horizontalScrollOffset: _state._lastEffectiveFrameScrollOffset,
      frameCellWidth: _state._metrics.frameCellWidth,
      visibleFrameCount: _state._frameScroll.renderedFrameCount,
    );
  }

  void selectClampedFrameFromRail(int frameIndex) {
    // The endless runway IS the selectable tail now (UI-R10 #23 retired
    // the fixed safety frames): clamp against the BUILT extent.
    final clampedFrameIndex = clampFrameIndex(
      frameIndex: frameIndex,
      visibleFrameCount: _state._frameScroll.renderedFrameCount,
    );
    if (clampedFrameIndex == null ||
        clampedFrameIndex == _state._lastRailScrubbedFrameIndex) {
      return;
    }

    _state._lastRailScrubbedFrameIndex = clampedFrameIndex;
    (_state.widget.hooks.onScrubFrame ?? _state.widget.hooks.onSelectFrame)(
      clampedFrameIndex,
    );
  }

  /// The scrub gesture's release (raw pointer up/cancel — fires for taps
  /// AND drags). Tracking is NOT reset here so trailing tap handlers stay
  /// deduplicated.
  void endRailScrub() {
    _state.widget.hooks.onScrubEnd?.call();
  }

  /// [autoPan] false is a PRESS: landing near an end of the rail is not a
  /// push toward it. R10 R6 found this the expensive way — the rail runs
  /// this from `onPointerDown` as well as from drag updates, so a plain tap
  /// inside the edge band scrolled the sheet under the finger before the
  /// frame was even resolved. The band is a fraction of the viewport, so
  /// the shorter the rail the larger the share of it that was untappable.
  void selectFrameFromRailGlobalPosition(
    Offset globalPosition, {
    bool autoPan = true,
  }) {
    final renderObject = _state._railScrubViewportKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox) {
      return;
    }

    final localY = renderObject.globalToLocal(globalPosition).dy;
    if (autoPan) {
      _autoPanRailEdge(renderObject, localY);
    }
    final frameIndex = _frameIndexForRailLocalY(localY);
    if (frameIndex == null) {
      return;
    }

    selectClampedFrameFromRail(frameIndex);
  }

  /// Edge auto-pan (UI-R10 #24): a rail scrub past the viewport edge
  /// scrolls the frame axis under it — with the endless growth feeding
  /// rows ahead, the rail drag alone reaches ANY frame (the scrollbar
  /// clamps at the built extent by design).
  void _autoPanRailEdge(RenderBox viewport, double localY) {
    if (!viewport.hasSize) {
      return;
    }
    edgeAutoPanOvershoot(
      _state._frameScrollController,
      edgeAutoPanDelta(localY, viewport.size.height),
    );
  }

  void resetRailScrubTracking() {
    _state._lastRailScrubbedFrameIndex = null;
  }
}
