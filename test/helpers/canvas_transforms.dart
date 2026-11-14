import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A canvas that follows the transforms a painter applies — what a test
/// canvas stands on to say where a thing was PAINTED, not where the layout
/// put it ([current]). Every other call it is handed does nothing.
///
/// ↩️[PaintedGlyphBoxes] followed them for itself, until `DrawnShapes` was
/// to be the second.
abstract class CanvasTransforms implements Canvas {
  final _saved = <Matrix4>[];
  var _transform = Matrix4.identity();

  /// Where the painter stands by now.
  Matrix4 get current => _transform;

  @override
  Float64List getTransform() => _transform.storage;

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
  void transform(Float64List matrix4) =>
      _transform = _transform.multiplied(Matrix4.fromFloat64List(matrix4));

  @override
  int getSaveCount() => _saved.length + 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
