/// The storyboard row's coverage rule (design E, user's rule): its blocks
/// TILE the cut — no gaps, no overlaps, every frame in exactly one cell.
///
/// Every other drawing kind keeps real gaps, where an empty frame means
/// nothing is drawn there. A conte panel is not like that: the cut is
/// divided into panels, so what a block's start really states is a
/// DIVISION, and the cell it opens runs until the next division or the end
/// of the cut. Hence [LayerKind.coversWithoutGaps] — and hence the
/// consequences the design lists: growing the cut lengthens the last cell,
/// deleting a block hands its frames to the one before it, and dragging a
/// trailing edge is the ordinary comma resize with the cut's length riding
/// the row end (edge unification).
///
/// A LEADING edge is the mirror of that trailing one and lives on the
/// storyboard strip only: it shortens the panel you grabbed and the cut's
/// length gives way, so it cannot open a hole either. The timeline panel
/// deliberately hangs no front grips at all — user's rule 2026-08-02,
/// "grabbing the front and watching the back shrink feels wrong", so that
/// surface keeps the trailing-edge vocabulary and nothing else.
///
/// ↩️I-21 (유저 2026-09-12) reversed both halves. A leading edge follows the
/// SHARED lead-edge rule on every surface now ([planBlockRunLeadEdge]): the
/// grabbed panel's end holds, and the block in front keeps its head and
/// trades frames with it, so the cut's length no longer gives way. And
/// because a front edge no longer changes the cut's length, the timeline's
/// conte row hangs front grips again on every block but the first, whose
/// front edge is the cut's own start and stays on the storyboard strip.
///
/// ⛔**The strip's own front-edge law is RETIRED (I-21 ②)**: the grabbed
/// panel lost frames, nobody grew, and the cut's length absorbed the
/// difference. The strip reaches the shared rule by flattening the track
/// into panels (`models/storyboard_panel_slots.dart`), and the cut axis's
/// own lead-edge planner, which bounded that law's growth, lost its last
/// caller with it and was deleted (2026-09-15). The law's two functions
/// stood here as a body "so nobody writes it again" until 2026-09-24 —
/// dead code that read as a law in force — and these words are that
/// warning now.
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

/// Where [timeline]'s conte begins in its cut's own frames: its first real
/// division.
///
/// 🗣️F-227 (유저 2026-09-29/30): 「ol주는컷은 콘티블록의 마지막블록을 늘리고
/// 받는컷은 처음블록을 늘리라」. A cut an O.L ARRIVES into draws from the
/// O.L's start, the のりしろ before its own conte, so its frames begin that
/// many frames early — and its conte panels keep the conte's timing by
/// starting that many frames in, the first panel held back over the
/// のりしろ. Every other cut begins its conte at 0.
///
/// The repository keeps it so on every write (the storyboard row's
/// normalization tiles the panels from the cut's のりしろ), which is what
/// lets a reader take it off the row instead of asking the transitions.
int storyboardConteStart(SplayTreeMap<int, TimelineExposure>? timeline) {
  if (timeline == null) {
    return 0;
  }
  for (final entry in timeline.entries) {
    if (entry.value.isDrawing &&
        !entry.value.ghost &&
        entry.value.frameId != null) {
      return entry.key;
    }
  }
  return 0;
}

/// The cut's cells, in order, covering `[0, cutDuration)` exactly — in the
/// CONTE's frames, which begin at [conteStart] in the cut's own
/// ([storyboardConteStart] when not given).
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
/// - The FIRST division reaches back to the conte start, so a drawing that
///   somehow begins 3 frames after it still owns the frames before it.
/// - Divisions at or past the cut end make no cell. The block stays real
///   data; the conte simply has no panel for it.
List<StoryboardCoverageCell> storyboardCoverageCells({
  required SplayTreeMap<int, TimelineExposure>? timeline,
  required int cutDuration,
  int? conteStart,
}) {
  if (cutDuration <= 0) {
    return const [];
  }
  final divisions = _divisionsOf(
    timeline,
    cutDuration,
    conteStart ?? storyboardConteStart(timeline),
  );
  if (divisions.isEmpty) {
    return [
      StoryboardCoverageCell(
        startIndex: 0,
        endIndexExclusive: cutDuration,
        frameId: null,
      ),
    ];
  }
  final starts = divisions.keys.toList();
  return [
    for (var index = 0; index < starts.length; index += 1)
      StoryboardCoverageCell(
        // The first cell reaches back to the conte start.
        startIndex: index == 0 ? 0 : starts[index],
        endIndexExclusive: index == starts.length - 1
            ? cutDuration
            : starts[index + 1],
        frameId: timeline![divisions[starts[index]]!]!.frameId,
      ),
  ];
}

/// Each division by where it falls in the CONTE's frames, in order, to the
/// stored key it is read from — the one walk [storyboardCoverageCells] and
/// [storyboardTimelineFilledToCover] both stand on, so a cell and the block
/// written for it can never be two different divisions.
SplayTreeMap<int, int> _divisionsOf(
  SplayTreeMap<int, TimelineExposure>? timeline,
  int cutDuration,
  int conteStart,
) {
  final divisions = SplayTreeMap<int, int>();
  for (final key in storyboardDivisionKeys(
    timeline: timeline,
    cutDuration: cutDuration,
    conteStart: conteStart,
  )) {
    // A key before the conte start is nonsense data; fold it onto the
    // conte's first frame rather than derive a cell that begins outside it.
    divisions[key < conteStart ? 0 : key - conteStart] = key;
  }
  return divisions;
}

/// The cut's division keys, in order — the STORED timeline keys the cells
/// above are derived from, the cut's own frames. The FIRST one opens the
/// conte (its cell reaches back to [conteStart] whatever its key says);
/// every later one is a boundary BETWEEN two panels, and those are the ones
/// an edge can move. A key at or past the conte's end
/// (`conteStart + cutDuration`) is not a division.
List<int> storyboardDivisionKeys({
  required SplayTreeMap<int, TimelineExposure>? timeline,
  required int cutDuration,
  int? conteStart,
}) {
  if (timeline == null || cutDuration <= 0) {
    return const [];
  }
  final end = (conteStart ?? storyboardConteStart(timeline)) + cutDuration;
  final keys = <int>[];
  for (final entry in timeline.entries) {
    if (entry.key >= end) {
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

/// [timeline] rewritten so its STORED blocks tile the conte — `[conteStart,
/// conteStart + cutDuration)` in the cut's own frames — the shape a row
/// must be in to become a storyboard row. Ghosts are not carried: they are
/// the run-edge pass's, derived again from the marks the blocks keep.
///
/// Returns null when there is nothing to tile with (no drawing inside the
/// cut): the caller makes a fresh blank panel instead, which is what a new
/// storyboard row is born as.
///
/// The rewrite is exactly what [storyboardCoverageCells] already READS, so
/// nothing about the picture changes — the first block reaches back to the
/// conte start, every block runs to the next division, and the last runs to
/// the conte's end. Making the store say it too is what stops the row from
/// showing "X" cells in the timeline while the strip shows none.
SplayTreeMap<int, TimelineExposure>? storyboardTimelineFilledToCover({
  required SplayTreeMap<int, TimelineExposure>? timeline,
  required int cutDuration,
  required int conteStart,
}) {
  if (cutDuration <= 0 || timeline == null) {
    return null;
  }
  final cells = storyboardCoverageCells(
    timeline: timeline,
    cutDuration: cutDuration,
    conteStart: conteStart,
  );
  if (cells.isEmpty || cells.first.frameId == null) {
    return null;
  }
  final keys = _divisionsOf(timeline, cutDuration, conteStart).values.toList();
  final next = SplayTreeMap<int, TimelineExposure>();
  for (var index = 0; index < cells.length; index += 1) {
    final cell = cells[index];
    // The entry keeps its own memo and dots; only where it starts and how
    // long it holds are rewritten.
    next[conteStart + cell.startIndex] = timeline[keys[index]]!.copyWith(
      length: cell.length,
    );
  }
  return next;
}

/// The frame a cell's PICTURE is composited at, in the CUT's own frames.
///
/// A panel shows the cut at its own division — that is where its drawing
/// begins, so it is what the panel is about. The cut's pinned thumbnail
/// frame still wins inside the panel that holds it: pinning says "show the
/// cut at THIS moment", and the panel covering that moment is the one it
/// was said about.
///
/// The cell counts the CONTE's frames, which begin at [conteStart] in the
/// cut's own ([storyboardConteStart]) — after the のりしろ a cut an O.L
/// arrives into owes (F-227); the picture and the pin are the cut's.
int storyboardCellPictureFrame(
  StoryboardCoverageCell cell, {
  int? pinnedFrameIndex,
  required int conteStart,
}) =>
    pinnedFrameIndex != null && cell.covers(pinnedFrameIndex - conteStart)
    ? pinnedFrameIndex
    : conteStart + cell.startIndex;
