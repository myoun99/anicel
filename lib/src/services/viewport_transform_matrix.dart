import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../models/canvas_viewport.dart';

/// One factor of the viewport: whether it applies, its matrix, and its
/// EXACT inverse (translation negated, scale reciprocal, rotation negated,
/// flip self-inverse).
typedef _ViewportFactor = ({
  bool Function(CanvasViewport viewport) applies,
  Matrix4 Function(CanvasViewport viewport) forward,
  Matrix4 Function(CanvasViewport viewport) inverse,
});

bool _always(CanvasViewport _) => true;
bool _rotated(CanvasViewport v) => v.rotationDegrees != 0;
bool _flipped(CanvasViewport v) => v.flipHorizontal || v.flipVertical;

Matrix4 _pan(CanvasViewport v) => Matrix4.translationValues(v.panX, v.panY, 0);
Matrix4 _unpan(CanvasViewport v) =>
    Matrix4.translationValues(-v.panX, -v.panY, 0);
Matrix4 _zoom(CanvasViewport v) => Matrix4.diagonal3Values(v.zoom, v.zoom, 1);
Matrix4 _unzoom(CanvasViewport v) =>
    Matrix4.diagonal3Values(1 / v.zoom, 1 / v.zoom, 1);
Matrix4 _rotate(CanvasViewport v) => Matrix4.rotationZ(v.rotationRadians);
Matrix4 _unrotate(CanvasViewport v) => Matrix4.rotationZ(-v.rotationRadians);
Matrix4 _flip(CanvasViewport v) => Matrix4.diagonal3Values(
  v.flipHorizontal ? -1 : 1,
  v.flipVertical ? -1 : 1,
  1,
);

/// The viewport's factors in application order. The forward matrix
/// composes them as listed; the inverse composes the inverses in reverse —
/// so a factor added here is added to both, and neither side can be edited
/// alone. A const table of functions rather than built pairs: only the
/// matrices a call actually multiplies are allocated (this runs per paint
/// and hit-test of a posed layer).
const _viewportFactors = <_ViewportFactor>[
  (applies: _always, forward: _pan, inverse: _unpan),
  (applies: _always, forward: _zoom, inverse: _unzoom),
  (applies: _rotated, forward: _rotate, inverse: _unrotate),
  (applies: _flipped, forward: _flip, inverse: _flip),
];

/// The viewport as a matrix — for Transform widgets and the layer-pose
/// viewport wrap. `applyViewportTransform` (ui) paints the same mapping.
///
/// ⛔UNSNAPPED on purpose: the pose wrap is V · P · V⁻¹ and must cancel to
/// identity at the identity pose, and Flutter routes hit testing through
/// this matrix — both need the exact mapping, not the render phase.
Matrix4 viewportTransformMatrix(CanvasViewport viewport) {
  final matrix = Matrix4.identity();
  for (final factor in _viewportFactors) {
    if (factor.applies(viewport)) {
      matrix.multiply(factor.forward(viewport));
    }
  }
  return matrix;
}

/// The exact inverse of [viewportTransformMatrix], built analytically
/// (flip⁻¹ · rotate⁻¹ · scale⁻¹ · translate⁻¹) instead of a numeric
/// inversion.
Matrix4 viewportInverseTransformMatrix(CanvasViewport viewport) {
  final matrix = Matrix4.identity();
  for (final factor in _viewportFactors.reversed) {
    if (factor.applies(viewport)) {
      matrix.multiply(factor.inverse(viewport));
    }
  }
  return matrix;
}

/// The viewport a pan · zoom · rotation [matrix] IS — [viewportTransformMatrix]
/// run backwards, for a chain of such maps one brush view has to see
/// through (a sheet's picture: the panel, the slot, the camera and the
/// layer's placement). Null when [matrix] is not one: a shear, a mirror or
/// a collapse has no viewport.
CanvasViewport? viewportOfSimilarity(Matrix4 matrix) {
  final a = matrix.entry(0, 0);
  final b = matrix.entry(1, 0);
  final zoom = math.sqrt(a * a + b * b);
  final slack = zoom * 1e-9;
  if (zoom == 0 ||
      (matrix.entry(1, 1) - a).abs() > slack ||
      (matrix.entry(0, 1) + b).abs() > slack) {
    return null;
  }
  return CanvasViewport(
    zoom: zoom,
    panX: matrix.entry(0, 3),
    panY: matrix.entry(1, 3),
    rotationDegrees: math.atan2(b, a) * 180 / math.pi,
  );
}
