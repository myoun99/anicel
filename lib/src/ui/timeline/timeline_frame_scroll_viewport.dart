import 'package:flutter/material.dart';

import 'timeline_scroll_viewport.dart';

/// Horizontal scroll viewport and content wrapper for the timeline frame grid.
///
/// This widget only preserves the existing frame grid scroll/layout structure.
/// Scroll controller ownership, synchronization, sizing decisions, and timeline
/// range semantics remain with [LayerTimelineGrid].
///
/// ↩️The scrollable itself is [TimelineScrollViewport] now, shared with the
/// five other timeline axes (F-4). What is left here is this axis's own
/// furniture: the scrollbar's keyed subtree and the content's size.
///
/// 🚨**THE CROSS AXIS IS GIVEN, NOT SHRINK-WRAPPED.** A sliver viewport
/// EXPANDS across its axis to fill its container, where the single-child one
/// took its child's size — so the same tree that worked before throws
/// 「Horizontal viewport was given unbounded height」 here, measured on the
/// first run. The height was always known at this site ([contentHeight]);
/// it just used to arrive from the inside.
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
      child: SizedBox(
        height: contentHeight,
        child: TimelineScrollViewport(
          viewportKey: const ValueKey<String>('timeline-frame-scroll-viewport'),
          controller: controller,
          axis: Axis.horizontal,
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
