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

}
