import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/tiles_covering.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart';
import 'package:anicel/src/services/viewport_transform_matrix.dart';

/// The three geometry laws no test named — each one carries a decision
/// comment that says what breaks when it drifts, and none of them had a
/// test that would notice (the audit's untested-file pass, 2026-09-05).
void main() {
  group('the viewport matrix and its analytic inverse', () {
    final viewports = <String, CanvasViewport>{
      'identity': CanvasViewport(),
      'pan': CanvasViewport(panX: 37.5, panY: -12.25),
      'zoom': CanvasViewport(zoom: 2.5),
      'rotation': CanvasViewport(rotationDegrees: 31),
      'flip H': CanvasViewport(flipHorizontal: true),
      'flip V': CanvasViewport(flipVertical: true),
      'all of it': CanvasViewport(
        zoom: 0.75,
        panX: -8,
        panY: 140,
        rotationDegrees: -17,
        flipHorizontal: true,
        flipVertical: true,
      ),
    };

    for (final entry in viewports.entries) {
      test('${entry.key}: V · V⁻¹ is the identity', () {
        final wrapped = viewportTransformMatrix(
          entry.value,
        ).multiplied(viewportInverseTransformMatrix(entry.value));
        _expectMatrix(wrapped, Matrix4.identity());
      });

      test('${entry.key}: the inverse is EXACT, not a numeric inversion', () {
        // The reason the inverse is built analytically: an inverted copy
        // and this are the same matrix, so nothing downstream has to care
        // which one it got.
        _expectMatrix(
          viewportInverseTransformMatrix(entry.value),
          Matrix4.inverted(viewportTransformMatrix(entry.value)),
        );
      });
    }

    test('the identity viewport is the identity matrix — the pose wrap is '
        'V · P · V⁻¹ and must cancel', () {
      _expectMatrix(
        viewportTransformMatrix(CanvasViewport()),
        Matrix4.identity(),
      );
    });

    test('the matrix is UNSNAPPED — a fractional pan survives, because hit '
        'testing routes through it', () {
      final matrix = viewportTransformMatrix(CanvasViewport(panX: 10.4));
      expect(matrix.getTranslation().x, 10.4);
    });

    test('zoom scales x and y only — a Transform must not touch z', () {
      final matrix = viewportTransformMatrix(CanvasViewport(zoom: 3));
      expect(_apply(matrix, 2, 5), _point(6, 15));
      expect(matrix.entry(2, 2), 1);
    });

    test('a horizontal flip mirrors x and leaves y', () {
      final matrix = viewportTransformMatrix(
        CanvasViewport(flipHorizontal: true),
      );
      expect(_apply(matrix, 4, 7), _point(-4, 7));
    });
  });

  group('the layer pose matrix', () {
    const canvas = CanvasSize(width: 100, height: 60);
    CameraPose poseAt(double x, double y, {double zoom = 1, double turn = 0}) =>
        CameraPose(
          center: CanvasPoint(x: x, y: y),
          zoom: zoom,
          rotationDegrees: turn,
        );

    test('the identity pose is the identity matrix, by construction', () {
      _expectMatrix(
        layerPoseMatrix(poseAt(50, 30), canvas),
        Matrix4.identity(),
      );
    });

    test('a NULL anchor is the canvas centre — the historical default', () {
      // Moving the pose centre by (10, 4) with no anchor keyed moves the
      // artwork by exactly that: the centre is what lands on it.
      final matrix = layerPoseMatrix(poseAt(60, 34), canvas);
      expect(_apply(matrix, 50, 30), _point(60, 34));
      expect(_apply(matrix, 0, 0), _point(10, 4));
    });

    test('a KEYED anchor is what lands on the pose centre, not the middle '
        'of the canvas', () {
      final matrix = layerPoseMatrix(
        poseAt(50, 30),
        canvas,
        anchorPoint: CanvasPoint(x: 0, y: 0),
      );
      expect(_apply(matrix, 0, 0), _point(50, 30));
    });

    test('zoom scales ABOUT the anchor, so the anchor does not move', () {
      final matrix = layerPoseMatrix(poseAt(50, 30, zoom: 3), canvas);
      expect(_apply(matrix, 50, 30), _point(50, 30));
      expect(_apply(matrix, 60, 30), _point(80, 30));
    });

    test('rotation turns CLOCKWISE about the anchor', () {
      final matrix = layerPoseMatrix(poseAt(50, 30, turn: 90), canvas);
      // A point to the anchor's right ends up BELOW it: y grows downward,
      // so a positive angle reads clockwise on screen.
      expect(_apply(matrix, 60, 30), _point(50, 40));
    });

    test('rasterScale restates the SAME pose in a scaled raster', () {
      // The playback quality tiers render at half size and must land the
      // same picture: every canvas-space coordinate simply halves.
      final full = layerPoseMatrix(poseAt(60, 34, zoom: 2), canvas);
      final half = layerPoseMatrix(
        poseAt(60, 34, zoom: 2),
        canvas,
        rasterScale: 0.5,
      );
      final fullPoint = _apply(full, 20, 10);
      expect(_apply(half, 10, 5), _point(fullPoint.dx / 2, fullPoint.dy / 2));
    });
  });

  group('tilesCovering', () {
    BitmapSurface surfaceWith(List<TileCoord> coords) => BitmapSurface(
      canvasSize: const CanvasSize(width: 32, height: 32),
      tileSize: 8,
      tiles: {
        for (final coord in coords)
          coord: BitmapTile.blank(coord: coord, size: 8),
      },
    );

    test('a region inside one tile clips to the region itself', () {
      final covered = tilesCovering(
        surfaceWith([TileCoord(x: 0, y: 0)]),
        DirtyRegion(left: 2, top: 3, rightExclusive: 5, bottomExclusive: 6),
      ).toList();

      expect(covered, hasLength(1));
      expect((covered.single.left, covered.single.top), (2, 3));
      expect(
        (covered.single.rightExclusive, covered.single.bottomExclusive),
        (5, 6),
      );
      expect((covered.single.worldLeft, covered.single.worldTop), (0, 0));
    });

    test('a region spanning tiles clips each one to the tile it is in', () {
      final covered = tilesCovering(
        surfaceWith([TileCoord(x: 0, y: 0), TileCoord(x: 1, y: 0)]),
        DirtyRegion(left: 6, top: 0, rightExclusive: 10, bottomExclusive: 4),
      ).toList();

      expect(covered.map((c) => c.tile.coord.x), [0, 1]);
      expect(covered[0].rightExclusive, 8, reason: 'clipped at the tile wall');
      expect(covered[1].left, 8, reason: 'and the next one starts there');
      expect(covered[1].rightExclusive, 10);
    });

    test(
      '🚨a NEGATIVE region reads tile -1, not tile 0 — floorDiv, not `~/`',
      () {
        final covered = tilesCovering(
          surfaceWith([TileCoord(x: -1, y: -1), TileCoord(x: 0, y: 0)]),
          DirtyRegion(left: -2, top: -2, rightExclusive: 2, bottomExclusive: 2),
        ).toList();

        expect(
          covered.map((c) => (c.tile.coord.x, c.tile.coord.y)),
          [(-1, -1), (0, 0)],
          reason:
              'truncation would have mapped pixel -1 to tile 0 and read '
              'the wrong tile at the pasteboard wall',
        );
        expect((covered.first.worldLeft, covered.first.worldTop), (-8, -8));
        expect(covered.first.left, -2);
        expect(covered.first.rightExclusive, 0);
      },
    );

    test('🚨a MISSING tile is skipped, not treated as transparent', () {
      final covered = tilesCovering(
        surfaceWith([TileCoord(x: 1, y: 0)]),
        DirtyRegion(left: 0, top: 0, rightExclusive: 16, bottomExclusive: 4),
      ).toList();

      expect(
        covered.map((c) => c.tile.coord.x),
        [1],
        reason:
            'the surface is sparse — an absent tile has no bytes, and a '
            'caller that did not skip it would read past a buffer that was '
            'never made',
      );
    });

    test('the right/bottom edges are EXCLUSIVE — a region ending on a tile '
        'wall does not reach the next tile', () {
      final covered = tilesCovering(
        surfaceWith([TileCoord(x: 0, y: 0), TileCoord(x: 1, y: 0)]),
        DirtyRegion(left: 0, top: 0, rightExclusive: 8, bottomExclusive: 8),
      ).toList();

      expect(covered.map((c) => c.tile.coord.x), [0]);
    });
  });
}

({double dx, double dy}) _point(double x, double y) => (dx: x, dy: y);

({double dx, double dy}) _apply(Matrix4 matrix, double x, double y) {
  final transformed = matrix.transform3(Vector3(x, y, 0));
  return (dx: _rounded(transformed.x), dy: _rounded(transformed.y));
}

/// Matrix maths carries the usual float dust; these laws are about which
/// mapping, not about the last bit.
double _rounded(double value) => (value * 1e9).roundToDouble() / 1e9;

void _expectMatrix(Matrix4 actual, Matrix4 expected) {
  for (var row = 0; row < 4; row += 1) {
    for (var column = 0; column < 4; column += 1) {
      expect(
        actual.entry(row, column),
        closeTo(expected.entry(row, column), 1e-9),
        reason: 'entry ($row, $column)',
      );
    }
  }
}
