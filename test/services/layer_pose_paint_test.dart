import 'package:flutter/rendering.dart' show Matrix4, MatrixUtils;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart'
    show placementUnderFolders;
import 'package:anicel/src/services/layer_pose_paint.dart';

import '../helpers/placement_reading.dart';

const _canvasSize = CanvasSize(width: 1280, height: 720);

TransformPose _pose() => TransformPose.uniform(
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
      'rasterScale adapts the same canvas-space placement to a scaled '
      'raster',
      () {
        const rasterScale = 0.25;
        final full = layerPoseMatrix(_pose(), _canvasSize);
        final scaled = placementMatrix(
          placedBy(_pose(), _canvasSize),
          rasterScale: rasterScale,
        );

        const artworkPoint = Offset(200, 500);
        final fullMapped = _map(full, artworkPoint);
        final scaledMapped = _map(scaled, artworkPoint * rasterScale);
        _expectClose(scaledMapped, fullMapped * rasterScale);
      },
    );
  });

  group('placementViewportWrapMatrix', () {
    final viewport = CanvasViewport(zoom: 1.6, panX: 120, panY: -40);

    Offset viewportMap(Offset point) => Offset(
      viewport.panX + viewport.zoom * point.dx,
      viewport.panY + viewport.zoom * point.dy,
    );

    test('wrap ∘ viewport == viewport ∘ pose: wrapping the viewport-rendered '
        'artwork shows it posed exactly like the composite routes', () {
      final wrap = placementViewportWrapMatrix(
        placedBy(
          _pose(),
          _canvasSize,
          anchorPoint: CanvasPoint(x: 100, y: 50),
        ),
        viewport,
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
      final wrap = placementViewportWrapMatrix(
        placedBy(_pose(), _canvasSize),
        viewport,
      );
      final poseMatrix = layerPoseMatrix(_pose(), _canvasSize);
      final wrapInverse = Matrix4.inverted(wrap);

      const artwork = Offset(444, 222);
      final posedOnScreen = viewportMap(_map(poseMatrix, artwork));
      _expectClose(_map(wrapInverse, posedOnScreen), viewportMap(artwork));
    });
  });

  // 🗣️F-256-Q1 (유저 2026-10-06): 「가른다 — AE 처럼 Scale X · Y」. ↩️This
  // group pinned `composeLayerPoseSamples`, which folded two poses into ONE
  // POSE — zooms multiplied, turns added (R9-B: cut ∘ layer in one wrap).
  // That is every fold there is while a pose is a similarity, and no fold
  // at all once a folder can stretch one axis: the last pin is that case.
  group('placementUnderFolders — a folder chain is ONE placement', () {
    final LayerPoseSample turned = (
      pose: _pose(),
      anchorPoint: CanvasPoint(x: 100, y: 50),
    );
    final LayerPoseSample shrunk = (
      pose: TransformPose.uniform(
        center: CanvasPoint(x: 500, y: 300),
        zoom: 0.8,
        rotationDegrees: -20,
      ),
      anchorPoint: CanvasPoint(x: 640, y: 360),
    );

    Matrix4 matrixOf(LayerPoseSample sample) => layerPoseMatrix(
      sample.pose,
      _canvasSize,
      anchorPoint: sample.anchorPoint,
    );

    LayerPlacement? under(
      List<LayerPoseSample> folders,
      LayerPoseSample? row,
    ) => placementUnderFolders(
      folderPoses: folders,
      layerSample: row,
      canvasSize: _canvasSize,
    );

    void expectMapsAs(LayerPlacement? placement, Matrix4 expected) {
      final matrix = placementMatrix(placement!);
      for (final point in const [
        Offset.zero,
        Offset(1280, 720),
        Offset(640, 360),
        Offset(87.5, 12.25),
      ]) {
        _expectClose(_map(matrix, point), _map(expected, point));
      }
    }

    test('a row under no posed folder lies where its own pose puts it — '
        'and with no pose of its own, nowhere but where it is', () {
      expect(
        under(const [], turned),
        placedBy(
          turned.pose,
          _canvasSize,
          anchorPoint: turned.anchorPoint,
        ),
      );
      expect(under(const [], null), isNull);
    });

    test('an unposed row in a posed folder lies where the folder puts it', () {
      expectMapsAs(under([shrunk], null), matrixOf(shrunk));
    });

    test('the fold is the PRODUCT, the outermost folder first', () {
      final LayerPoseSample moved = (
        pose: TransformPose(center: CanvasPoint(x: 900, y: 100)),
        anchorPoint: null,
      );

      expectMapsAs(
        under([moved, shrunk], turned),
        matrixOf(moved)
          ..multiply(matrixOf(shrunk))
          ..multiply(matrixOf(turned)),
      );
      // Order is the point: a move outside a turn is not a turn outside a
      // move.
      expect(
        under([moved, shrunk], turned),
        isNot(under([shrunk, moved], turned)),
      );
    });

    test('🚨a folder stretched along ONE axis over a turned row SHEARS the '
        'row — the product says so, and no pose could', () {
      final LayerPoseSample stretched = (
        pose: TransformPose(center: CanvasPoint(x: 640, y: 360), scaleX: 2),
        anchorPoint: null,
      );
      final LayerPoseSample askew = (
        pose: TransformPose(
          center: CanvasPoint(x: 640, y: 360),
          rotationDegrees: 45,
        ),
        anchorPoint: null,
      );

      final folded = under([stretched], askew)!;

      expectMapsAs(folded, matrixOf(stretched)..multiply(matrixOf(askew)));
      // The row's own two axes, as the canvas shows them, no longer stand
      // square to one another — which a centre, two scales and a turn can
      // never say.
      expect(
        folded.a * folded.c + folded.b * folded.d,
        closeTo(-1.5, 1e-9),
      );
    });
  });
}
