import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import '../../models/text_cel_style.dart';

/// A TEXT'S LETTERS AS THE SHAPES THEY COVER, one layer at a time — what
/// the GPU engine is handed to raster them itself (`engine_letters.dart`,
/// cel-number-on-the-engine-letters): where the app's layout put each
/// cluster, and which paint a layer covers in. Which glyph a cluster takes
/// and how it rasters is the engine's; where it stands is the layout's, and
/// the engine keeps no copy of why.
///
/// One layer is one of `CanvasLetterPasses.layers` — or the box behind
/// them — in one paint: its colour over what its shapes cover, filled or
/// outlined that wide, hard or not.
typedef CanvasLetterShapes = ({
  int argb,
  bool hard,
  double outline,
  List<CanvasLetterShape> shapes,
});

/// What one layer of a text's letters covers.
sealed class CanvasLetterShape {
  const CanvasLetterShape();
}

/// A line of letters in one style, at [size]: each grapheme cluster with
/// its box's left and its line's baseline where the layout set them.
final class CanvasLetterClusters extends CanvasLetterShape {
  const CanvasLetterClusters({
    required this.letters,
    required this.size,
    required this.clusters,
  });

  final TextLetterStyle letters;
  final double size;
  final List<CanvasLetterCluster> clusters;
}

/// A box behind the letters, or a line they wear.
final class CanvasLetterRect extends CanvasLetterShape {
  const CanvasLetterRect(this.rect);

  final ui.Rect rect;
}

typedef CanvasLetterCluster = ({String text, double left, double baseline});

/// Where [painter] set each grapheme cluster of its letters, a line's
/// clusters at a time, its corner at [at] — read off its layout, a
/// cluster's box and the line it lies on: the box's left and that line's
/// baseline.
///
/// ⚠️A line's break is no cluster: the layout draws nothing for it, where
/// an engine handed it would look for its glyph — and draw the box a face
/// draws for a letter it lacks.
List<List<CanvasLetterCluster>> canvasLetterClustersOf(
  TextPainter painter,
  ui.Offset at,
) {
  final text = painter.plainText;
  final lines = painter.computeLineMetrics();
  final clusters = [for (final _ in lines) <CanvasLetterCluster>[]];
  var start = 0;
  for (final cluster in text.characters) {
    final end = start + cluster.length;
    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );
    start = end;
    if (boxes.isEmpty || cluster.contains('\n')) {
      continue;
    }
    final box = boxes.first;
    final line = _lineHolding(lines, (box.top + box.bottom) / 2);
    clusters[line].add((
      text: cluster,
      left: at.dx + box.left,
      baseline: at.dy + lines[line].baseline,
    ));
  }
  return [
    for (final line in clusters)
      if (line.isNotEmpty) line,
  ];
}

/// The line of [lines] whose height holds [y] — the last one past them.
int _lineHolding(List<ui.LineMetrics> lines, double y) {
  for (final (index, line) in lines.indexed) {
    if (y < line.baseline - line.ascent + line.height) {
      return index;
    }
  }
  return lines.length - 1;
}
