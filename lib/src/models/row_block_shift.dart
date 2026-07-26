/// PUSH and PULL: the blocks at or after an anchor travel RIGIDLY, and the
/// empty space between them is carried along rather than eaten.
///
/// This is one rule for two axes. A layer row's blocks are its exposures
/// and the anchor is a frame; a track row's blocks are its cuts and the
/// anchor is a cut boundary. What differs is only what the shift is written
/// back as — re-keyed exposures on one, leading gaps on the other — so the
/// arithmetic lives here and the two commits stay thin.
///
/// It is deliberately NOT what a drag does. A drag that shoved everything
/// after it made one selected block and five selected blocks the same
/// edit, which is why dragging now re-times or reorders instead
/// ([planCutMove]) and the shove became a verb you aim.
library;

import 'dart:collection';
import 'dart:math' as math;

import 'timeline_coverage.dart';
import 'timeline_exposure.dart';

/// One block on a row's index axis, as PUSH/PULL sees it.
typedef ShiftableBlock = ({int startIndex, int endIndexExclusive});

/// The blocks that a push/pull from [anchorIndex] moves: every block that
/// STARTS at or after it. A block straddling the anchor stays put — the
/// anchor is a boundary, and splitting a block would not be a rigid move.
List<ShiftableBlock> blocksShiftedFrom(
  List<ShiftableBlock> blocks,
  int anchorIndex,
) => [
  for (final block in blocks)
    if (block.startIndex >= anchorIndex) block,
];

/// How far a PULL from [anchorIndex] can travel before the first moved
/// block touches whatever sits behind it. Zero when they already touch;
/// unbounded rows (nothing before the anchor) clamp at frame 0.
///
/// The row with the least slack decides for every row a scope covers —
/// "가장 먼저 닿는 곳에서 전체 정지" — so a caller takes the minimum over
/// its rows before committing anything.
int rowPullSlack({
  required List<ShiftableBlock> blocks,
  required int anchorIndex,
}) {
  int? firstMovedStart;
  var lastStillEnd = 0;
  for (final block in blocks) {
    if (block.startIndex >= anchorIndex) {
      firstMovedStart ??= block.startIndex;
      continue;
    }
    lastStillEnd = math.max(lastStillEnd, block.endIndexExclusive);
  }
  if (firstMovedStart == null) {
    // Nothing to move: the row imposes no limit of its own.
    return 0x7fffffff;
  }
  // Measured from what STAYS, not from the anchor: a pull closes the space
  // in front of the moved run, and the anchor is where the run begins, not
  // a wall of its own.
  return math.max(0, firstMovedStart - lastStillEnd);
}

/// [timeline] with every drawing block starting at or after [anchorIndex]
/// moved by [delta] frames. The caller has already clamped [delta] against
/// [rowPullSlack]; a shift that would collide or go negative is a
/// programming error, not a silent no-op.
SplayTreeMap<int, TimelineExposure> timelineShiftedFrom(
  SplayTreeMap<int, TimelineExposure> timeline, {
  required int anchorIndex,
  required int delta,
}) {
  if (delta == 0) {
    return timeline;
  }
  final shifted = SplayTreeMap<int, TimelineExposure>();
  for (final entry in timeline.entries) {
    final key = entry.key >= anchorIndex ? entry.key + delta : entry.key;
    if (key < 0) {
      throw ArgumentError('Shift moves a block before frame 0.');
    }
    shifted[key] = entry.value;
  }
  validateTimelineCoverage(shifted);
  return shifted;
}

/// A layer timeline's drawing blocks as shift material.
List<ShiftableBlock> timelineShiftableBlocks(
  SplayTreeMap<int, TimelineExposure> timeline,
) => [
  for (final block in drawingBlocks(timeline))
    (startIndex: block.startIndex, endIndexExclusive: block.endIndexExclusive),
];
