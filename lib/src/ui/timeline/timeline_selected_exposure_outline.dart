import 'package:flutter/material.dart';

import '../../models/layer_id.dart';
import 'selected_exposure_display_range_policy.dart';
import 'timeline_cell_style.dart' show timelineSelectedFrameBorderColor;
import 'timeline_frame_coordinate_policy.dart';

/// THE ring that says "this is in the selection", wherever a selection is
/// drawn — a selected frame run here, a selected rail row (㊴).
///
/// ★유저 08-12: 「레이어의 선택범위가 액티브레이어랑 생긴게 똑같아서 이상함.
/// 프레임셀처럼 외곽선으로 감싸자」. The two states had been sharing the wash
/// on the reasoning that both mean "the verbs act here" — true, and useless
/// on screen, because then nothing tells them apart. They are orthogonal:
/// **the wash says where you are STANDING, the ring says what is SELECTED**,
/// and the active row inside a selection wears both.
///
/// Extracted rather than copied so the sheet, the rail and the frame runs
/// cannot drift into three rings ([[no-copy-to-share]]).
class TimelineSelectionRing extends StatelessWidget {
  const TimelineSelectionRing({
    super.key,
    this.color,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.width = 2,
  });

  /// Null = the accent every other selection ring uses.
  final Color? color;
  final BorderRadius borderRadius;
  final double width;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border.all(
            color: color ?? timelineSelectedFrameBorderColor,
            width: width,
          ),
          borderRadius: borderRadius,
        ),
      ),
    );
  }
}

class TimelineSelectedExposureOutline extends StatelessWidget {
  const TimelineSelectedExposureOutline({
    super.key,
    required this.layerId,
    required this.displayRange,
    required this.frameStartIndex,
    required this.leadingFrameSpacerWidth,
    required this.frameCellWidth,
    required this.rowHeight,
    required this.borderColor,
    required this.borderRadius,
    this.axis = Axis.horizontal,
  });

  final LayerId layerId;
  final SelectedExposureDisplayRange displayRange;
  final int frameStartIndex;
  final double leadingFrameSpacerWidth;
  final double frameCellWidth;

  /// Cross-axis extent of the outlined run (row height in the horizontal
  /// timeline, column width in the X-sheet).
  final double rowHeight;
  final Color borderColor;
  final BorderRadius borderRadius;

  /// The frame axis direction; the offset math is shared and transposed.
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    if (!displayRange.hasVisibleIntersection) {
      return const SizedBox.shrink();
    }

    final mainAxisOffset = frameVisibleX(
      frameIndex: displayRange.visibleStartFrameIndex,
      frameStartIndex: frameStartIndex,
      frameCellWidth: frameCellWidth,
      leadingFrameSpacerWidth: leadingFrameSpacerWidth,
    );
    final mainAxisExtent = frameRangeVisibleWidth(
      startFrameIndex: displayRange.visibleStartFrameIndex,
      endFrameIndexExclusive: displayRange.visibleEndFrameIndexExclusive,
      frameCellWidth: frameCellWidth,
    );
    final outline = TimelineSelectionRing(
      color: borderColor,
      borderRadius: borderRadius,
    );

    if (axis == Axis.vertical) {
      return Positioned(
        key: ValueKey<String>(
          'timeline-selected-exposure-range-outline-$layerId',
        ),
        top: mainAxisOffset,
        left: 0,
        height: mainAxisExtent,
        width: rowHeight,
        child: outline,
      );
    }
    return Positioned(
      key: ValueKey<String>(
        'timeline-selected-exposure-range-outline-$layerId',
      ),
      left: mainAxisOffset,
      top: 0,
      width: mainAxisExtent,
      height: rowHeight,
      child: outline,
    );
  }
}
