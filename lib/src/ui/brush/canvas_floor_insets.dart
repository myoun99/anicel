import 'package:flutter/widgets.dart';

/// How much of the canvas FLOOR is covered by the panels floating on it.
///
/// The canvas is the app's bottom layer now: it fills everything but the top
/// strip and the two tool strips, and every panel — the always-open timeline,
/// a column opened from a rail — lies ON it rather than beside it. Nobody
/// shrinks the canvas any more, so nothing in the canvas's own layout can tell
/// it which of its edges are hidden.
///
/// This is that answer, published by the shell around the floor dock and read
/// by whichever canvas host is currently lying there. Two properties make it
/// the right shape for the job:
///
///  * A host that is NOT on the floor — the conte in the bottom panel, a
///    timesheet in a rail column — is not under this widget at all, so it
///    reads null and keeps the arithmetic it has always had. Being the floor
///    is a question about WHERE you are, and inherited scope is exactly that
///    question.
///  * Swapping which panel lies on the floor (the top strip's canvas/viewer
///    switch) needs no wiring: the new occupant reads the same value from the
///    same place.
///
/// What to do with it is settled in [canvasVisibleRect]: the verbs that FRAME
/// the artwork deflate by these edges, the ones that describe the SURFACE do
/// not.
class CanvasFloorInsets extends InheritedWidget {
  const CanvasFloorInsets({
    super.key,
    required this.insets,
    required super.child,
  });

  /// The edges of the floor covered by panels floating over it.
  final EdgeInsets insets;

  /// The cover for the floor [context] sits on, or null when it is not the
  /// floor at all.
  static EdgeInsets? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CanvasFloorInsets>()
      ?.insets;

  @override
  bool updateShouldNotify(CanvasFloorInsets oldWidget) =>
      oldWidget.insets != insets;
}
