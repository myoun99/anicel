part of '../xsheet_timeline_grid.dart';

/// THE FRAME SCROLL — the frame axis the X-sheet scrolls down: its
/// controller kept in step with the owner, the effective offset, the
/// activity watch, how many frames are rendered and visible, and the
/// windowed frame geometry it publishes — as its own object.
///
/// 🚨A collaborator carved out of `_XSheetTimelineGridState` (the audit's
/// SRP cut, 2026-09-02). It reaches the State through `_state` and
/// rebuilds through `_rebuild`.
class _XSheetGridFrameScroll {
  _XSheetGridFrameScroll(this._state);

  final _XSheetTimelineGridState _state;

  TimelineFrameGeometry _baseFrameGeometry() => TimelineFrameGeometry(
    frameCellExtent: _state._metrics.frameCellWidth,
    frameStartIndex: 0,
    frameEndIndexExclusive: renderedFrameCount,
  );

  TimelineFrameGeometry _windowedFrameGeometryValue() {
    final base = _baseFrameGeometry();
    final cellExtent = base.frameCellExtent;
    if (_state._frameViewportExtent <= 0 || cellExtent <= 0) {
      return base;
    }
    final spanPx = timelineFrameWindowSpanFor(cellExtent) * cellExtent;
    return base.windowed(
      originPx: math.max(
        0.0,
        _state._frameWindowBucket.value * spanPx - timelineFrameWindowMarginPx,
      ),
      extentPx: _state._frameViewportExtent + 2 * timelineFrameWindowMarginPx,
    );
  }

  void handleFrameWindowBucket() {
    _state._windowedFrameGeometry.value = _windowedFrameGeometryValue();
  }

  /// The handle every column follows (see [_state._windowedFrameGeometry]).
  ///
  /// EVERY kind takes the windowed one now: the sparse columns' span
  /// overlays are placed by [TimelineFrameSpanLayout] at layout time, so a
  /// window sliding under them carries them along.
  ValueNotifier<TimelineFrameGeometry> publishFrameGeometry(LayerKind kind) {
    _state._frameGeometry.value = _baseFrameGeometry();
    _state._windowedFrameGeometry.value = _windowedFrameGeometryValue();
    return _state._windowedFrameGeometry;
  }

  int get _visibleFrameCount =>
      _state._rangeGestures.frameRangePolicy.visibleFrameCount;

  /// Render extent (UI-R12 #16 contract): the cells scrolled into
  /// existence PLUS the viewport fill — no runway beyond. Scroll physics
  /// and the rail clamp here; the frame-rail edge-drag overshoots and the
  /// growth listener materializes what the overshot view needs.
  int get renderedFrameCount => math.max(
    _visibleFrameCount + _state._frameAxis.trailingFrames,
    _state._viewportFillFrameCells,
  );

  double get _totalFrameContentHeight =>
      renderedFrameCount * _state._metrics.frameCellWidth;

  double effectiveFrameScrollOffset({
    required double requestedOffset,
    required double viewportExtent,
  }) {
    // Same offset policy as the horizontal grid, transposed to y.
    return resolveTimelineHorizontalOffset(
      requestedOffset: requestedOffset,
      totalContentWidth: _totalFrameContentHeight,
      viewportWidth: viewportExtent,
    ).effectiveOffset;
  }

}
