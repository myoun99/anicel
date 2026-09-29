import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'axis_turn.dart';
import 'timeline_frame_coordinate_policy.dart';
import 'timeline_grid_metrics.dart';

/// The playhead tint color, exported so tests can assert against it —
/// a LIVE accent read (UI-R22 #5).
Color get timelinePlayheadColor => AppColors.accent;

/// THE playhead's wash — the one colour every surface lays over the cell
/// the playhead stands on: the grids' column, the rulers' cell, the conte's
/// strips and the folded rows.
///
/// 🗣️F-212 (유저 2026-09-28): 「재생헤드 세로 오버레이, 좀 더 진해서 확실하게
/// 보이도록. 그리고 룰러랑 프레임영역이랑 미묘하게 색 다른거같은데 통일」 —
/// and it is the one thing that says where you stand now: the outlines
/// round the block or gap you stand in went with the same request.
/// ↩️The grids and the conte laid the accent at 18%, the rulers at 12%.
Color get timelinePlayheadWashColor =>
    timelinePlayheadColor.withValues(alpha: 0.3);

/// THE playhead column: the wash over the cell [frame] stands on
/// ([timelinePlayheadSpan]), the whole way across the strip, in a stack
/// whose frame 0 boundary stands at [origin] along [axis]. Every surface's
/// playhead is placed by this one call.
Positioned timelinePlayheadColumn({
  required Axis axis,
  required int frame,
  required double cellExtent,
  required double origin,
  Key columnKey = const ValueKey<String>('timeline-playhead-column'),
}) {
  final span = timelinePlayheadSpan(frame, cellExtent);
  return stripAlong(
    axis,
    key: columnKey,
    along: origin + span.start,
    alongExtent: span.end - span.start,
    child: ColoredBox(color: timelinePlayheadWashColor),
  );
}

/// The playhead of a grid laid out from [frameStartIndex], which stands at
/// [leadingFrameSpacerWidth]: a column in the horizontal timeline, a row in
/// the X-sheet.
class TimelinePlayhead extends StatelessWidget {
  const TimelinePlayhead({
    super.key = const ValueKey<String>('timeline-playhead'),
    required this.currentFrameIndex,
    required this.frameStartIndex,
    required this.frameEndIndexExclusive,
    required this.leadingFrameSpacerWidth,
    required this.metrics,
    required this.crossAxisExtent,
    this.axis = Axis.horizontal,
  });

  final int currentFrameIndex;
  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final double leadingFrameSpacerWidth;
  final TimelineGridMetrics metrics;

  /// The rows' extent across the frame axis — the column's length.
  final double crossAxisExtent;

  /// The frame axis direction: a column tint in the horizontal timeline, a
  /// row tint in the X-sheet. The offset math is shared.
  final Axis axis;

  bool get _isCurrentFrameBuilt {
    return currentFrameIndex >= frameStartIndex &&
        currentFrameIndex < frameEndIndexExclusive;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCurrentFrameBuilt) {
      return const SizedBox.shrink();
    }
    final cell = metrics.frameCellWidth;
    return IgnorePointer(
      child: acrossBox(
        axis,
        crossAxisExtent,
        child: Stack(
          children: [
            timelinePlayheadColumn(
              axis: axis,
              frame: currentFrameIndex,
              cellExtent: cell,
              origin:
                  leadingFrameSpacerWidth -
                  timelineFrameEdge(frameStartIndex, cell),
            ),
          ],
        ),
      ),
    );
  }
}
