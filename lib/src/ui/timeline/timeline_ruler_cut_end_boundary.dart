import 'package:flutter/material.dart';

import 'timeline_cut_end_boundary_line.dart';

class TimelineRulerCutEndBoundary extends StatelessWidget {
  const TimelineRulerCutEndBoundary({
    super.key = const ValueKey<String>('timeline-cut-end-boundary-ruler'),
    required this.left,
    this.axis = Axis.horizontal,
  });

  /// Main-axis offset of the boundary line (x when horizontal, y when
  /// vertical) — the shared `timelineCutEndBoundaryX` result.
  final double left;

  /// The frame axis direction: a vertical line in the horizontal ruler, a
  /// horizontal line in the X-sheet frame-number rail.
  final Axis axis;

  @override
  Widget build(BuildContext context) =>
      timelineCutEndBoundaryLine(left: left, axis: axis);
}
