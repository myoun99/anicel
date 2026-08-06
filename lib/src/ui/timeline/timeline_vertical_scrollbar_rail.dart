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

/// The timeline's right-edge scrollbar rail: rail chrome (background +
/// side hairlines) around the shared [AppControllerScrollbar]. The rail
/// width is the hit lane; the thumb inside stays visually thin.
class TimelineVerticalScrollbarRail extends StatelessWidget {
  const TimelineVerticalScrollbarRail({
    super.key = const ValueKey<String>('timeline-vertical-scrollbar'),
    required this.controller,
    required this.viewportHeight,
    required this.contentHeight,
    required this.width,
  });

  static const double _minimumThumbHeight = 32;

  final ScrollController controller;
  final double viewportHeight;
  final double contentHeight;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      // The rail's side hairlines are GONE (UI-R18 #3) — the lane color
      // alone separates it from the rows, so with one chrome fill it has to
      // be the level BELOW the rows: a lane is a groove, not a panel.
      decoration: BoxDecoration(color: colorScheme.surfaceContainerLowest),
      child: AppControllerScrollbar(
        controller: controller,
        axis: Axis.vertical,
        minThumbExtent: _minimumThumbHeight,
        fallbackViewportExtent: viewportHeight,
        fallbackContentExtent: contentHeight,
        laneKey: const ValueKey<String>('timeline-vertical-scrollbar-track'),
        thumbKey: const ValueKey<String>('timeline-vertical-scrollbar-thumb'),
      ),
    );
  }
}
