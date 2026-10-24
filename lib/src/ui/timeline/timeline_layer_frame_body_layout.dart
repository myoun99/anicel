import 'package:flutter/material.dart';

/// The one Row that puts a grid's rail window, the gap after it and the
/// frame cells in that order.
///
/// The rail and the cells stay in the SAME vertical scroll body — that is
/// what makes row alignment free, and no amount of rail chrome may split
/// them into two scrollables. The layer-axis bar is not in it: it stands
/// still over the gap's second column (`timeline_grid_frame.dart`).
class TimelineLayerFrameBodyLayout extends StatelessWidget {
  const TimelineLayerFrameBodyLayout({
    super.key,
    required this.layerControlsRail,
    required this.railGap,
    required this.frameGridArea,
  });

  final Widget layerControlsRail;

  /// The splitter's column and the layer-axis bar's
  /// (`TimelineGridRailGap`).
  final Widget railGap;

  final Widget frameGridArea;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [layerControlsRail, railGap, frameGridArea],
    );
  }
}
