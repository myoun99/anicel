import 'package:flutter/material.dart';

import '../theme/app_scroll_behavior.dart';
import 'app_scrollbar.dart';

/// A panel's CONTENT with its scrollbar in a lane of its own, always there.
///
/// 🚨H35 (유저 2026-09-11): 「툴 라이브러리 패널에 스크롤바가 없어. 눈에
/// 보이는 스크롤바 … 내용물에 공통적으로 스크롤바 넣자. 항상 보이도록. 법
/// 하나로 최대한 통일하면서. 이는 최대한 공용화하고싶어. 일단 툴설정패널에도
/// 넣고싶거든. 당장은 그 두개만」.
///
/// The app had both shapes already and this makes the second one a shared
/// widget. `AppScrollBehavior` lays [PanelScrollbar] OVER every scrollable,
/// but only on a desktop and only while it overflows — so on a tablet these
/// panels had no bar at all, and on a desktop a list that fit had none. The
/// timeline's rails keep a lane of their own; so does this.
///
/// ⚠️IT READS ITS OWN CONTROLLER (one it owns, or the host's), and that is
/// what lets it stand on a tablet: the mobile exclusion in
/// `AppScrollBehavior` is about controller-less views inheriting the route's
/// `PrimaryScrollController`, which a bar cannot tell apart. A bar reading
/// its own controller has no such doubt.
///
/// ⛔The overlay bar is switched off underneath ([UnbarredScrollable]): the
/// lane beside the content IS this content's bar, and a second one laid over
/// it would be the double bar `scrollbar-law` deleted twice.
///
/// When the content fits, the thumb fills the lane — the shared geometry's
/// rule — so the lane stays: 「항상 보이도록」, and CLAUDE.md's 「스크롤바를
/// 자동으로 숨기지 않는다」.
class ContentScrollbar extends StatefulWidget {
  const ContentScrollbar({super.key, required this.builder, this.controller});

  /// The scroll view, built on the controller the lane reads.
  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  /// A controller the host already keeps — the preset panel scrolls its two
  /// lists from code as well — or null for one this widget owns.
  final ScrollController? controller;

  @override
  State<ContentScrollbar> createState() => _ContentScrollbarState();
}

class _ContentScrollbarState extends State<ContentScrollbar> {
  ScrollController? _owned;

  ScrollController get _controller =>
      widget.controller ?? (_owned ??= ScrollController());

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const lane = AppScrollbarLane.wide;
    final controller = _controller;
    // A STACK, not a Row: the content keeps deciding the size, exactly as it
    // did before the lane (a panel pumped somewhere unbounded still lays
    // out), and the lane takes whatever height that is. The padding is the
    // reservation — nothing is ever drawn under the lane.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: lane),
          child: UnbarredScrollable(child: widget.builder(context, controller)),
        ),
        Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          width: lane,
          // NO FILL of its own (F-73 ②, 유저 2026-09-11: 「공용 스크롤바의
          // 배경색을 패널색이랑 맞추고싶음 … 그냥 투명하게 할수는없나?」): the
          // lane is the panel's own surface and the thumb alone marks it. It
          // used to wear the timeline rails' groove — a level below the
          // content beside it, not a panel of its own — and the rails let go
          // of theirs in the same round.
          child: AppControllerScrollbar(
            controller: controller,
            axis: Axis.vertical,
          ),
        ),
      ],
    );
  }
}
