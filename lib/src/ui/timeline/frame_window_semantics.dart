import 'dart:ui' show Rect, TextDirection;

import 'package:flutter/rendering.dart'
    show CustomPainterSemantics, SemanticsProperties;

import 'timeline_grid_metrics.dart' show timelineFirstOnStride;

/// One semantics node per LABELLED frame of [window]: the frame ruler and
/// the X-sheet's frame rail walk their visible frame window and emit a node
/// where a label exists — the per-cell widget tree used to emit these; the
/// painted strips keep the a11y surface without the widget cost. (The
/// painted drawing rows say their window in one node:
/// [frameWindowSentence].)
///
/// [labelFor] answering null skips the frame (the strips label only the
/// frames they write a number on). Rect and label are VALUE parameters —
/// one walk for every strip (the audit's clone scan, 2026-09-06).
/// Semantics building runs only with semantics enabled and once per frame,
/// never per pixel.
///
/// [step] walks only every [step]th frame, from the first one on it: a
/// strip asks only the frames a mark can stand on, as its paint does.
/// ↩️"Once per frame of the window is no hot-loop concern" held while a
/// window was a few hundred frames; I-22's ten-minute floor puts ~19,000
/// in one.
List<CustomPainterSemantics> frameWindowSemantics({
  required ({int startIndex, int endIndexExclusive}) window,
  required Rect Function(int frameIndex) rectFor,
  required String? Function(int frameIndex) labelFor,
  int step = 1,
}) {
  final nodes = <CustomPainterSemantics>[];
  for (
    var frameIndex = timelineFirstOnStride(window.startIndex, step);
    frameIndex < window.endIndexExclusive;
    frameIndex += step
  ) {
    final label = labelFor(frameIndex);
    if (label == null) {
      continue;
    }
    nodes.add(
      CustomPainterSemantics(
        rect: rectFor(frameIndex),
        properties: SemanticsProperties(
          label: label,
          textDirection: TextDirection.ltr,
        ),
      ),
    );
  }
  return nodes;
}

/// ONE semantics node for a row's [window], saying in frame order what each
/// of its labelled cells says — a run of cells that say the same said once,
/// with its frames ("held exposure, frames 2 to 6"). Nothing where no cell
/// of the window says anything.
///
/// 🚨ONE NODE A ROW, NOT ONE A CELL (I-57-Q3 c, 유저 2026-10-15: 「b c 등
/// 거기서 좋은. 하면 좋은 대응들을 전부 하고싶음. 극한으로 성능 내기위함」).
/// A cut crossing moves every row's window a page, and a node a cell was
/// every visible cell's node made afresh — 🔬~0.9ms of the crossing's frame
/// on a machine whose accessibility tree is on (10-15). The cost the user
/// took: a screen reader no longer steps cell by cell; it reads the row.
/// ↩️Until then a row said a node per non-empty cell
/// ([frameWindowSemantics]); keeping it so (10-11) was an AI call, not the
/// user's.
///
/// [cellAt] answers the cell's sentence, and whether the cell carries on
/// the run before it when it says the same (`runsOn` — a held cell) rather
/// than beginning one of its own (a block's first cell, even one that reads
/// like the block before it). Each cell is asked once.
List<CustomPainterSemantics> frameWindowSentence({
  required ({int startIndex, int endIndexExclusive}) window,
  required Rect Function(int frameIndex) rectFor,
  required ({String label, bool runsOn})? Function(int frameIndex) cellAt,
}) {
  final pieces = <String>[];
  String? label;
  var first = 0;
  var last = 0;
  void said() {
    final run = label;
    if (run != null) {
      pieces.add(
        first == last
            ? '$run, frame ${first + 1}'
            : '$run, frames ${first + 1} to ${last + 1}',
      );
    }
  }

  for (
    var frameIndex = window.startIndex;
    frameIndex < window.endIndexExclusive;
    frameIndex += 1
  ) {
    final cell = cellAt(frameIndex);
    if (cell != null && cell.runsOn && cell.label == label) {
      last = frameIndex;
      continue;
    }
    said();
    label = cell?.label;
    first = last = frameIndex;
  }
  said();
  if (pieces.isEmpty) {
    return const <CustomPainterSemantics>[];
  }
  return [
    CustomPainterSemantics(
      rect: rectFor(
        window.startIndex,
      ).expandToInclude(rectFor(window.endIndexExclusive - 1)),
      properties: SemanticsProperties(
        label: pieces.join('; '),
        textDirection: TextDirection.ltr,
      ),
    ),
  ];
}
