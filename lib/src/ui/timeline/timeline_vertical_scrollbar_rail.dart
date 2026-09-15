import 'package:flutter/material.dart';

import '../widgets/app_scrollbar.dart';

class TimelineVerticalScrollbarSlot extends StatelessWidget {
  const TimelineVerticalScrollbarSlot({
    super.key = const ValueKey<String>('timeline-vertical-scrollbar-slot'),
    required this.width,
    required this.height,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, height: height);
  }
}

/// The timeline's right-edge scrollbar rail: the shared
/// [AppControllerScrollbar] on the panel's own surface. The rail width is the
/// hit lane; the thumb inside stays visually thin.
class TimelineVerticalScrollbarRail extends StatelessWidget {
  const TimelineVerticalScrollbarRail({
    super.key = const ValueKey<String>('timeline-vertical-scrollbar'),
    required this.controller,
    required this.viewportHeight,
    required this.contentHeight,
    required this.width,
  });


  final ScrollController controller;
  final double viewportHeight;
  final double contentHeight;
  final double width;

  @override
  Widget build(BuildContext context) {
    // The rail's side hairlines went at UI-R18 #3, leaving a fill one level
    // BELOW the rows to separate it — "a lane is a groove, not a panel". The
    // fill went at F-73 ② (유저 2026-09-11: 「타임라인패널의 스크롤바도 배경이
    // 검정색이니까. 그냥 투명하게 할수는없나?」): the rail is the panel's own
    // surface now, and the thumb alone marks the lane.
    return AppControllerScrollbar(
      controller: controller,
      axis: Axis.vertical,
      minThumbExtent: AppScrollbarThumb.minimum,
      fallbackViewportExtent: viewportHeight,
      fallbackContentExtent: contentHeight,
      laneKey: const ValueKey<String>('timeline-vertical-scrollbar-track'),
      thumbKey: const ValueKey<String>('timeline-vertical-scrollbar-thumb'),
    );
  }
}
