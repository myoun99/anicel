import 'package:flutter/material.dart';

import '../widgets/app_scrollbar.dart';

/// The timeline's bottom scrollbar rail: rail chrome (background + top
/// hairline) around the shared [AppControllerScrollbar]. The rail height is
/// the hit lane; the thumb inside stays visually thin.
class TimelineHorizontalScrollbarRail extends StatelessWidget {
  const TimelineHorizontalScrollbarRail({
    super.key,
    required this.controller,
    required this.viewportWidth,
    required this.contentWidth,
    required this.height,
  });

  static const double _minimumThumbWidth = 32;

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
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: AppControllerScrollbar(
        controller: controller,
        axis: Axis.horizontal,
        minThumbExtent: _minimumThumbWidth,
        fallbackViewportExtent: viewportWidth,
        fallbackContentExtent: contentWidth,
        laneKey: const ValueKey<String>('timeline-horizontal-scrollbar-track'),
        thumbKey: const ValueKey<String>('timeline-horizontal-scrollbar-thumb'),
      ),
    );
  }
}
