/// The storyboard row's coverage rule (design E, user's rule): its blocks
/// TILE the cut — no gaps, no overlaps, every frame in exactly one cell.
///
/// Every other drawing kind keeps real gaps, where an empty frame means
/// nothing is drawn there. A conte panel is not like that: the cut is
/// divided into panels, so what a block's start really states is a
/// DIVISION, and the cell it opens runs until the next division or the end
/// of the cut. Hence [layerKindCoversWithoutGaps] — and hence the
/// consequences the design lists: growing the cut lengthens the last cell,
/// deleting a block hands its frames to the one before it, and dragging an
/// edge moves a division rather than resizing one thing and leaving a hole.
///
/// The cells are DERIVED here rather than maintained in the store, so the
/// invariant cannot be broken by an edit path that forgot about it. Stored
/// lengths stay real for every shared verb (delete, push/pull, move); this
/// is the reading the panel and the conte sheet draw from.
library;

import 'dart:collection';

import 'frame_id.dart';
import 'timeline_exposure.dart';

/// One cell of the conte: a panel of the cut, and the drawing in it.
class StoryboardCoverageCell {
  const StoryboardCoverageCell({
    required this.startIndex,
    required this.endIndexExclusive,
    required this.frameId,
  }) : assert(endIndexExclusive > startIndex, 'A cell must cover frames.');

  final int startIndex;
  final int endIndexExclusive;

  /// The drawing shown in this cell, or null when nothing has been drawn
  /// in it yet — an undrawn cell is still a cell (a blank conte panel).
  final FrameId? frameId;

  int get length => endIndexExclusive - startIndex;

  bool covers(int frameIndex) =>
      frameIndex >= startIndex && frameIndex < endIndexExclusive;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoryboardCoverageCell &&
          other.startIndex == startIndex &&
          other.endIndexExclusive == endIndexExclusive &&
          other.frameId == frameId;

  @override
  int get hashCode => Object.hash(startIndex, endIndexExclusive, frameId);

  @override
  String toString() =>
      'StoryboardCoverageCell([$startIndex, $endIndexExclusive), $frameId)';
}

/// The cut's cells, in order, covering `[0, cutDuration)` exactly.
///
/// - No timeline (or no drawing inside the cut) gives ONE cell over the
///   whole cut, which is what the panel already shows for a cut with no
///   storyboard layer at all. The general case degenerates into it rather
///   than being a second rule beside it.
///
/// The other two clauses are SAFETY NETS, not the mechanism. The row is
/// meant to have no reachable state that needs them — it is born covering
/// its cut, and the cut cannot shrink past the drawings on it (user's rule
/// 2026-07-27) — but an old file, an undo landing or a bug must still read
/// as something rather than as a hole:
///
/// - The FIRST division reaches back to the cut start, so a drawing that
///   somehow begins at frame 3 still owns the frames before it.
/// - Divisions at or past the cut end make no cell. The block stays real
///   data; the conte simply has no panel for it.
List<StoryboardCoverageCell> storyboardCoverageCells({
  required SplayTreeMap<int, TimelineExposure>? timeline,
  required int cutDuration,
}) {
  if (cutDuration <= 0) {
    return const [];
  }
  final divisions = <int, FrameId>{};
  if (timeline != null) {
    for (final entry in timeline.entries) {
      if (entry.key >= cutDuration) {
        break;
      }
      final frameId = entry.value.frameId;
      if (entry.value.isDrawing && !entry.value.ghost && frameId != null) {
        divisions[entry.key < 0 ? 0 : entry.key] = frameId;
      }
    }
  }
  if (divisions.isEmpty) {
    return [
      StoryboardCoverageCell(
        startIndex: 0,
        endIndexExclusive: cutDuration,
        frameId: null,
      ),
    ];
  }
  final starts = divisions.keys.toList()..sort();
  return [
    for (var index = 0; index < starts.length; index += 1)
      StoryboardCoverageCell(
        // The first cell reaches back to the cut start.
        startIndex: index == 0 ? 0 : starts[index],
        endIndexExclusive: index == starts.length - 1
            ? cutDuration
            : starts[index + 1],
        frameId: divisions[starts[index]],
      ),
  ];
}

/// The cell covering [frameIndex], or null when the frame is outside the
/// cut.
StoryboardCoverageCell? storyboardCellAt({
  required SplayTreeMap<int, TimelineExposure>? timeline,
  required int cutDuration,
  required int frameIndex,
}) {
  for (final cell in storyboardCoverageCells(
    timeline: timeline,
    cutDuration: cutDuration,
  )) {
    if (cell.covers(frameIndex)) {
      return cell;
    }
  }
  return null;
}
