import 'package:flutter/foundation.dart';

import '../../models/layer_kind.dart';

/// What the flip HUD DRAWS — a read-only snapshot of the rows the timeline
/// is showing, taken after a flip step has landed.
///
/// The HUD never computes movement. The gesture emits the same action ids
/// the arrow keys do, the session decides where that lands, and the HUD
/// asks for a fresh snapshot and redraws. That is what keeps it a display:
/// change the navigation rules (R10 made property rows landable) and the
/// HUD follows without knowing it happened.

/// One stretch of CONTENT on a row: a drawing block, a key, an SE span.
///
/// Emptiness is deliberately NOT a run — the app's timeline model does not
/// author empty entries either ("Emptiness is NOT a timeline entry"), so a
/// gap here is the absence of a run, exactly as it is there.
@immutable
class FlipHudRun {
  const FlipHudRun({
    required this.startIndex,
    required this.length,
    this.label = '',
    this.isKey = false,
    this.holdKey = false,
  }) : assert(length >= 1, 'A run covers at least one frame.');

  final int startIndex;
  final int length;

  /// The cel name printed in the block. Empty prints the timeline's `○`.
  final String label;

  /// A property key rather than a picture: drawn as the lane diamond
  /// (square when [holdKey]) instead of a paper body.
  final bool isKey;
  final bool holdKey;

  int get endIndexExclusive => startIndex + length;

  bool covers(int frameIndex) =>
      frameIndex >= startIndex && frameIndex < endIndexExclusive;
}

/// One row of the HUD — a layer row or one of its property lanes, named
/// and ordered exactly as the timeline stacks them.
@immutable
class FlipHudRow {
  const FlipHudRow({
    required this.name,
    required this.kind,
    required this.runs,
    this.isLane = false,
    this.holdsDrawings = true,
    this.showsKindIcon = true,
  });

  final String name;

  /// Drives the rail's kind icon — the same [LayerKind] the rails read.
  final LayerKind kind;

  /// Whether the rail draws that icon. A property lane carries its
  /// property's name, not its owner's kind, and a TRACK row is not a
  /// layer at all; neither should be stamped with a layer glyph the
  /// timeline has never drawn on them.
  final bool showsKindIcon;

  /// Content runs in frame order, non-overlapping.
  final List<FlipHudRun> runs;

  final bool isLane;

  /// Whether an uncovered cell on this row prints the timesheet `X`. The
  /// cells painter's own rule: only rows that hold drawings do.
  final bool holdsDrawings;

  FlipHudRun? runAt(int frameIndex) {
    for (final run in runs) {
      if (run.covers(frameIndex)) {
        return run;
      }
    }
    return null;
  }

  /// The FIRST cell of an empty stretch — where the `X` goes.
  bool emptyRunStartsAt(int frameIndex) =>
      runAt(frameIndex) == null &&
      (frameIndex == 0 || runAt(frameIndex - 1) != null);
}

@immutable
class FlipHudSnapshot {
  const FlipHudSnapshot({
    required this.rows,
    required this.rowIndex,
    required this.frameIndex,
    required this.frameCount,
  });

  static const FlipHudSnapshot empty = FlipHudSnapshot(
    rows: <FlipHudRow>[],
    rowIndex: 0,
    frameIndex: 0,
    frameCount: 0,
  );

  /// The displayed rows, in the timeline's own order — filtered, folded
  /// and section-hidden exactly as they are on screen.
  final List<FlipHudRow> rows;

  /// Which row the flip is standing on.
  final int rowIndex;

  final int frameIndex;
  final int frameCount;

  bool get isEmpty => rows.isEmpty || frameCount <= 0;

  FlipHudRow? get currentRow =>
      rowIndex >= 0 && rowIndex < rows.length ? rows[rowIndex] : null;

  /// THE haptic subject: the run under the cursor, as an identity that
  /// changes when — and only when — the picture does.
  ///
  /// One definition serves both axes. Stepping along the frame axis moves
  /// off a block onto another; stepping along the row axis lands on a
  /// different row's run. Empty space and a clamped end both answer null
  /// or the same value, which is why "tick when this changes" needs no
  /// per-case rules.
  String? get contentKey {
    final row = currentRow;
    final run = row?.runAt(frameIndex);
    return run == null ? null : '$rowIndex:${run.startIndex}';
  }
}

/// One column of the HUD strip.
@immutable
class FlipHudSlot {
  const FlipHudSlot({required this.startIndex, required this.frames, this.run});

  final int startIndex;

  /// How many frames this column stands for — 1 on the frame axis, the
  /// run's length (or 1, for an uncovered frame) on the block axis.
  final int frames;

  final FlipHudRun? run;

  bool get filled => run != null;

  bool covers(int frameIndex) =>
      frameIndex >= startIndex && frameIndex < startIndex + frames;
}

/// The BLOCK axis: one column per content run, one column per uncovered
/// frame, every column the same width.
///
/// Giving each empty frame its own column is what lets the block axis stay
/// honest without changing navigation. A flip jumps from block to block, so
/// the empty columns are travelled over rather than landed on — except at a
/// cut's head and tail, where the app already walks one frame at a time and
/// the columns are exactly the steps it takes.
List<FlipHudSlot> flipHudBlockSlots(FlipHudRow row, int frameCount) {
  final slots = <FlipHudSlot>[];
  var frame = 0;
  while (frame < frameCount) {
    final run = row.runAt(frame);
    if (run == null) {
      slots.add(FlipHudSlot(startIndex: frame, frames: 1));
      frame += 1;
      continue;
    }
    slots.add(
      FlipHudSlot(startIndex: run.startIndex, frames: run.length, run: run),
    );
    frame = run.endIndexExclusive;
  }
  return slots;
}

/// The FRAME axis: one column per frame. A run's columns all carry it, so
/// the painter can span one body across a block and still know where the
/// block starts.
List<FlipHudSlot> flipHudFrameSlots(FlipHudRow row, int frameCount) => [
  for (var frame = 0; frame < frameCount; frame += 1)
    FlipHudSlot(startIndex: frame, frames: 1, run: row.runAt(frame)),
];

/// The first column the painter must actually VISIT, given the first one
/// that is visible.
///
/// Only a run's HEAD column paints its body — the head spans the whole
/// run in one piece, the way a timeline block does. So culling to the
/// visible window has to keep the head: a forty-frame block scrolled to
/// its middle would otherwise have nothing left to draw it, and the
/// window would show bare grid where a block plainly is.
int flipHudFirstPaintedIndex(List<FlipHudSlot> slots, int firstVisible) {
  if (slots.isEmpty) {
    return 0;
  }
  var index = firstVisible.clamp(0, slots.length - 1);
  final covering = slots[index].run;
  if (covering == null) {
    return index;
  }
  while (index > 0 && slots[index - 1].run == covering) {
    index -= 1;
  }
  return index;
}

/// Which column holds [frameIndex]; 0 when the list is empty.
int flipHudSlotIndexAt(List<FlipHudSlot> slots, int frameIndex) {
  for (var index = slots.length - 1; index >= 0; index -= 1) {
    if (frameIndex >= slots[index].startIndex) {
      return index;
    }
  }
  return 0;
}
