/// The storyboard row's coverage rule (design E, user's rule): its blocks
/// TILE the cut — no gaps, no overlaps, every frame in exactly one cell.
///
/// Every other drawing kind keeps real gaps, where an empty frame means
/// nothing is drawn there. A conte panel is not like that: the cut is
/// divided into panels, so what a block's start really states is a
/// DIVISION, and the cell it opens runs until the next division or the end
/// of the cut. Hence [layerKindCoversWithoutGaps] — and hence the
/// consequences the design lists: growing the cut lengthens the last cell,
/// deleting a block hands its frames to the one before it, and dragging a
/// trailing edge is the ordinary comma resize with the cut's length riding
/// the row end (edge unification).
///
/// A LEADING edge is the mirror of that trailing one and lives on the
/// storyboard strip only ([storyboardTimelineWithPanelLeadRetimed]): it
/// shortens the panel you grabbed and the cut's length gives way, so it
/// cannot open a hole either. The timeline panel deliberately hangs no
/// front grips at all — user's rule 2026-08-02, "grabbing the front and
/// watching the back shrink feels wrong", so that surface keeps the
/// trailing-edge vocabulary and nothing else.
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
  for (final key in storyboardDivisionKeys(
    timeline: timeline,
    cutDuration: cutDuration,
  )) {
    // A key before the cut start is nonsense data; fold it onto frame 0
    // rather than derive a cell that begins outside the cut.
    divisions[key < 0 ? 0 : key] = timeline![key]!.frameId!;
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

/// The cut's division keys, in order — the timeline keys the cells above
/// are derived from. The FIRST one opens the cut (its cell reaches back to
/// frame 0 whatever its key says); every later one is a boundary BETWEEN
/// two panels, and those are the ones an edge can move.
List<int> storyboardDivisionKeys({
  required SplayTreeMap<int, TimelineExposure>? timeline,
  required int cutDuration,
}) {
  if (timeline == null || cutDuration <= 0) {
    return const [];
  }
  final keys = <int>[];
  for (final entry in timeline.entries) {
    if (entry.key >= cutDuration) {
      break;
    }
    if (entry.value.isDrawing &&
        !entry.value.ghost &&
        entry.value.frameId != null) {
      keys.add(entry.key);
    }
  }
  return keys;
}

/// How far the panel at [panelIndex] may be shortened from its FRONT, or
/// null when there is no such panel to re-time.
///
/// The panel keeps one frame — the same one-frame floor every other
/// boundary rule here has. Growing (a negative delta) is NOT bounded here:
/// what stops it is the cut axis, where the frames come from ([planCutLeadEdge]
/// clamps against the slack that actually exists ahead of the cut).
int? storyboardPanelLeadMaxShrink({
  required SplayTreeMap<int, TimelineExposure>? timeline,
  required int cutDuration,
  required int panelIndex,
}) {
  final bounds = _panelLeadBounds(
    timeline: timeline,
    cutDuration: cutDuration,
    panelIndex: panelIndex,
  );
  if (bounds == null) {
    return null;
  }
  final room = bounds.end - bounds.start - 1;
  return room < 0 ? 0 : room;
}

/// [timeline] with the panel at [panelIndex] shortened by [delta] frames at
/// its FRONT, or null when there is nothing to re-time or the clamped delta
/// is zero.
///
/// This is the ONE thing a front-edge drag does, and it is the same
/// operation whether the panel is the cut's first or one of its inner ones
/// — the user's rule 2026-08-02: *the panel you grabbed loses commas, every
/// other panel keeps the commas it had, and the cut's length gives way by
/// the difference*. Nobody grows.
///
/// The keys BEFORE the grabbed panel do not move and the grabbed panel keeps
/// its own key; every later key rides by -[delta] so it keeps its comma.
/// That looks like it contradicts the cascade the user asked for — the
/// panels in FRONT visibly come along — but it does not, because these are
/// CUT-LOCAL keys and the caller moves the cut's head by the same amount.
/// In the cut's own coordinates the panels ahead of the grab hold still and
/// the ones behind it slide; on screen, with the cut's end pinned, it reads
/// as the whole run in front translating. Two frames of reference, one
/// motion — the same trick [planBlockRunLeadEdge] plays on the frame axis.
///
/// The grabbed panel loses its front frames, so its inbetween dots SHIFT
/// rather than truncate — [TimelineExposure.copyWith] would drop them off
/// the tail, which is the wrong end.
///
/// A row whose first division key is negative is refused rather than
/// repaired: that is corrupt data, and folding it onto frame 0 can collide
/// with a real key there.
SplayTreeMap<int, TimelineExposure>? storyboardTimelineWithPanelLeadRetimed({
  required SplayTreeMap<int, TimelineExposure>? timeline,
  required int cutDuration,
  required int panelIndex,
  required int delta,
}) {
  final bounds = _panelLeadBounds(
    timeline: timeline,
    cutDuration: cutDuration,
    panelIndex: panelIndex,
  );
  if (bounds == null) {
    return null;
  }
  final maxShrink = bounds.end - bounds.start - 1;
  final applied = delta > maxShrink ? maxShrink : delta;
  if (applied == 0) {
    return null;
  }
  final source = timeline!;
  final next = SplayTreeMap<int, TimelineExposure>();
  for (final entry in source.entries) {
    if (entry.key < bounds.key) {
      next[entry.key] = entry.value;
    } else if (entry.key == bounds.key) {
      next[entry.key] = entry.value.copyWith(
        length: bounds.end - applied - bounds.start,
        breakdownOffsets: [
          for (final offset in entry.value.breakdownOffsets)
            if (offset - applied >= 1) offset - applied,
        ],
      );
    } else {
      // Later entries ride, comma intact — overhanging junk data past the
      // cut end included, so its distance to the end stays what it was.
      next[entry.key - applied] = entry.value;
    }
  }
  return next;
}

/// The stored key, cell start and cell end of the panel a front-edge drag
/// grabbed, or null when that panel does not exist.
({int key, int start, int end})? _panelLeadBounds({
  required SplayTreeMap<int, TimelineExposure>? timeline,
  required int cutDuration,
  required int panelIndex,
}) {
  final keys = storyboardDivisionKeys(
    timeline: timeline,
    cutDuration: cutDuration,
  );
  if (panelIndex < 0 || panelIndex >= keys.length || keys.first < 0) {
    return null;
  }
  return (
    key: keys[panelIndex],
    // The first cell reaches back to the cut start, exactly as
    // [storyboardCoverageCells] reads it.
    start: panelIndex == 0 ? 0 : keys[panelIndex],
    end: panelIndex + 1 < keys.length ? keys[panelIndex + 1] : cutDuration,
  );
}

/// [timeline] rewritten so its STORED blocks tile `[0, cutDuration)` — the
/// shape a row must be in to become a storyboard row.
///
/// Returns null when there is nothing to tile with (no drawing inside the
/// cut): the caller makes a fresh blank panel instead, which is what a new
/// storyboard row is born as.
///
/// The rewrite is exactly what [storyboardCoverageCells] already READS, so
/// nothing about the picture changes — the first block reaches back to the
/// cut start, every block runs to the next division, and the last runs to
/// the cut end. Making the store say it too is what stops the row from
/// showing "X" cells in the timeline while the strip shows none.
SplayTreeMap<int, TimelineExposure>? storyboardTimelineFilledToCover({
  required SplayTreeMap<int, TimelineExposure>? timeline,
  required int cutDuration,
}) {
  if (cutDuration <= 0 || timeline == null) {
    return null;
  }
  final cells = storyboardCoverageCells(
    timeline: timeline,
    cutDuration: cutDuration,
  );
  if (cells.isEmpty || cells.first.frameId == null) {
    return null;
  }
  final next = SplayTreeMap<int, TimelineExposure>();
  final keys = storyboardDivisionKeys(
    timeline: timeline,
    cutDuration: cutDuration,
  );
  for (var index = 0; index < cells.length; index += 1) {
    final cell = cells[index];
    // The entry keeps its own memo and dots; only where it starts and how
    // long it holds are rewritten.
    next[cell.startIndex] = timeline[keys[index]]!.copyWith(
      length: cell.length,
    );
  }
  return next;
}

/// The frame a cell's PICTURE is composited at.
///
/// A panel shows the cut at its own division — that is where its drawing
/// begins, so it is what the panel is about. The cut's pinned thumbnail
/// frame still wins inside the panel that holds it: pinning says "show the
/// cut at THIS moment", and the panel covering that moment is the one it
/// was said about.
int storyboardCellPictureFrame(
  StoryboardCoverageCell cell, {
  int? pinnedFrameIndex,
}) => pinnedFrameIndex != null && cell.covers(pinnedFrameIndex)
    ? pinnedFrameIndex
    : cell.startIndex;

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
