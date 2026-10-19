import 'package:flutter/material.dart';

/// The one Row that puts a grid's rail window, the splitter's reserved slot
/// and the frame cells in that order.
///
/// The rail and the cells stay in the SAME vertical scroll body — that is
/// what makes row alignment free, and no amount of rail chrome may split
/// them into two scrollables. The layer-axis bar is not in it: it stands
/// beside the scroll body, at the frame area's far right
/// (`timeline_grid_frame.dart`).
class TimelineLayerFrameBodyLayout extends StatelessWidget {
  const TimelineLayerFrameBodyLayout({
    super.key,
    required this.layerControlsRail,
    required this.railSplitterSlot,
    required this.frameGridArea,
  });

  final Widget layerControlsRail;

  /// Reserves the gap the rail splitter floats over.
  final Widget railSplitterSlot;

  final Widget frameGridArea;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [layerControlsRail, railSplitterSlot, frameGridArea],
    );
  }
}
