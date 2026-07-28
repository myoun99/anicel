import 'package:flutter/rendering.dart' show Matrix4, MatrixUtils;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/canvas/layer_pose_paint.dart';

const _canvasSize = CanvasSize(width: 1280, height: 720);

TransformPose _pose() => TransformPose(
  center: CanvasPoint(x: 700, y: 400),
  zoom: 1.7,
  rotationDegrees: 33,
);

Offset _map(Matrix4 matrix, Offset point) =>
    MatrixUtils.transformPoint(matrix, point);

void _expectClose(Offset actual, Offset expected) {
  expect(actual.dx, closeTo(expected.dx, 1e-6));
  expect(actual.dy, closeTo(expected.dy, 1e-6));
}

void main() {
  group('layerPoseMatrix', () {
    test('the identity pose maps to the identity matrix', () {
      final matrix = layerPoseMatrix(
        TransformPose(center: CanvasPoint(x: 640, y: 360)),
        _canvasSize,
      );

      for (final point in const [
        Offset.zero,
        Offset(1280, 720),
        Offset(3, 9),
      ]) {
        _expectClose(_map(matrix, point), point);
      }
    });

    test('the anchor point lands exactly on pose.center (canvas center by '
        'default, the keyed anchor when present)', () {
      _expectClose(
        _map(layerPoseMatrix(_pose(), _canvasSize), const Offset(640, 360)),
        const Offset(700, 400),
      );
      _expectClose(
        _map(
          layerPoseMatrix(
            _pose(),
            _canvasSize,
            anchorPoint: CanvasPoint(x: 100, y: 50),
          ),
          const Offset(100, 50),
        ),
        const Offset(700, 400),
      );
    });

    test('pose ∘ inverse round-trips points — the draw-through requirement '
        '(inputs inverse-map to the exact original artwork coordinates)', () {
      final matrix = layerPoseMatrix(
        _pose(),
        _canvasSize,
        anchorPoint: CanvasPoint(x: 100, y: 50),
      );
      final inverse = Matrix4.inverted(matrix);

      for (final point in const [
        Offset.zero,
        Offset(640, 360),
        Offset(1280, 720),
        Offset(12.5, 703.25),
      ]) {
        _expectClose(_map(inverse, _map(matrix, point)), point);
        _expectClose(_map(matrix, _map(inverse, point)), point);
      }
    });

    test(
      'rasterScale adapts the same canvas-space pose to a scaled raster',
      () {
        const rasterScale = 0.25;
        final full = layerPoseMatrix(_pose(), _canvasSize);
        final scaled = layerPoseMatrix(
          _pose(),
          _canvasSize,
          rasterScale: rasterScale,
        );

        const artworkPoint = Offset(200, 500);
        final fullMapped = _map(full, artworkPoint);
        final scaledMapped = _map(scaled, artworkPoint * rasterScale);
        _expectClose(scaledMapped, fullMapped * rasterScale);
      },
    );
  });

  group('layerPoseViewportWrapMatrix', () {
    final viewport = CanvasViewport(zoom: 1.6, panX: 120, panY: -40);

    Offset viewportMap(Offset point) => Offset(
      viewport.panX + viewport.zoom * point.dx,
      viewport.panY + viewport.zoom * point.dy,
    );

    test('wrap ∘ viewport == viewport ∘ pose: wrapping the viewport-rendered '
        'artwork shows it posed exactly like the composite routes', () {
      final wrap = layerPoseViewportWrapMatrix(
        _pose(),
        _canvasSize,
        viewport,
        anchorPoint: CanvasPoint(x: 100, y: 50),
      );
      final poseMatrix = layerPoseMatrix(
        _pose(),
        _canvasSize,
        anchorPoint: CanvasPoint(x: 100, y: 50),
      );

      for (final artwork in const [
        Offset.zero,
        Offset(640, 360),
        Offset(1280, 720),
        Offset(87.5, 12.25),
      ]) {
        _expectClose(
          _map(wrap, viewportMap(artwork)),
          viewportMap(_map(poseMatrix, artwork)),
        );
      }
    });

    test('the wrap inverse routes a posed screen point back to the '
        'artwork\'s own viewport point — the hit-test path strokes ride', () {
      final wrap = layerPoseViewportWrapMatrix(_pose(), _canvasSize, viewport);
      final poseMatrix = layerPoseMatrix(_pose(), _canvasSize);
      final wrapInverse = Matrix4.inverted(wrap);

      const artwork = Offset(444, 222);
      final posedOnScreen = viewportMap(_map(poseMatrix, artwork));
      _expectClose(_map(wrapInverse, posedOnScreen), viewportMap(artwork));
    });
  });

  group('composeLayerPoseSamples (R9-B: cut ∘ layer in ONE wrap)', () {
    test('composing with the identity preserves the other pose\'s exact '
        'map', () {
      final LayerPoseSample identity = (
        pose: TransformPose(center: CanvasPoint(x: 640, y: 360)),
        anchorPoint: null,
      );
      final LayerPoseSample posed = (
        pose: _pose(),
        anchorPoint: CanvasPoint(x: 100, y: 50),
      );
      final original = layerPoseMatrix(
        posed.pose,
        _canvasSize,
        anchorPoint: posed.anchorPoint,
      );
      for (final composed in [
        composeLayerPoseSamples(identity, posed, _canvasSize),
        composeLayerPoseSamples(posed, identity, _canvasSize),
      ]) {
        final composedMatrix = layerPoseMatrix(
          composed.pose,
          _canvasSize,
          anchorPoint: composed.anchorPoint,
        );
        for (final point in const [
          Offset.zero,
          Offset(1280, 720),
          Offset(87.5, 12.25),
        ]) {
          _expectClose(_map(composedMatrix, point), _map(original, point));
        }
      }
    });

    test('the composed sample maps every point exactly like applying the '
        'two matrices in sequence (similarities compose exactly)', () {
      final LayerPoseSample outer = (
        pose: TransformPose(
          center: CanvasPoint(x: 500, y: 300),
          zoom: 0.8,
          rotationDegrees: -20,
        ),
        anchorPoint: CanvasPoint(x: 640, y: 360),
      );
      final LayerPoseSample inner = (
        pose: _pose(),
        anchorPoint: CanvasPoint(x: 100, y: 50),
      );
      final composed = composeLayerPoseSamples(outer, inner, _canvasSize);
      expect(composed.pose.zoom, closeTo(0.8 * 1.7, 1e-9));
      expect(composed.pose.rotationDegrees, closeTo(-20 + 33, 1e-9));

      final composedMatrix = layerPoseMatrix(
        composed.pose,
        _canvasSize,
        anchorPoint: composed.anchorPoint,
      );
      final product =
          layerPoseMatrix(
            outer.pose,
            _canvasSize,
            anchorPoint: outer.anchorPoint,
          )..multiply(
            layerPoseMatrix(
              inner.pose,
              _canvasSize,
              anchorPoint: inner.anchorPoint,
            ),
          );
      for (final point in const [
        Offset.zero,
        Offset(1280, 720),
        Offset(640, 360),
        Offset(87.5, 12.25),
      ]) {
        _expectClose(_map(composedMatrix, point), _map(product, point));
      }
    });
  });
}
