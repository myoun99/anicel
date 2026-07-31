/// Comma-drag pixel policy, shared across frame-axis orientations.
///
/// "Comma-drag" grabs a drawing block's edge grip and drags along the frame
/// axis to adjust exposure one frame (comma) at a time, TVPaint-style. The
/// math here is main-axis scalars only, so the horizontal timeline and the
/// transposed X-sheet reuse it unchanged (Axis policy: no per-orientation
/// forks).
///
/// The conversion is CUMULATIVE: callers keep the summed pixel delta since
/// drag start and pass it whole. The data layer recomputes the shifted
/// timeline from the drag-start snapshot each time, so previews are
/// idempotent and no per-step accounting exists anywhere.
library;

import 'package:flutter/widgets.dart';

import '../../models/layer_id.dart';
import '../../models/timeline_coverage.dart';

/// Whole-frame delta for an EDGE drag (R9 #10): the edge already sits ON a
/// cell boundary, so it steps once the pointer has carried it a WHOLE
/// cell.
///
/// It used to round, which stepped as the pointer passed the cell's
/// MIDDLE — the user read that as the edge leaping out from under the
/// hand. Truncation is toward zero, so both directions feel the same.
int commaDragFrameDelta({
  required double accumulatedDelta,
  required double frameCellExtent,
}) {
  assert(frameCellExtent > 0, 'Frame cell extent must be positive.');
  return (accumulatedDelta / frameCellExtent).truncate();
}

/// Whole-frame delta for a MOVE drag — still the NEAREST cell.
///
/// The user's rule when #10 was decided: edges only. A move travels with
/// the grab POINT, which starts somewhere inside a cell rather than on a
/// boundary, so following the nearest boundary is what tracks the hand.
int timelineMoveFrameDelta({
  required double accumulatedDelta,
  required double frameCellExtent,
}) {
  assert(frameCellExtent > 0, 'Frame cell extent must be positive.');
  return (accumulatedDelta / frameCellExtent).round();
}

/// R27 #12: the CROSS-axis (row) step of a move drag, with a deadband.
///
/// Rows used to step on the same half-cell rounding the frame axis uses.
/// At the slim 28px row height that is a 14px wobble — which a fast
/// horizontal drag produces without meaning anything by it — and each
/// wobble handed the step to the row-change path, where an incompatible
/// landing HOLDS: the block stopped following the pointer and the drag
/// read as "그랩이 풀린" mid-sweep. A row must be crossed by
/// [_rowStepThreshold] of its height before it counts, so a horizontal
/// sweep stays horizontal while a deliberate row change still lands one
/// row per row.
int timelineRowStepDelta({
  required double accumulatedDelta,
  required double rowExtent,
}) {
  assert(rowExtent > 0, 'Row extent must be positive.');
  final raw = accumulatedDelta / rowExtent;
  final steps = raw.truncate();
  final fraction = raw - steps;
  if (fraction >= _rowStepThreshold) {
    return steps + 1;
  }
  if (fraction <= -_rowStepThreshold) {
    return steps - 1;
  }
  return steps;
}

const double _rowStepThreshold = 0.75;

/// The drag hooks a grip needs, bundled so rows/grids thread one optional
/// object instead of four callbacks. Wired to the editor session's
/// begin/update/end/cancel exposure-edge-drag methods (single undo entry
/// per drag).
class TimelineCommaDragCallbacks {
  const TimelineCommaDragCallbacks({
    required this.onBegin,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  /// Returns whether the drag may start (e.g. the block still exists).
  final bool Function(
    LayerId layerId,
    int blockStartIndex,
    TimelineBlockEdge edge,
  )
  onBegin;

  /// Reports the cumulative whole-frame delta since drag start.
  final ValueChanged<int> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;
}
