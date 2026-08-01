import 'package:flutter/material.dart';

/// The one Row that puts a grid's layer-axis scrollbar, its rail window,
/// the splitter's reserved slot and the frame cells in that order.
///
/// The rail and the cells stay in the SAME vertical scroll body — that is
/// what makes row alignment free, and no amount of rail chrome may split
/// them into two scrollables.
class TimelineLayerFrameBodyLayout extends StatelessWidget {
  const TimelineLayerFrameBodyLayout({
    super.key,
    required this.layerAxisScrollbarSlot,
    required this.layerControlsRail,
    required this.railSplitterSlot,
    required this.frameGridArea,
  });

  /// Reserves the left EDGE column the layer-axis scrollbar floats over.
  final Widget layerAxisScrollbarSlot;

  final Widget layerControlsRail;

  /// Reserves the gap the rail splitter floats over.
  final Widget railSplitterSlot;

  final Widget frameGridArea;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        layerAxisScrollbarSlot,
        layerControlsRail,
        railSplitterSlot,
        frameGridArea,
      ],
    );
  }
}
