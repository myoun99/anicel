import 'package:flutter/material.dart';

import '../widgets/app_scrollbar.dart';

/// The timeline's bottom scrollbar rail: the shared [AppControllerScrollbar]
/// under a top hairline, on the panel's own surface. The rail height is the
/// hit lane; the thumb inside stays visually thin.
class TimelineHorizontalScrollbarRail extends StatelessWidget {
  const TimelineHorizontalScrollbarRail({
    super.key,
    required this.controller,
    required this.viewportWidth,
    required this.contentWidth,
    required this.height,
  });


  final ScrollController controller;
  final double viewportWidth;
  final double contentWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: const ValueKey<String>('timeline-bottom-scrollbar-rail'),
      height: height,
      // The top hairline separates the rail from the rows above; the fill it
      // wore went at F-73 ② (유저 2026-09-11: 「타임라인패널의 스크롤바도 배경이
      // 검정색이니까. 그냥 투명하게 할수는없나?」) — the lane is the panel's own
      // surface, and the thumb alone marks it.
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: AppControllerScrollbar(
        controller: controller,
        axis: Axis.horizontal,
        minThumbExtent: AppScrollbarThumb.minimum,
        fallbackViewportExtent: viewportWidth,
        fallbackContentExtent: contentWidth,
        laneKey: const ValueKey<String>('timeline-horizontal-scrollbar-track'),
        thumbKey: const ValueKey<String>('timeline-horizontal-scrollbar-thumb'),
      ),
    );
  }
}
