import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'owning_draggable.dart';

/// THE app's grip band: a thin rule along an edge saying "there is a handle
/// here", plus the one colour ladder every grip climbs.
///
/// It was born on the panel tab (R2 #9 / R3 #9), where a band's THICKNESS
/// says which thing it is saying — 2px for a state you read, 6px for a
/// handle you can reach — and its COLOUR says how close your hand is. Both
/// halves are here rather than in that widget because a second surface now
/// wears the same band: the command pill's `＋`, whose top edge opens the
/// list of kinds ([StrapIconButton]).
///
/// ★The TARGET is a constant [hitExtent] and the band inside it grows toward
/// the edge, so a pointer resting on a grip never finds the thing it is over
/// moving out from under it.
abstract final class GripBand {
  /// The lift/menu zone's extent along the edge. The band is thinner than
  /// this; the target may not move because the band grew.
  static const double hitExtent = 8;

  /// What the band is when it is saying a STATE, and when it is offering a
  /// HANDLE.
  static const double rest = 2;
  static const double reach = 6;

  /// Three rungs, on the three things a hand does: something is NEARBY
  /// (기본색) → the band itself is under the pointer (호버색) → it is being
  /// used (클릭색).
  ///
  /// [idle] is what the band is when nothing is near. The tab's is
  /// transparent — a strip of them would be noise — and the pill's `＋` is
  /// [AppColors.hairlineStrong], because a menu nobody can see is a menu
  /// nobody opens, and a tablet has no pointer to hover with.
  static Color ink({
    required bool nearby,
    required bool hovered,
    required bool active,
    Color idle = Colors.transparent,
  }) {
    if (active) {
      return AppColors.accent;
    }
    if (hovered) {
      return AppColors.gripHover;
    }
    return nearby ? AppColors.hairlineStrong : idle;
  }
}

/// THE band that LIFTS what it stands in — a panel's tab, and a strip's
/// button: [GripBand.hitExtent] along one edge, laid over the thing inside
/// its own box, with the band in it climbing [GripBand.ink]; pressed and
/// moved, it carries [data] ([OwningDraggable]).
///
/// 🗣️I-147 (유저 2026-10-30): 「패널의 아이콘 작은거 버튼있잖아. 그 위에
/// 띠있고. 그거처럼 버튼내에서 공간나누던가해서 오버레이로 위에 띠 띄우는것」
/// · 「이 버튼 자체 탭 띠는 공용으로 다른 사이드띠에도 쓸수있게해서」 — the
/// tab's band, the same code on the strip's buttons. ↩️It was the tab's own
/// until then.
///
/// ★Put it INSIDE the press of what it stands in. That press takes the arena
/// on the first movement, and this asks on the first move too — deeper, so
/// it is asked first and wins for every device (F-126: a stock `Draggable`
/// lost the grip's drag to the tab's claim for a pen, whose slop is eighteen
/// pixels). A press on the band that does not move is still the thing's.
class LiftingGripBand<T extends Object> extends StatefulWidget {
  const LiftingGripBand({
    super.key,
    required this.gripKey,
    required this.data,
    required this.feedback,
    required this.nearby,
    this.atBottom = false,
    this.edgeOutline = 0,
    this.onLifted,
  });

  final Key gripKey;

  /// What the band carries; null for a thing that cannot be lifted, which
  /// keeps the target's footprint and never arms.
  final T? data;

  /// What hangs at the pointer while it is carried.
  final Widget feedback;

  /// Whether the pointer is anywhere on what holds the thing — its panel,
  /// its strip: the first rung of the ladder (유저, R3 #9).
  final ValueListenable<bool> nearby;

  /// Whether the band runs along the thing's bottom edge rather than its
  /// top — a panel whose strip is under it.
  final bool atBottom;

  /// How far in from that edge the band stands — the width of an outline
  /// drawn over it (`EditorPanelTabs.stripEdgeOutline`). The target does not
  /// move for it.
  final double edgeOutline;

  /// Told what is carried as a lift starts, and null as it ends — dropped
  /// or not.
  final ValueChanged<T?>? onLifted;

  @override
  State<LiftingGripBand<T>> createState() => _LiftingGripBandState<T>();
}

class _LiftingGripBandState<T extends Object>
    extends State<LiftingGripBand<T>> {
  bool _hovered = false;
  bool _lifted = false;

  bool get _armed => widget.data != null;

  /// Thick when there is something to grab, thin when it is only offering
  /// itself.
  double get _bandExtent =>
      _armed && (_lifted || _hovered) ? GripBand.reach : GripBand.rest;

  /// The app's one grip ladder ([GripBand.ink]), and NOTHING ELSE (유저,
  /// R3 #9).
  ///
  /// ⛔The ACTIVE rung is gone. The band used to turn accent for the open
  /// tab, which meant the tab you were most likely to want to drag was the
  /// one tab whose band could never say "you may drag me" — the two signals
  /// were sharing one surface and the louder one always won. Which panel is
  /// open is still said twice over without it: the selected tab wears the
  /// body's own fill and its glyph is accent.
  ///
  /// A tab that cannot be lifted has no band at all, which is why the
  /// `_armed` gate stays here rather than moving into the ladder.
  Color _bandColor(bool nearby) => _armed
      ? GripBand.ink(nearby: nearby, hovered: _hovered, active: _lifted)
      : Colors.transparent;

  @override
  Widget build(BuildContext context) {
    Widget grip = MouseRegion(
      cursor: _armed ? SystemMouseCursors.grab : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        key: widget.gripKey,
        height: GripBand.hitExtent,
        // The TARGET is a constant 8px of the edge; the band inside it
        // grows toward the frame, so a pointer resting on the grip never
        // finds the thing it is over moving out from under it.
        //
        // The band itself starts where an outline over that edge ends
        // (F-257, [EditorPanelTabs.stripEdgeOutline]) — the target does
        // not move for it.
        child: Padding(
          padding: widget.atBottom
              ? EdgeInsets.only(bottom: widget.edgeOutline)
              : EdgeInsets.only(top: widget.edgeOutline),
          child: Align(
            alignment: widget.atBottom
                ? Alignment.bottomCenter
                : Alignment.topCenter,
            child: ValueListenableBuilder<bool>(
              valueListenable: widget.nearby,
              builder: (context, nearby, _) => SizedBox(
                // BOTH axes, not just the height. `Align` hands its child
                // LOOSE constraints, and a `ColoredBox` with no child takes
                // `constraints.smallest` — so a band told only how THICK to
                // be laid out 0px wide. It was coloured correctly, on the
                // right edge, climbing the right ladder, and invisible: the
                // whole handle simply did not exist on screen (유저, R4 #6).
                //
                // ⚠️Third time this trap has bitten: R1a collapsed a grip's
                // HEIGHT the same way. A `ColoredBox` is a leaf — it never
                // has a size of its own to fall back on.
                width: double.infinity,
                height: _bandExtent,
                child: ColoredBox(color: _bandColor(nearby)),
              ),
            ),
          ),
        ),
      ),
    );
    final data = widget.data;
    if (data != null) {
      grip = OwningDraggable<T>(
        data: data,
        maxSimultaneousDrags: 1,
        // The avatar origin IS the pointer, so drop regions can split
        // themselves into exact before/after halves from the drag offset.
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: widget.feedback,
        onDragStarted: () {
          setState(() => _lifted = true);
          widget.onLifted?.call(data);
        },
        // onDragEnd covers completion AND cancellation.
        onDragEnd: (_) {
          setState(() => _lifted = false);
          widget.onLifted?.call(null);
        },
        child: grip,
      );
    }
    return grip;
  }
}
