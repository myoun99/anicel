import 'package:anicel/src/models/timeline_run_behavior.dart';

/// The run-edge vocabulary tests spell over and over (F-134): the mark a
/// block carries, and the stamp a derived ghost wears.

const holdMark = TimelineRunEdgeMark(mode: TimelineRunEdgeMode.hold);
const repeatMark = TimelineRunEdgeMark(mode: TimelineRunEdgeMode.repeat);

/// A repeat carrier that is ALSO its own pattern bound.
const repeatBoundMark = TimelineRunEdgeMark(
  mode: TimelineRunEdgeMode.repeat,
  bound: true,
);

/// A block that only bounds its run's scoped repeat pattern.
const boundMark = TimelineRunEdgeMark(bound: true);

const endHoldGhost = TimelineRunEdgeGhost(
  side: TimelineRunEdgeSide.end,
  mode: TimelineRunEdgeMode.hold,
);
const endRepeatGhost = TimelineRunEdgeGhost(
  side: TimelineRunEdgeSide.end,
  mode: TimelineRunEdgeMode.repeat,
);
const startHoldGhost = TimelineRunEdgeGhost(
  side: TimelineRunEdgeSide.start,
  mode: TimelineRunEdgeMode.hold,
);
const startRepeatGhost = TimelineRunEdgeGhost(
  side: TimelineRunEdgeSide.start,
  mode: TimelineRunEdgeMode.repeat,
);
