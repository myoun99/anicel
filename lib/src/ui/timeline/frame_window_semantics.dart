import 'dart:ui' show Rect, TextDirection;

import 'package:flutter/rendering.dart'
    show CustomPainterSemantics, SemanticsProperties;

import 'timeline_grid_metrics.dart' show timelineFirstOnStride;

/// One semantics node per LABELLED frame of [window]: the frame ruler, the
/// painted drawing rows and the X-sheet's frame rail all walk their
/// visible frame window and emit a node where a label exists — the
/// per-cell widget tree used to emit these; the painted strips keep the
/// a11y surface without the widget cost.
///
/// [labelFor] answering null skips the frame (the strips label only the
/// frames they write a number on; the rows label only non-empty cells).
/// Rect and label are VALUE parameters — one walk, three painters (the
/// audit's clone scan, 2026-09-06). Semantics building runs only with
/// semantics enabled and once per frame, never per pixel.
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
