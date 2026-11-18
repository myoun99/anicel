import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'canvas_transforms.dart';

/// A canvas that keeps the box every paragraph is PAINTED in, through the
/// transforms the painter applies on the way.
///
/// ⚠️The oracle for where a glyph stands is what is painted, not the
/// layout's numbers: the centres were right all along while the painter
/// drew wide glyphs around them (F-93).
class PaintedGlyphBoxes extends CanvasTransforms {
  final boxes = <Rect>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => boxes.add(
    MatrixUtils.transformRect(
      current,
      offset & Size(paragraph.maxIntrinsicWidth, paragraph.height),
    ),
  );
}
