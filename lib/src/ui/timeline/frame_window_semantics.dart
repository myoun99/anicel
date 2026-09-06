import 'dart:ui' show Rect, TextDirection;

import 'package:flutter/rendering.dart'
    show CustomPainterSemantics, SemanticsProperties;

/// One semantics node per LABELLED frame of [window]: the frame ruler, the
/// painted drawing rows and the X-sheet's frame rail all walk their
/// visible frame window and emit a node where a label exists — the
/// per-cell widget tree used to emit these; the painted strips keep the
/// a11y surface without the widget cost.
///
/// [labelFor] answering null skips the frame (the ruler labels only the
/// headers it prints a number on; the rows label only non-empty cells; the
/// rail labels every row). Rect and label are VALUE parameters — one walk,
/// three painters (the audit's clone scan, 2026-09-06). Semantics building
/// runs only with semantics enabled and once per frame, never per pixel,
/// so the per-frame callback is not a hot-loop concern.
List<CustomPainterSemantics> frameWindowSemantics({
  required ({int startIndex, int endIndexExclusive}) window,
  required Rect Function(int frameIndex) rectFor,
  required String? Function(int frameIndex) labelFor,
}) {
  final nodes = <CustomPainterSemantics>[];
  for (
    var frameIndex = window.startIndex;
    frameIndex < window.endIndexExclusive;
    frameIndex += 1
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
