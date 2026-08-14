import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/canvas_selection.dart'
    show CanvasSelectionShape;
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/cel_pixel_region.dart';

void main() {
  const canvas = CanvasSize(width: 1024, height: 512);

  BitmapTile blank(TileCoord coord) =>
      BitmapTile.blank(coord: coord, size: 256);

  BitmapSurface surfaceWith(List<TileCoord> coords) => BitmapSurface(
    canvasSize: canvas,
    tiles: {for (final coord in coords) coord: blank(coord)},
  );

  CanvasSelectionRegion rect(double l, double t, double r, double b) =>
      CanvasSelectionRegion.shape(
        CanvasSelectionShape([
          CanvasPoint(x: l, y: t),
          CanvasPoint(x: r, y: t),
          CanvasPoint(x: r, y: b),
          CanvasPoint(x: l, y: b),
        ]),
      );

  /// Everything the walk hands over, in order.
  List<(TileCoord, Uint8List?)> collect(walk) {
    final visited = <(TileCoord, Uint8List?)>[];
    walk((TileCoord coord, Uint8List? mask) {
      // The buffer is reused between tiles, so a test that wants to compare
      // two tiles has to take its own copy.
      visited.add((coord, mask == null ? null : Uint8List.fromList(mask)));
    });
    return visited;
  }

  int maskAt(Uint8List mask, int x, int y) => mask[(y * 256) + x];

  group('celPixelWalkFor', () {
    test('no region walks every allocated tile with no mask', () {
      final surface = surfaceWith([
        TileCoord(x: 0, y: 0),
        TileCoord(x: 1, y: 0),
        TileCoord(x: 3, y: 1),
      ]);

      final visited = collect(celPixelWalkFor(surface: surface));

      expect(visited.length, 3);
      expect(visited.every((entry) => entry.$2 == null), isTrue);
    });

    test('tile order is sorted rather than borrowed from the map', () {
      // Inserted deliberately out of order — a later commit elsewhere can
      // reshuffle the tile map, and a recipe read back in a different
      // order would restore every value to the wrong pixel.
      final surface = surfaceWith([
        TileCoord(x: 2, y: 1),
        TileCoord(x: 0, y: 1),
        TileCoord(x: 1, y: 0),
      ]);

      final visited = collect(celPixelWalkFor(surface: surface));

      expect(visited.map((entry) => (entry.$1.x, entry.$1.y)).toList(), [
        (1, 0),
        (0, 1),
        (2, 1),
      ]);
    });

    test('a region only reaches the tiles it covers', () {
      final surface = surfaceWith([
        TileCoord(x: 0, y: 0),
        TileCoord(x: 1, y: 0),
        TileCoord(x: 2, y: 0),
      ]);

      final visited = collect(
        celPixelWalkFor(surface: surface, region: rect(10, 10, 60, 60)),
      );

      expect(visited.length, 1);
      expect(visited.single.$1, TileCoord(x: 0, y: 0));
    });

    test('a region spanning a tile boundary masks each side', () {
      final surface = surfaceWith([TileCoord(x: 0, y: 0), TileCoord(x: 1, y: 0)]);

      final visited = collect(
        celPixelWalkFor(surface: surface, region: rect(200, 0, 300, 100)),
      );

      expect(visited.length, 2);
      final leftMask = visited[0].$2!;
      final rightMask = visited[1].$2!;
      // Left tile holds global x 200..255 of the run.
      expect(maskAt(leftMask, 199, 50), 0);
      expect(maskAt(leftMask, 220, 50), 255);
      expect(maskAt(leftMask, 255, 50), 255);
      // Right tile starts at global x 256, so its local 0..43 are inside.
      expect(maskAt(rightMask, 0, 50), 255);
      expect(maskAt(rightMask, 43, 50), 255);
      expect(maskAt(rightMask, 60, 50), 0);
      // ...and nothing below the region's bottom edge.
      expect(maskAt(leftMask, 220, 150), 0);
    });

    test('a region off in the pasteboard still reaches its tiles', () {
      final surface = surfaceWith([
        TileCoord(x: -1, y: 0),
        TileCoord(x: 0, y: 0),
      ]);

      final visited = collect(
        celPixelWalkFor(surface: surface, region: rect(-200, 10, -100, 60)),
      );

      expect(visited.length, 1);
      expect(visited.single.$1, TileCoord(x: -1, y: 0));
      // Tile -1 spans global x -256..-1, so global -200 is local 56.
      expect(maskAt(visited.single.$2!, 56, 30), 255);
      expect(maskAt(visited.single.$2!, 10, 30), 0);
    });
  });

  group('regionInArtworkSpace', () {
    final region = rect(100, 100, 200, 200);

    test('an unposed layer gets the region back unchanged', () {
      expect(
        identical(
          regionInArtworkSpace(
            region: region,
            pose: null,
            canvasSize: canvas,
          ),
          region,
        ),
        isTrue,
      );
    });

    test('a moved layer sees the region shifted the other way', () {
      // The pose puts the artwork's anchor (canvas centre) 50px right of
      // where it would sit, so artwork space is the selection shifted 50px
      // LEFT — recolour what the user drew over, not what sits at those
      // artwork coordinates.
      final moved = regionInArtworkSpace(
        region: region,
        pose: CameraPose(
          center: CanvasPoint(x: canvas.width / 2 + 50, y: canvas.height / 2),
        ),
        canvasSize: canvas,
      );

      final points = moved!.steps.single.shape.points;
      expect(points.first.x, closeTo(50, 0.001));
      expect(points.first.y, closeTo(100, 0.001));
    });

    test('the singular-pose guard is a backstop, not a path', () {
      // A pose cannot collapse a layer in the first place, so the null
      // return in regionInArtworkSpace is unreachable through the model.
      // Pinned rather than deleted: if CameraPose ever admits a zero zoom,
      // this is the line that says the guard has become a real path.
      expect(
        () => CameraPose(center: CanvasPoint(x: 0, y: 0), zoom: 0),
        throwsArgumentError,
      );
    });
  });
}
