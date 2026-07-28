import 'package:flutter/rendering.dart' show Matrix4, MatrixUtils, Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/canvas/layer_pose_paint.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';

/// P8 painter-parity pins: the shared paint matrix must speak EXACTLY the
/// viewport's coordinate mapping, and its analytic inverse must undo it —
/// otherwise painted pixels and pointer math drift apart.
void main() {
  final assortedViewports = [
    CanvasViewport(),
    CanvasViewport(zoom: 2.5, panX: 33, panY: -7),
    CanvasViewport(rotationDegrees: 45),
    CanvasViewport(flipHorizontal: true),
    CanvasViewport(
      zoom: 0.6,
      panX: -20,
      panY: 14,
      rotationDegrees: -120,
      flipHorizontal: true,
    ),
  ];

  final assortedPoints = [
    CanvasPoint(x: 0, y: 0),
    CanvasPoint(x: 64, y: 128),
    CanvasPoint(x: -5.5, y: 7.25),
  ];

  test('viewportTransformMatrix maps points exactly like canvasToViewport', () {
    for (final viewport in assortedViewports) {
      final matrix = viewportTransformMatrix(viewport);
      for (final point in assortedPoints) {
        final expected = viewport.canvasToViewport(point);
        final mapped = MatrixUtils.transformPoint(
          matrix,
          Offset(point.x, point.y),
        );
        expect(mapped.dx, closeTo(expected.x, 1e-6), reason: '$viewport');
        expect(mapped.dy, closeTo(expected.y, 1e-6), reason: '$viewport');
      }
    }
  });

  test('the analytic inverse undoes the transform', () {
    for (final viewport in assortedViewports) {
      final product = viewportTransformMatrix(
        viewport,
      ).multiplied(viewportInverseTransformMatrix(viewport));
      final identity = Matrix4.identity();
      for (var i = 0; i < 16; i += 1) {
        expect(
          product.storage[i],
          closeTo(identity.storage[i], 1e-9),
          reason: '$viewport [$i]',
        );
      }
    }
  });

  test('an identity pose wraps to identity under ANY viewport', () {
    const canvasSize = CanvasSize(width: 200, height: 100);
    final identityPose = TransformPose(
      center: CanvasPoint(x: 100, y: 50),
      zoom: 1,
      rotationDegrees: 0,
    );
    for (final viewport in assortedViewports) {
      final wrap = layerPoseViewportWrapMatrix(
        identityPose,
        canvasSize,
        viewport,
      );
      final identity = Matrix4.identity();
      for (var i = 0; i < 16; i += 1) {
        expect(
          wrap.storage[i],
          closeTo(identity.storage[i], 1e-6),
          reason: '$viewport [$i]',
        );
      }
    }
  });
}
