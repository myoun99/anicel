import 'package:flutter/widgets.dart';

/// One rail column's vertical extent, in the floor's own coordinates.
typedef CanvasFloorBand = ({double top, double bottom});

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
    this.leftRailBand,
    this.rightRailBand,
    required super.child,
  });

  /// The edges of the floor covered by panels floating over it.
  ///
  /// A band that is only half covered still costs the whole edge here,
  /// because framing cannot put half a picture behind a panel.
  final EdgeInsets insets;

  /// WHERE the side columns actually are, vertically.
  ///
  /// A rail panel keeps the height it was left at, so an open rail covers a
  /// band rather than an edge. Something deciding whether the rail is in the
  /// way of one small floating control has to ask about the band: stepping
  /// aside for the whole edge is what made the vertical scrollbar drift
  /// inward beside a short panel that was nowhere near it (유저, R3 #5).
  final CanvasFloorBand? leftRailBand;
  final CanvasFloorBand? rightRailBand;

  /// The cover for the floor [context] sits on, or null when it is not the
  /// floor at all.
  static CanvasFloorInsets? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasFloorInsets>();

  @override
  bool updateShouldNotify(CanvasFloorInsets oldWidget) =>
      oldWidget.insets != insets ||
      oldWidget.leftRailBand != leftRailBand ||
      oldWidget.rightRailBand != rightRailBand;
}

/// Whether [band] overlaps the vertical range [top]..[bottom].
bool canvasFloorBandIntrudes(
  CanvasFloorBand? band, {
  required double top,
  required double bottom,
}) => band != null && band.bottom > top && band.top < bottom;

// ⛔`CanvasPillSide` is gone (유저, R3 #6). It answered "which top CORNER
// does the pill take", and the answer is now neither: 알약은 상단중앙. A
// centred pill needs no rule about which hand the strip is under, so the
// InheritedWidget that carried the answer had nothing left to say.
