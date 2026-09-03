import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../models/canvas_viewport.dart';

/// The viewport as a matrix — for Transform widgets and the layer-pose
/// viewport wrap. `applyViewportTransform` (ui) paints the same mapping.
///
/// ⛔UNSNAPPED on purpose: the pose wrap is V · P · V⁻¹ and must cancel to
/// identity at the identity pose, and Flutter routes hit testing through
/// this matrix — both need the exact mapping, not the render phase.
Matrix4 viewportTransformMatrix(CanvasViewport viewport) {
  final matrix = Matrix4.translationValues(viewport.panX, viewport.panY, 0)
    ..multiply(Matrix4.diagonal3Values(viewport.zoom, viewport.zoom, 1));
  if (viewport.rotationDegrees != 0) {
    matrix.multiply(Matrix4.rotationZ(viewport.rotationRadians));
  }
  if (viewport.flipHorizontal || viewport.flipVertical) {
    matrix.multiply(
      Matrix4.diagonal3Values(
        viewport.flipHorizontal ? -1 : 1,
        viewport.flipVertical ? -1 : 1,
        1,
      ),
    );
  }
  return matrix;
}

/// The exact inverse of [viewportTransformMatrix], built analytically
/// (flip⁻¹ · rotate⁻¹ · scale⁻¹ · translate⁻¹) instead of a numeric
/// inversion.
Matrix4 viewportInverseTransformMatrix(CanvasViewport viewport) {
  final matrix = Matrix4.identity();
  if (viewport.flipHorizontal || viewport.flipVertical) {
    matrix.multiply(
      Matrix4.diagonal3Values(
        viewport.flipHorizontal ? -1 : 1,
        viewport.flipVertical ? -1 : 1,
        1,
      ),
    );
  }
  if (viewport.rotationDegrees != 0) {
    matrix.multiply(Matrix4.rotationZ(-viewport.rotationRadians));
  }
  matrix
    ..multiply(Matrix4.diagonal3Values(1 / viewport.zoom, 1 / viewport.zoom, 1))
    ..multiply(Matrix4.translationValues(-viewport.panX, -viewport.panY, 0));
  return matrix;
}
