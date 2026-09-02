part of '../layer_timeline_grid.dart';

/// THE SCROLL — the two axes the grid scrolls on, their controllers kept
/// in step with the owner, the effective offsets and the activity watch —
/// as its own object.
///
/// 🚨A collaborator carved out of `_LayerTimelineGridState` (the audit's
/// SRP cut, 2026-09-02). Measured before cutting: eleven State members
/// shared, the controllers above all. It reaches the State through
/// `_state` and rebuilds through `_rebuild`.
class _LayerGridScroll {
  _LayerGridScroll(this._state);

  final _LayerTimelineGridState _state;

  /// Re-read the layer-axis offset from the position itself.
  ///
  /// 🚨The position's pixels move WITHOUT notifying: when the rows shrink
  /// out from under it, `ScrollPosition` silently `correctPixels` back into
  /// range during layout, and [handleVerticalScroll] never runs. An offset
  /// cached from notifications alone therefore freezes at the pre-collapse
  /// value — and (UI-R5 #3) comes back to life the moment the rows grow
  /// again, because the clamp below is applied to a COPY. Expanding an
  /// attach group then scrolled the view down by exactly the rows that had
  /// been folded, cancelling the insertion the user had just asked to see.
  void readVerticalScrollOffset() {
    final position = _state._verticalPosition;
    if (position != null && position.hasPixels) {
      _state._verticalScrollOffset = position.pixels;
    }
  }

  /// Layer-axis virtualization: re-plan only when the scroll crosses a
  /// row boundary (the ≥2-row overscan absorbs sub-row movement).
  ///
  /// ⛔The crossing publishes a TOKEN; it does not `setState`. See
  /// [_state._rowWindowBucket] for what the `setState` was costing — and note that
  /// the saving is not the widgets, it is the row MODEL above them.
  void handleVerticalScroll() {
    final offset = _state._verticalScrollController.hasClients
        ? _state._verticalScrollController.offset
        : 0.0;
    if (offset == _state._verticalScrollOffset) {
      return;
    }
    final rowExtent = _state._metrics.layerRowHeight;
    final newBucket = (offset / rowExtent).floor();
    _state._verticalScrollOffset = offset;
    // ⚠️Compared against the NOTIFIER, not against a bucket recomputed from
    // the old offset. They agree while nothing else moves, but a row-height
    // change or a collapse moves the boundary under a stationary scroll —
    // and then the "old" bucket is a number nobody ever rendered.
    if (newBucket != _state._rowWindowBucket.value) {
      _state._rowWindowBucket.value = newBucket;
    }
  }

  /// Frame-axis scroll (UI-R9 #12a): NO setState per pixel. The offset
  /// notifier drives the ruler translate; the window bucket drives the
  /// re-windowing; only an ENDLESS-extent growth (a real relayout, rare)
  /// still rebuilds the grid.
  void handleHorizontalScroll() {
    if (!_state._horizontalScrollController.hasClients) {
      return;
    }
    _watchHorizontalScrollActivity();
    final offset = _state._horizontalScrollController.offset;
    if (offset == _state._frameAxisOffset.value) {
      return;
    }
    _state._frameAxisOffset.value = offset;
    // Quantized span buckets (UI-R16): the bucket notifier — the
    // painters' repaint trigger — fires once per span crossing, so the
    // frames between crossings are pure translation.
    final bucket = timelineFrameWindowBucketOf(
      offset: offset,
      cellExtent: _state._metrics.frameCellWidth,
    );
    if (bucket != _state._frameWindowBucket.value) {
      _state._frameWindowBucket.value = bucket;
    }
    final position = _state._horizontalScrollController.position;
    final nextTrailingFrames = endlessTrailingFrames(
      baseFrameCount: _state._visibleFrameCount,
      currentTrailingFrames: _state._endlessTrailingFrames,
      scrollOffset: offset,
      viewportExtent: position.viewportDimension,
      frameCellExtent: _state._metrics.frameCellWidth,
      // Discrete moves (wheel ticks, programmatic jumps) may shrink right
      // away; gesture pixels never rescale the extent mid-drag (the
      // settle listener below applies the release).
      allowShrink: !position.isScrollingNotifier.value,
    );
    if (nextTrailingFrames != _state._endlessTrailingFrames) {
      _state._rebuild(() => _state._endlessTrailingFrames = nextTrailingFrames);
    }
  }

  void _watchHorizontalScrollActivity() {
    final position = _state._horizontalScrollController.position;
    if (identical(position, _state._watchedHorizontalPosition)) {
      return;
    }
    _state._watchedHorizontalPosition?.isScrollingNotifier.removeListener(
      handleHorizontalScrollActivity,
    );
    _state._watchedHorizontalPosition = position;
    position.isScrollingNotifier.addListener(handleHorizontalScrollActivity);
  }

  /// Scroll settled: apply the lazy endless SHRINK (UI-R9 #11) — the
  /// extent contracts back toward the base + runway so the scrollbar
  /// thumb recovers, never mid-gesture.
  void handleHorizontalScrollActivity() {
    final position = _state._watchedHorizontalPosition;
    if (position == null || position.isScrollingNotifier.value) {
      return;
    }
    final nextTrailingFrames = endlessTrailingFrames(
      baseFrameCount: _state._visibleFrameCount,
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

  double effectiveHorizontalScrollOffset({
    required double requestedOffset,
    required double viewportWidth,
  }) {
    final totalFrameContentWidth =
        _state._renderedFrameCount * _state._metrics.frameCellWidth;

    return resolveTimelineHorizontalOffset(
      requestedOffset: requestedOffset,
      totalContentWidth: totalFrameContentWidth,
      viewportWidth: viewportWidth,
    ).effectiveOffset;
  }

  void synchronizeHorizontalScrollController(double effectiveOffset) {
    if (!_state._horizontalScrollController.hasClients ||
        _state._horizontalScrollController.offset == effectiveOffset ||
        _state._scheduledHorizontalOffsetCorrection == effectiveOffset) {
      return;
    }

    _state._scheduledHorizontalOffsetCorrection = effectiveOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_state.mounted || !_state._horizontalScrollController.hasClients) {
        _state._scheduledHorizontalOffsetCorrection = null;
        return;
      }

      final maxScrollExtent =
          _state._horizontalScrollController.position.maxScrollExtent;
      final targetOffset = effectiveOffset
          .clamp(0.0, maxScrollExtent)
          .toDouble();

      _state._scheduledHorizontalOffsetCorrection = null;
      if (_state._horizontalScrollController.offset != targetOffset) {
        _state._horizontalScrollController.jumpTo(targetOffset);
      }
    });
  }

  /// The vertical mirror of the horizontal clamp machinery (UI-R9 #9):
  /// collapsing transform lanes SHRINKS the row content, but the scroll
  /// controller's pixels don't move on their own — windowing from the
  /// stale, now-out-of-range offset inflated the leading spacer and pushed
  /// every section downward (top alignment broke).
  double _effectiveVerticalScrollOffset({
    required double requestedOffset,
    required double viewportHeight,
    required double contentHeight,
  }) {
    final maxOffset = math.max(0.0, contentHeight - viewportHeight);
    return requestedOffset.clamp(0.0, maxOffset).toDouble();
  }

  void synchronizeVerticalScrollController(double effectiveOffset) {
    if (!_state._verticalScrollController.hasClients ||
        _state._verticalScrollController.offset == effectiveOffset ||
        _state._scheduledVerticalOffsetCorrection == effectiveOffset) {
      return;
    }

    _state._scheduledVerticalOffsetCorrection = effectiveOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_state.mounted || !_state._verticalScrollController.hasClients) {
        _state._scheduledVerticalOffsetCorrection = null;
        return;
      }

      final maxScrollExtent =
          _state._verticalScrollController.position.maxScrollExtent;
      final targetOffset = effectiveOffset
          .clamp(0.0, maxScrollExtent)
          .toDouble();

      _state._scheduledVerticalOffsetCorrection = null;
      if (_state._verticalScrollController.offset != targetOffset) {
        _state._verticalScrollController.jumpTo(targetOffset);
      }
    });
  }
}
