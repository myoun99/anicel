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
    this.bottomOverlaySpan = 0,
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

  /// ⑩ (user, 2026-08-12): 「캔버스 패널 가로 스크롤바가 간편 오버레이와
  /// 겹치니 스크롤바를 더 위로」.
  ///
  /// How much floats over the floor's BOTTOM edge without framing the
  /// artwork — the collapsed row, which is drawn on the drawing with no
  /// ground of its own.
  ///
  /// ⚠️Deliberately NOT part of [insets]. That one deflates the window the
  /// artist looks through, and adding this to it would shift the picture
  /// every time the panel folded. A control that must not be buried asks
  /// this instead — the same distinction [leftRailBand] draws for the side
  /// columns: where something IS, versus what the framing owes it.
  final double bottomOverlaySpan;

  /// The cover for the floor [context] sits on, or null when it is not the
  /// floor at all.
  static CanvasFloorInsets? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasFloorInsets>();

  @override
  bool updateShouldNotify(CanvasFloorInsets oldWidget) =>
      oldWidget.insets != insets ||
      oldWidget.leftRailBand != leftRailBand ||
      oldWidget.rightRailBand != rightRailBand ||
      oldWidget.bottomOverlaySpan != bottomOverlaySpan;
}

/// The stage's outer two surfaces, published ONCE for every canvas panel in
/// the app.
///
/// 유저, R4 #2: 캔버스 베이스 패널들 배경색 통일하고싶어. 캔버스패널에서
/// 배경색 정하잖아. 그거 그대로 따라가게. 즉 바꾸면 바뀌게.
///
/// ⛔Deliberately NOT a parameter threaded to each host. It effectively was:
/// the drawing floor dug the values out of the session and passed them down,
/// and the timesheet, the conte, the cut envelope and the media viewer each
/// quietly took `BrushCanvasPanel`'s constant defaults instead — four canvas
/// panels sitting on hard black while the floor followed the project, and a
/// fifth would have joined them. The same lesson `CanvasPillSide` was built
/// on: when five widgets need one fact about WHERE THEY ARE, the shell says
/// it once rather than five constructors remembering to ask.
///
/// The paper is not here. It belongs to the CUT being shown, so a sheet panel
/// and the drawing floor legitimately disagree about it; these two are the
/// room the work is being done in, and there is only one room.
class CanvasStageColors extends InheritedWidget {
  const CanvasStageColors({
    super.key,
    required this.backdropArgb,
    required this.pasteboardArgb,
    required this.pasteboardMargin,
    required super.child,
  });

  /// The floor everything lies on, beyond where the pasteboard stops.
  final int backdropArgb;

  /// The working surface around the stage — RGBA, so thinning it reveals the
  /// backdrop.
  final int pasteboardArgb;

  /// How far past each canvas edge the pasteboard SHOWS, in canvas widths
  /// and heights.
  final double pasteboardMargin;

  static CanvasStageColors? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasStageColors>();

  @override
  bool updateShouldNotify(CanvasStageColors oldWidget) =>
      oldWidget.backdropArgb != backdropArgb ||
      oldWidget.pasteboardArgb != pasteboardArgb ||
      oldWidget.pasteboardMargin != pasteboardMargin;
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
