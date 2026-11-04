import 'package:flutter/widgets.dart';

import '../../models/pasteboard_bounds.dart';

/// One rail column's vertical extent, in the floor's own coordinates.
typedef CanvasFloorBand = ({double top, double bottom});

/// What stands on a canvas panel's LEFT edge, in the middle of the room
/// there ([CanvasFloorInsets.leftPill]) — the brush's values on the
/// drawing (I-34).
///
/// The [width] travels with the widget for `CanvasTransportBand.height`'s
/// reason: nothing the panel frames may lie under it, and framing is read
/// before anything is laid out.
///
/// The same width round the same widget is the same pill: a floor built
/// again with what it had tells the panel lying there nothing new.
class CanvasEdgePill {
  const CanvasEdgePill({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  bool operator ==(Object other) =>
      other is CanvasEdgePill && other.width == width && other.child == child;

  @override
  int get hashCode => Object.hash(width, child);
}

/// How much of the canvas FLOOR is covered by the panels floating on it —
/// and what stands on its left edge ([leftPill]).
///
/// The canvas is the app's bottom layer now: it fills everything but the top
/// strip and the two tool strips, and every panel — the always-open timeline,
/// a column opened from a rail — lies ON it rather than beside it. Nobody
/// shrinks the canvas any more, so nothing in the canvas's own layout can tell
/// it which of its edges are hidden.
///
/// This is that answer, published by the shell around the floor dock and read
/// by the canvas panel lying there, whichever host mounted it
/// (`BrushCanvasPanel`). Two properties make it the right shape for the job:
///
///  * A panel that is NOT on the floor — the conte in the bottom panel, a
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
    this.leftPill,
    required super.child,
  });

  /// The edges of the floor covered by panels floating over it.
  ///
  /// A band that is only half covered still costs the whole edge here,
  /// because framing cannot put half a picture behind a panel.
  ///
  /// The PANELS only. A panel's own capsules are added where framing reads
  /// the window (`BrushCanvasPanel._framingInsets`): the pill, the transport
  /// and the left pill are cover there, the panbars float on the drawing.
  /// ↩️None was until 2026-09-30 — a capsule hiding a corner of the artwork
  /// was the price of not spending a strip of the screen on idle chrome.
  /// The user took that back for the pill (「판정을 알약까지 포함해서
  /// 판정」) and then for the page strip that stood on the left edge
  /// (F-346).
  final EdgeInsets insets;

  /// WHERE the side columns actually are, vertically.
  ///
  /// A rail panel keeps the height it was left at, so an open rail covers a
  /// band rather than an edge. Something deciding whether the rail is in the
  /// way of one small floating control has to ask about the band: stepping
  /// aside for the whole edge is what made the vertical scrollbar drift
  /// inward beside a short panel that was nowhere near it (유저, R3 #5).
  /// ↩️The left column's was published for the page strip on that edge,
  /// went with it under the bars (F-383), and is published again for the
  /// brush pill there (I-34).
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

  /// What stands on the LEFT edge of whichever panel lies on the floor: the
  /// brush's values (I-34, 유저 2026-10-18: 「캔버스 패널의 왼쪽 중앙 알약
  /// 만들어서 거기로 이동」), or null where the workspace stands them on the
  /// top strip.
  ///
  /// 🗣️I-157 (유저 2026-11-04): 「배경에 있는 패널에선 다 브러시사이즈 알약
  /// 보이도록. 배경에 깔린 타임시트용지던 뭐던」 — so the floor says it, as it
  /// says its cover: the canvas, the main viewer and a canvas-base panel
  /// laid there from the top strip stand the same pill, and the same panel
  /// docked in a rail stands none. ↩️The canvas's tab handed it to its own
  /// panel, and nothing else on the floor had one.
  ///
  /// It is seated as the page strip that stood on this edge was
  /// (`_LeftEdgeSeat`): in the middle of the room between the pill's band
  /// and the file's name, and past the left rail where the rail is beside
  /// it. It is cover to framing as that strip was (F-346).
  final CanvasEdgePill? leftPill;

  /// The cover for the floor [context] sits on, or null when it is not the
  /// floor at all.
  static CanvasFloorInsets? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasFloorInsets>();

  @override
  bool updateShouldNotify(CanvasFloorInsets oldWidget) =>
      oldWidget.insets != insets ||
      oldWidget.leftRailBand != leftRailBand ||
      oldWidget.rightRailBand != rightRailBand ||
      oldWidget.bottomOverlaySpan != bottomOverlaySpan ||
      oldWidget.leftPill != leftPill;
}

/// The stage's outer two surfaces, published ONCE by the shell for the
/// canvas panels that stand in the project's room.
///
/// 유저, R4 #2: 캔버스 베이스 패널들 배경색 통일하고싶어. 캔버스패널에서
/// 배경색 정하잖아. 그거 그대로 따라가게. 즉 바꾸면 바뀌게.
///
/// ↩️Reversed for those very panels on 2026-10-03 (F-272: 「그냥 검정색
/// 고정/통일」): a canvas-base panel lies on black and reads nothing here
/// (`BrushCanvasPanel.canvasBase`). The drawing floor is who this speaks to.
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
    this.backdropNone = false,
    this.pasteboardNone = false,
    this.pasteboardSize = PasteboardSize.three,
    this.pasteboardInUse = true,
    required super.child,
  });

  /// The floor everything lies on, beyond where the pasteboard stops.
  final int backdropArgb;

  /// The working surface around the stage — RGBA, so thinning it reveals the
  /// backdrop.
  final int pasteboardArgb;

  /// Whether each plane is ABSENT (F-114) — a checkerboard where it would
  /// be — while its colour above stays kept for the next pick.
  final bool backdropNone;
  final bool pasteboardNone;

  /// The pasteboard's size and whether it is there at all (I-109), as the
  /// project keeps them — the size stays kept while it is off, as a colour
  /// does while its plane is none.
  final PasteboardSize pasteboardSize;
  final bool pasteboardInUse;

  /// How far the pasteboard reaches past the paper — where its plane is
  /// laid, and the wall every picture on the floor stands behind.
  PasteboardReach get pasteboardReach =>
      PasteboardReach.of(size: pasteboardSize, inUse: pasteboardInUse);

  static CanvasStageColors? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasStageColors>();

  @override
  bool updateShouldNotify(CanvasStageColors oldWidget) =>
      oldWidget.backdropArgb != backdropArgb ||
      oldWidget.pasteboardArgb != pasteboardArgb ||
      oldWidget.backdropNone != backdropNone ||
      oldWidget.pasteboardNone != pasteboardNone ||
      oldWidget.pasteboardSize != pasteboardSize ||
      oldWidget.pasteboardInUse != pasteboardInUse;
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
