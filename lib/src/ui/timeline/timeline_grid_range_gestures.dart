import 'timeline_frame_range_policy.dart';
import '../../models/timeline_row_address.dart';
import 'property_lane_model.dart';
import 'timeline_frame_range_gesture.dart';
import 'timeline_grid_hooks.dart';
import 'timeline_grid_metrics.dart';
import 'timeline_grid_range_callbacks.dart';

/// The row a range drag is HOLDING, pinned by the host that windows its
/// rows. [take] fires when the A5 grip is taken, [release] when it lets go;
/// a host that builds every row (the sheet) passes no pin at all.
class HeldRowPin {
  const HeldRowPin({required this.take, required this.release});

  final void Function(TimelineRowAddress row) take;
  final void Function(TimelineRowAddress row) release;
}

/// THE RANGE GESTURES — the sweep that selects a frame range on a row or
/// a lane, and the policy that says which rows take one — as their own
/// object.
///
/// 🚨A collaborator carved out of the two grid States (the audit's SRP
/// cut, 2026-09-02), then found to be the same collaborator twice: the
/// rail's and the sheet's copies were byte-identical modulo names, save
/// that the rail pins its held row and the sheet does not (round 8,
/// 2026-09-06). It reaches the host through the four getters, never the
/// State.
///
/// The SAME builders both grids call — the sheet used to copy the rail's
/// callbacks and fall a law behind (no span rows, no head lane).
class TimelineGridRangeGestures {
  TimelineGridRangeGestures({
    required this.hooks,
    required this.metrics,
    required this.dragRows,
    required this.rangeMove,
    this.pin,
  });

  final TimelineGridHooks Function() hooks;
  final TimelineGridMetrics Function() metrics;

  /// The display rows of the pass in flight — a getter, read at CALL time
  /// (see [timelineGridRangeCallbacks] on why never a list).
  final List<TimelineDisplayRow> Function() dragRows;

  /// The host's row resolver for a range MOVE; [rangeGestureFor] loads it.
  final TimelineRangeMoveRowResolver rangeMove;

  /// D42: EVERY range drag (select or move) takes the A5 grip, and the held
  /// row is PINNED in the row window while it does. Null where the host has
  /// no row window — every row stays built, so nothing can unmount the
  /// held one.
  final HeldRowPin? pin;

  TimelineFrameRange get frameRangePolicy =>
      TimelineFrameRange.fromPlaybackDuration(
        playbackFrameCount: hooks().playbackFrameCount,
        minimumVisibleFrameCells: metrics().minimumVisibleFrameCells,
      );

  /// The cells-family drag callbacks for this pass, or null when the
  /// host wired none.
  ///
  /// ⚠️It also loads [rangeMove] with [rows], which is why it takes them
  /// rather than reading a field: the drag counts ROWS and lands on
  /// SLOTS, and only this list knows how many rows sit between two fx
  /// headers. Both happen in the same pass or neither does.
  TimelineRangeGestureCallbacks? rangeGestureFor(
    List<TimelineDisplayRow> rows,
  ) {
    final rangeHooks = hooks().rangeHooks;
    rangeMove
      ..rows = rows
      ..session = rangeHooks?.move;
    return rangeHooks == null
        ? null
        : timelineGridRangeCallbacks(
            rangeHooks: rangeHooks,
            rowExtent: metrics().layerRowHeight,
            dragRows: dragRows,
            rangeMove: rangeMove,
            onGripTaken: pin?.take,
            onGripReleased: pin?.release,
          );
  }

  /// The lane-family drag callbacks for this pass, or null when the host
  /// wired none. Same display-row slice and the same hooks as the cells
  /// family above — one law, both axes.
  TimelineLaneRangeCallbacks? laneRangeFor(List<TimelineDisplayRow> rows) {
    final hostLaneRange = hooks().laneRange;
    return hostLaneRange == null
        ? null
        : timelineGridLaneRangeCallbacks(
            hostLaneRange: hostLaneRange,
            rangeHooks: hooks().rangeHooks,
            rowExtent: metrics().layerRowHeight,
            dragRows: dragRows,
            onGripTaken: pin?.take,
            onGripReleased: pin?.release,
          );
  }
}
