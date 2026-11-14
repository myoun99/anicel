part of '../storyboard_panel.dart';

/// THE HORIZONTAL SCROLL's own verb — the ruler edge that auto-pans — as
/// its own object. Following the controller and the endless trailing room
/// left for [TimelineFrameAxisFollower], the one the timeline grids hold
/// too (the audit's clone scan, 2026-09-03).
///
/// 🚨A collaborator carved out of `_StoryboardPanelState` (the audit's SRP
/// cut, 2026-09-02). It reaches the State through `_state`.
class _StoryboardScroll {
  _StoryboardScroll(this._state);

  final _StoryboardPanelState _state;

  /// Ruler edge auto-pan (UI-R12 #16, the timeline's rule unified): a
  /// scrub past the viewport edge pans the strip — rightward it
  /// deliberately OVERSHOOTS the built extent, and the growth listener
  /// materializes the frames the overshot view needs. The scrollbar and
  /// scroll physics stay clamped at the built cells. The ruler holds the
  /// axis while it drags it ([TimelineFrameAxisFollower.hold]), as the
  /// timeline's grids' strips do ([TimelineFrameScrub.dragTo]).
  void autoPanRulerEdge(double delta) {
    _state._frameAxis.hold();
    edgeAutoPanOvershoot(_state._horizontalController, delta);
  }

  /// The ruler scrub let go: the axis comes to rest, its runway past the
  /// end shrunk as the timeline's grids shrink theirs
  /// ([TimelineFrameScrub.endScrub]), and the host commits the scrub.
  void endRulerScrub() {
    _state._frameAxis.letGo();
    _state.widget.onScrubEnd?.call();
  }
}
