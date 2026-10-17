import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A canvas that keeps the box every paragraph is PAINTED in, through the
/// transforms the painter applies on the way.
///
/// ⚠️The oracle for where a glyph stands is what is painted, not the
/// layout's numbers: the centres were right all along while the painter
/// drew wide glyphs around them (F-93).
class PaintedGlyphBoxes implements Canvas {
  final boxes = <Rect>[];
  final _saved = <Matrix4>[];
  var _transform = Matrix4.identity();

  @override
  void save() => _saved.add(_transform.clone());

  @override
  void restore() => _transform = _saved.removeLast();

  @override
  void translate(double dx, double dy) =>
      _transform = _transform.multiplied(Matrix4.translationValues(dx, dy, 0));

  @override
  void rotate(double radians) =>
      _transform = _transform.multiplied(Matrix4.rotationZ(radians));

  @override
  void scale(double sx, [double? sy]) => _transform = _transform.multiplied(
    Matrix4.diagonal3Values(sx, sy ?? sx, 1),
  );

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => boxes.add(
    MatrixUtils.transformRect(
      _transform,
      offset & Size(paragraph.maxIntrinsicWidth, paragraph.height),
    ),
  );

  @override
  int getSaveCount() => _saved.length + 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
