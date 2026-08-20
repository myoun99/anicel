import 'package:flutter/material.dart';
import '../layout/device_grid_scroll_controller.dart';

/// Horizontal scroll viewport and content wrapper for the timeline frame grid.
///
/// This widget only preserves the existing frame grid scroll/layout structure.
/// Scroll controller ownership, synchronization, sizing decisions, and timeline
/// range semantics remain with [LayerTimelineGrid].
class TimelineFrameScrollViewport extends StatelessWidget {
  const TimelineFrameScrollViewport({
    super.key,
    required this.controller,
    required this.contentWidth,
    required this.contentHeight,
    required this.child,
  });

  final ScrollController controller;
  final double contentWidth;
  final double contentHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey<String>('timeline-horizontal-scrollbar-viewport'),
      child: SingleChildScrollView(
        key: const ValueKey<String>('timeline-frame-scroll-viewport'),
        controller: controller,
        scrollDirection: Axis.horizontal,
        child: DeviceGridScrollBody(
          controller: controller,
          axisDirection: AxisDirection.right,
          child: KeyedSubtree(
            key: const ValueKey<String>('timeline-frame-scroll-content'),
            child: SizedBox(
              width: contentWidth,
              height: contentHeight,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
