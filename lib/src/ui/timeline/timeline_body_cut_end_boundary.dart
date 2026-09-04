import 'package:flutter/material.dart';

import 'timeline_cut_end_boundary_line.dart';

class TimelineBodyCutEndBoundary extends StatelessWidget {
  const TimelineBodyCutEndBoundary({
    super.key = const ValueKey<String>('timeline-cut-end-boundary'),
    required this.left,
    this.axis = Axis.horizontal,
  });

  /// Main-axis offset of the boundary line (x when horizontal, y when
  /// vertical) — the shared `timelineCutEndBoundaryX` result.
  final double left;

  /// The frame axis direction: a vertical line in the horizontal timeline,
  /// a horizontal line in the X-sheet.
  final Axis axis;

  @override
  Widget build(BuildContext context) =>
      timelineCutEndBoundaryLine(left: left, axis: axis);
}
