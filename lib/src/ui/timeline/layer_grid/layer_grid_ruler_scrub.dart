part of '../layer_timeline_grid.dart';

/// THE RULER SCRUB — a press or drag on the ruler picking a frame, the
/// clamp, the auto-pan at the edge and the tracking that ends with the
/// scrub — as its own object.
///
/// 🚨A collaborator carved out of `_LayerTimelineGridState` (the audit's
/// SRP cut, 2026-09-02). Measured before cutting: five State members
/// shared. It reaches the State through `_state`.
class _LayerGridRulerScrub {
  _LayerGridRulerScrub(this._state);

  final _LayerTimelineGridState _state;

  int? _frameIndexForRulerLocalX(double localX) {
    return frameIndexFromLocalX(
      localX: localX,
      horizontalScrollOffset: _state._lastEffectiveHorizontalScrollOffset,
      frameCellWidth: _state._metrics.frameCellWidth,
      visibleFrameCount: _state._renderedFrameCount,
    );
  }

  void selectClampedFrameFromRuler(int frameIndex) {
    // The endless runway IS the selectable tail now (UI-R10 #23 retired
    // the fixed safety frames): clamp against the BUILT extent.
    final frame = _state._rulerScrubbedFrame.next(
      clampFrameIndex(
        frameIndex: frameIndex,
        visibleFrameCount: _state._renderedFrameCount,
      ),
    );
    if (frame == null) {
      return;
    }
    (_state.widget.hooks.onScrubFrame ?? _state.widget.hooks.onSelectFrame)(
      frame,
    );
  }

  /// The scrub gesture's release (raw pointer up/cancel — fires for taps
  /// AND drags, wherever the pointer ends up). Tracking is NOT reset here
  /// so the ruler InkWell's trailing onTap stays deduplicated.
  void endRulerScrub() {
    _state.widget.hooks.onScrubEnd?.call();
  }

  double? _rulerViewportLocalXFromGlobal(Offset globalPosition) {
    final renderObject = _state._rulerScrubViewportKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox) {
      return null;
    }

    return renderObject.globalToLocal(globalPosition).dx;
  }

  void selectFrameFromRulerGlobalPosition(Offset globalPosition) {
    final localX = _rulerViewportLocalXFromGlobal(globalPosition);
    if (localX == null) {
      return;
    }
    _autoPanRulerEdge(localX);

    final frameIndex = _frameIndexForRulerLocalX(localX);
    if (frameIndex == null) {
      return;
    }

    selectClampedFrameFromRuler(frameIndex);
  }

  /// Edge auto-pan (UI-R10 #24, the pro-standard ruler drag): a scrub
  /// pointer past the viewport edge scrolls the frame axis under it.
  /// Rightward it deliberately OVERSHOOTS the built extent (UI-R12 #16):
  /// the ruler drag is THE way past the last built cell — the growth
  /// listener materializes the frames the overshot view needs, while the
  /// scrollbar and scroll physics stay clamped at the built cells.
  void _autoPanRulerEdge(double localX) {
    final viewport = _state._rulerScrubViewportKey.currentContext
        ?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) {
      return;
    }
    edgeAutoPanOvershoot(
      _state._horizontalScrollController,
      edgeAutoPanDelta(localX, viewport.size.width),
    );
  }

  void resetRulerScrubTracking() {
    _state._rulerScrubbedFrame.reset();
  }
}
