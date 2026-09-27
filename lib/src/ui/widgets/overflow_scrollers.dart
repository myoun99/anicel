import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../input/pen_friendly_scroll_controller.dart';
import '../input/scroller_press_hold.dart';

/// A body with a FLOOR: laid out at no less than [minWidth] × [minHeight],
/// and scrolled instead of squeezed when the room is smaller.
///
/// 🚨ONE TREE SHAPE whether the body fits or not (F-103). Both scrollers are
/// always there, around a box that is the room where the room holds the
/// floor and the floor where it does not, so crossing the floor changes how
/// far they scroll, never what the body sits in. Mounted only on the axis
/// that overflowed, crossing the floor changed the parent chain and the
/// body's state was new: a docked viewer read its file again when a
/// neighbour opened (the dock says whose words those were), and a list came
/// back scrolled to the top. With nothing to scroll they take no drag and
/// no wheel (the platform physics accept no user offset at zero extent) and
/// draw no bar.
///
/// ⛔ONE COPY. The dock, the media pool and the import window's table each
/// wrote this — the last one's comment named the second as its model — and
/// only the dock had learned the tree-shape law (card
/// `overflow-escape-three-copies`, 2026-09-28).
///
/// 🚨★★★THE SCROLLERS ARE PEN-FRIENDLY. A `ScrollPosition` ignore-pointers
/// its viewport's CHILDREN for the life of any scroll activity, and the
/// children here are the body itself. So while one of these coasts, a pen
/// or finger landing on the body reaches nothing and the press falls
/// through to whatever is behind. 유저 2026-08-29 「어차피 같은상황에서
/// **타임라인을 옆 패널로 둬도 문제 발생**했단얘기니까」 — whatever is squeezed
/// gets it, so the fix belongs to the thing that squeezes.
///
/// The controllers are THIS State's (F-103), so they live exactly as long as
/// the scroll views they drive. They used to be one pair for a whole dock
/// group, and a keep-alive tab stays built offstage with its scrollers — so
/// two kept tabs that both overflowed put one controller on two views, and
/// `PanelScrollbar`, which reads a controller only while it has exactly one
/// position, stood the shown tab's bar down the next time the dock moved.
class OverflowScrollers extends StatefulWidget {
  const OverflowScrollers({
    super.key,
    this.minWidth = 0,
    this.minHeight = 0,
    required this.child,
  });

  final double minWidth;
  final double minHeight;
  final Widget child;

  @override
  State<OverflowScrollers> createState() => _OverflowScrollersState();
}

class _OverflowScrollersState extends State<OverflowScrollers> {
  final ScrollController _vertical = PenFriendlyScrollController();
  final ScrollController _horizontal = PenFriendlyScrollController();

  @override
  void initState() {
    super.initState();
    // One surface scrolled two ways, not a scroller inside a scroller.
    scrollTogether(_horizontal, _vertical);
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  /// The room as it was given on an axis where it holds the floor, and
  /// exactly the floor on an axis where it does not.
  BoxConstraints _floored(BoxConstraints room) => BoxConstraints(
    minWidth: room.maxWidth < widget.minWidth ? widget.minWidth : room.minWidth,
    maxWidth: math.max(room.maxWidth, widget.minWidth),
    minHeight: room.maxHeight < widget.minHeight
        ? widget.minHeight
        : room.minHeight,
    maxHeight: math.max(room.maxHeight, widget.minHeight),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      controller: _horizontal,
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        controller: _vertical,
        child: ConstrainedBox(
          constraints: _floored(constraints),
          child: widget.child,
        ),
      ),
    ),
  );
}
