import 'package:flutter/widgets.dart';

/// PEN-10: a scroll position that keeps its children HITTABLE through a
/// coasting (ballistic/driven) activity while a pen is nearby.
///
/// The framework ignore-pointers the viewport's children for the whole
/// life of any scroll activity, so a pen landing mid-coast can never
/// reach the timeline's edit layers — its drag falls to the scroll
/// recognizer no matter how the arena is tuned. [StylusGlideStop]'s
/// hover-stop kills the coast when the pen APPROACHES with movement;
/// this position covers the remaining window (a stationary hovering pen,
/// or a pen re-landing right after its last event) by lifting the
/// ignore-pointer for coasting activities while [penNearby] is set.
///
/// A live finger DRAG keeps the framework's ignore-pointer: yanking
/// hit-tests under a scrolling finger protects cells from accidental
/// presses, and pens hover while fingers scroll.
class PenFriendlyScrollController extends ScrollController {
  PenFriendlyScrollController();

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return PenFriendlyScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class PenFriendlyScrollPosition extends ScrollPositionWithSingleContext {
  PenFriendlyScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  bool _penNearby = false;

  /// Marked by [StylusGlideStop] on stylus hover/down (cleared shortly
  /// after the pen's last event): while set, coasting activities stop
  /// hiding the viewport's children from hit-testing.
  set penNearby(bool value) {
    if (_penNearby == value) {
      return;
    }
    _penNearby = value;
    _applyIgnorePointer();
  }

  @override
  void beginActivity(ScrollActivity? newActivity) {
    super.beginActivity(newActivity);
    if (newActivity != null) {
      _applyIgnorePointer();
    }
  }

  void _applyIgnorePointer() {
    final current = activity;
    if (current == null) {
      return;
    }
    final coasting =
        current is BallisticScrollActivity || current is DrivenScrollActivity;
    context.setIgnorePointer(
      current.shouldIgnorePointer && !(_penNearby && coasting),
    );
  }
}
