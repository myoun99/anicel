part of '../storyboard_panel.dart';

/// THE HORIZONTAL SCROLL — following the controller, the endless trailing
/// frames the sheet grows as the user scrolls past its end, and the ruler
/// edge that auto-pans — as its own object.
///
/// 🚨A collaborator carved out of `_StoryboardPanelState` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: seven State members
/// shared, the scroll controller above all. It reaches the State through
/// `_state` and rebuilds through `_rebuild`.
class _StoryboardScroll {
  _StoryboardScroll(this._state);

  final _StoryboardPanelState _state;

  int _endlessTrailingFrames = 0;

  void handleHorizontalScroll() {
    if (!_state._horizontalController.hasClients) {
      return;
    }
    _watchHorizontalScrollActivity();
    final offset = _state._horizontalController.offset;
    final position = _state._horizontalController.position;
    final next = endlessTrailingFrames(
      baseFrameCount: _state._totalFrames(
        _state.widget.project,
        buildStoryboardTimelineLayout(_state.widget.project),
      ),
      currentTrailingFrames: _endlessTrailingFrames,
      scrollOffset: offset,
      viewportExtent: position.viewportDimension,
      frameCellExtent: _state._scale.pixelsPerFrame,
      // Past-content cells vanish once scrolled out of view (UI-R12 #16,
      // the timeline's shrink rule): discrete moves may shrink right
      // away, gesture pixels wait for the settle listener.
      allowShrink: !position.isScrollingNotifier.value,
    );
    // Repaint-only scroll (UI-R15→R16): the offset rides the value
    // channel (translate), the quantized bucket triggers the painters;
    // widgets rebuild ONLY when the endless extent itself changes.
    _state._horizontalScrollOffset.value = offset;
    _state._horizontalWindowBucket.value = timelineFrameWindowBucketOf(
      offset: offset,
      cellExtent: _state._scale.pixelsPerFrame,
    );
    if (next != _endlessTrailingFrames) {
      _state._rebuild(() => _endlessTrailingFrames = next);
    }
  }

  ScrollPosition? _watchedHorizontalPosition;

  void _watchHorizontalScrollActivity() {
    final position = _state._horizontalController.position;
    if (identical(position, _watchedHorizontalPosition)) {
      return;
    }
    _watchedHorizontalPosition?.isScrollingNotifier.removeListener(
      handleHorizontalScrollActivity,
    );
    _watchedHorizontalPosition = position;
    position.isScrollingNotifier.addListener(handleHorizontalScrollActivity);
  }

  /// Scroll settled: apply the lazy endless SHRINK (UI-R12 #16 — the
  /// timeline's rule, unified): the extent contracts back toward the
  /// cuts' end so the scrollbar thumb recovers, never mid-gesture.
  void handleHorizontalScrollActivity() {
    final position = _watchedHorizontalPosition;
    if (position == null || position.isScrollingNotifier.value) {
      return;
    }
    final next = endlessTrailingFrames(
      baseFrameCount: _state._totalFrames(
        _state.widget.project,
        buildStoryboardTimelineLayout(_state.widget.project),
      ),
      currentTrailingFrames: _endlessTrailingFrames,
      scrollOffset: position.pixels,
      viewportExtent: position.viewportDimension,
      frameCellExtent: _state._scale.pixelsPerFrame,
      allowShrink: true,
    );
    if (next != _endlessTrailingFrames && _state.mounted) {
      _state._rebuild(() => _endlessTrailingFrames = next);
    }
  }

  /// Ruler edge auto-pan (UI-R12 #16, the timeline's rule unified): a
  /// scrub past the viewport edge pans the strip — rightward it
  /// deliberately OVERSHOOTS the built extent, and the growth listener
  /// materializes the frames the overshot view needs. The scrollbar and
  /// scroll physics stay clamped at the built cells.
  void autoPanRulerEdge(double delta) {
    if (!_state._horizontalController.hasClients) {
      return;
    }
    final position = _state._horizontalController.position;
    final target = math.max(0.0, position.pixels + delta);
    if (target != position.pixels) {
      _state._horizontalController.jumpTo(target);
    }
  }
}
