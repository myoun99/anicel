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

  /// Frame-axis scroll (UI-R9 #12a): NO setState per pixel — only an
  /// endless-extent growth (a real relayout, rare) rebuilds the grid.
  void handleFrameScroll() {
    if (!_state._frameScrollController.hasClients) {
      return;
    }
    _watchFrameScrollActivity();
    final offset = _state._frameScrollController.offset;
    if (offset == _state._frameAxisOffset.value) {
      return;
    }
    _state._frameAxisOffset.value = offset;
    // Quantized span buckets (UI-R16): repaint once per span crossing.
    final bucket = timelineFrameWindowBucketOf(
      offset: offset,
      cellExtent: _state._metrics.frameCellWidth,
    );
    if (bucket != _state._frameWindowBucket.value) {
      _state._frameWindowBucket.value = bucket;
    }
    final position = _state._frameScrollController.position;
    final nextTrailingFrames = endlessTrailingFrames(
      baseFrameCount: _visibleFrameCount,
      currentTrailingFrames: _state._endlessTrailingFrames,
      scrollOffset: offset,
      viewportExtent: position.viewportDimension,
      frameCellExtent: _state._metrics.frameCellWidth,
      // Discrete moves (wheel ticks, programmatic jumps) may shrink right
      // away; gesture pixels never rescale mid-drag (the settle listener
      // applies the release).
      allowShrink: !position.isScrollingNotifier.value,
    );
    if (nextTrailingFrames != _state._endlessTrailingFrames) {
      _state._rebuild(() => _state._endlessTrailingFrames = nextTrailingFrames);
    }
  }

  void _watchFrameScrollActivity() {
    final position = _state._frameScrollController.position;
    if (identical(position, _state._watchedFramePosition)) {
      return;
    }
    _state._watchedFramePosition?.isScrollingNotifier.removeListener(
      handleFrameScrollActivity,
    );
    _state._watchedFramePosition = position;
    position.isScrollingNotifier.addListener(handleFrameScrollActivity);
  }

  /// Scroll settled: the lazy endless SHRINK (UI-R9 #11).
  void handleFrameScrollActivity() {
    final position = _state._watchedFramePosition;
    if (position == null || position.isScrollingNotifier.value) {
      return;
    }
    final nextTrailingFrames = endlessTrailingFrames(
      baseFrameCount: _visibleFrameCount,
      currentTrailingFrames: _state._endlessTrailingFrames,
      scrollOffset: position.pixels,
      viewportExtent: position.viewportDimension,
      frameCellExtent: _state._metrics.frameCellWidth,
      allowShrink: true,
    );
    if (nextTrailingFrames != _state._endlessTrailingFrames && _state.mounted) {
      _state._rebuild(() => _state._endlessTrailingFrames = nextTrailingFrames);
    }
  }

  int get _visibleFrameCount =>
      _state._rangeGestures._frameRangePolicy.visibleFrameCount;

  /// Render extent (UI-R12 #16 contract): the cells scrolled into
  /// existence PLUS the viewport fill — no runway beyond. Scroll physics
  /// and the rail clamp here; the frame-rail edge-drag overshoots and the
  /// growth listener materializes what the overshot view needs.
  int get renderedFrameCount => math.max(
    _visibleFrameCount + _state._endlessTrailingFrames,
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

  void synchronizeFrameScrollController(double effectiveOffset) {
    if (!_state._frameScrollController.hasClients ||
        _state._frameScrollController.offset == effectiveOffset ||
        _state._scheduledFrameOffsetCorrection == effectiveOffset) {
      return;
    }

    _state._scheduledFrameOffsetCorrection = effectiveOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_state.mounted || !_state._frameScrollController.hasClients) {
        _state._scheduledFrameOffsetCorrection = null;
        return;
      }

      final maxScrollExtent =
          _state._frameScrollController.position.maxScrollExtent;
      final targetOffset = effectiveOffset
          .clamp(0.0, maxScrollExtent)
          .toDouble();

      _state._scheduledFrameOffsetCorrection = null;
      if (_state._frameScrollController.offset != targetOffset) {
        _state._frameScrollController.jumpTo(targetOffset);
      }
    });
  }
}
