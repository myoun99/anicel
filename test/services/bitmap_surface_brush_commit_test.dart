import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/bitmap_tile_operation_apply.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_dab_sequence_blend.dart';

void main() {
  group('materializeBrushDabSequenceOnBitmapSurface', () {
    BitmapSurface surface({
      int width = 4,
      int height = 4,
      int tileSize = 2,
      Map<TileCoord, BitmapTile> tiles = const {},
    }) {
      return BitmapSurface(
        canvasSize: CanvasSize(width: width, height: height),
        tileSize: tileSize,
        tiles: tiles,
      );
    }

    BitmapTile blankTile(int x, int y, {int size = 2}) {
      return BitmapTile.blank(
        coord: TileCoord(x: x, y: y),
        size: size,
      );
    }

    BrushDab onePixelDab({
      required double globalX,
      required double globalY,
      int color = 0xFFFF0000,
      double opacity = 1,
      double flow = 1,
      int sequence = 0,
    }) {
      return BrushDab(
        center: CanvasPoint(x: globalX + 0.5, y: globalY + 0.5),
        color: color,
        size: 1,
        opacity: opacity,
        flow: flow,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: sequence,
      );
    }

    BrushDab squareDab({required double centerX, required double centerY}) {
      return BrushDab(
        center: CanvasPoint(x: centerX, y: centerY),
        color: 0xFFFF0000,
        size: 2,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.square,
        pressure: 1,
        sequence: 0,
      );
    }

    test('returns no changes for empty sequence', () {
      final original = surface();
      final result = materializeBrushDabSequenceOnBitmapSurface(
        surface: original,
        sequence: BrushDabSequence(),
      );

      expect(result.surface, original);
      expect(result.dirtyTiles.isEmpty, isTrue);
      expect(result.hasChanges, isFalse);
    });

    test('returns no changes for non-effective dab', () {
      final original = surface();
      final result = materializeBrushDabSequenceOnBitmapSurface(
        surface: original,
        sequence: BrushDabSequence([
          onePixelDab(globalX: 0, globalY: 0, opacity: 0),
        ]),
      );

      expect(result.surface, original);
      expect(result.dirtyTiles.isEmpty, isTrue);
    });

    test('returns updated surface and dirtyTiles for dab on missing tile', () {
      final original = surface();
      final result = materializeBrushDabSequenceOnBitmapSurface(
        surface: original,
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
      );

      final coord = TileCoord(x: 0, y: 0);
      expect(result.surface.tileAt(coord), isNotNull);
      expect(result.dirtyTiles.contains(coord), isTrue);
      expect(
        readRgbaColorFromBitmapTile(
          tile: result.surface.tileAt(coord)!,
          x: 0,
          y: 0,
        ).a,
        255,
      );
    });

    test('returns updated surface and dirtyTiles for dab on existing tile', () {
      final existing = blankTile(0, 0);
      final original = surface(tiles: {existing.coord: existing});
      final result = materializeBrushDabSequenceOnBitmapSurface(
        surface: original,
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
      );

      expect(result.surface.tileAt(existing.coord), isNot(existing));
      expect(result.dirtyTiles.contains(existing.coord), isTrue);
    });

    test('handles multi-tile dab deterministically', () {
      final original = surface(width: 4, height: 4, tileSize: 2);
      final result = materializeBrushDabSequenceOnBitmapSurface(
        surface: original,
        sequence: BrushDabSequence([squareDab(centerX: 2, centerY: 1)]),
      );

      expect(result.dirtyTiles.coords.toList(), [
        TileCoord(x: 0, y: 0),
        TileCoord(x: 1, y: 0),
      ]);
    });

    test('paints pasteboard pixels beyond the canvas edge', () {
      // Canvas 1×1 → pasteboard [-1, 2)². A square dab over [-1, 1)²
      // paints all four pasteboard pixels; nothing clips at the canvas.
      final original = surface(width: 1, height: 1, tileSize: 1);
      final result = materializeBrushDabSequenceOnBitmapSurface(
        surface: original,
        sequence: BrushDabSequence([squareDab(centerX: 0, centerY: 0)]),
      );

      expect(result.dirtyTiles.coords, {
        TileCoord(x: -1, y: -1),
        TileCoord(x: 0, y: -1),
        TileCoord(x: -1, y: 0),
        TileCoord(x: 0, y: 0),
      });
      expect(result.surface.tiles.length, 4);
    });

    test('ignores pixels outside the pasteboard', () {
      // Canvas 1×1 → 3×3 pasteboard [-1, 2)² (H2, 2026-08-22). A square
      // dab over [-2, 0)² clips to it: only the [-1, 0)² pixel survives.
      final original = surface(width: 1, height: 1, tileSize: 1);
      final result = materializeBrushDabSequenceOnBitmapSurface(
        surface: original,
        sequence: BrushDabSequence([squareDab(centerX: -1, centerY: -1)]),
      );

      expect(result.dirtyTiles.coords, {TileCoord(x: -1, y: -1)});
      expect(result.surface.tiles.length, 1);
    });

    group('erase dabs', () {
      BrushDab eraseDab({
        required double globalX,
        required double globalY,
        double opacity = 1,
        int sequence = 0,
      }) {
        return onePixelDab(
          globalX: globalX,
          globalY: globalY,
          opacity: opacity,
          sequence: sequence,
        ).copyWith(erase: true);
      }

      test('partial erase halves alpha and keeps the color', () {
        final painted = materializeBrushDabSequenceOnBitmapSurface(
          surface: surface(),
          sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
        ).surface;

        final erased = materializeBrushDabSequenceOnBitmapSurface(
          surface: painted,
          sequence: BrushDabSequence([
            eraseDab(globalX: 0, globalY: 0, opacity: 0.5),
          ]),
        );

        final pixel = readRgbaColorFromBitmapTile(
          tile: erased.surface.tileAt(TileCoord(x: 0, y: 0))!,
          x: 0,
          y: 0,
        );
        expect(pixel.a, 128);
        expect(pixel.r, 255);
        expect(erased.dirtyTiles.contains(TileCoord(x: 0, y: 0)), isTrue);
      });

      test('full erase zeroes the pixel entirely', () {
        final painted = materializeBrushDabSequenceOnBitmapSurface(
          surface: surface(),
          sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
        ).surface;

        final erased = materializeBrushDabSequenceOnBitmapSurface(
          surface: painted,
          sequence: BrushDabSequence([eraseDab(globalX: 0, globalY: 0)]),
        );

        final pixel = readRgbaColorFromBitmapTile(
          tile: erased.surface.tileAt(TileCoord(x: 0, y: 0))!,
          x: 0,
          y: 0,
        );
        expect(pixel.a, 0);
        expect(pixel.r, 0);
      });

      test('erasing empty canvas changes nothing', () {
        final original = surface();
        final result = materializeBrushDabSequenceOnBitmapSurface(
          surface: original,
          sequence: BrushDabSequence([eraseDab(globalX: 0, globalY: 0)]),
        );

        expect(result.hasChanges, isFalse);
        expect(result.surface, original);
      });

      test('hot path matches the per-pixel oracle for mixed sequences', () {
        final sequence = BrushDabSequence([
          onePixelDab(globalX: 0, globalY: 0),
          onePixelDab(globalX: 1, globalY: 0, opacity: 0.6, sequence: 1),
          eraseDab(globalX: 0, globalY: 0, opacity: 0.4, sequence: 2),
          eraseDab(globalX: 1, globalY: 0, sequence: 3),
        ]);

        final hot = materializeBrushDabSequenceOnBitmapSurface(
          surface: surface(),
          sequence: sequence,
        ).surface;

        var oracleTile = blankTile(0, 0);
        final operations = brushPixelBlendOperationsForDabSequence(
          sequence: sequence,
          destinationAt: (x, y) => RgbaColor(r: 0, g: 0, b: 0, a: 0),
        );
        oracleTile = applyBrushPixelBlendOperationsToBitmapTile(
          tile: oracleTile,
          operations: operations,
        );

        expect(hot.tileAt(TileCoord(x: 0, y: 0))!.pixels, oracleTile.pixels);
      });
    });

    test('does not mutate original BitmapSurface', () {
      final original = surface();
      materializeBrushDabSequenceOnBitmapSurface(
        surface: original,
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
      );

      expect(original.tiles, isEmpty);
    });

    test('does not mutate existing BitmapTile', () {
      final existing = blankTile(0, 0);
      final beforePixels = existing.pixels;
      final original = surface(tiles: {existing.coord: existing});

      materializeBrushDabSequenceOnBitmapSurface(
        surface: original,
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
      );

      expect(existing.pixels, beforePixels);
    });

    test('does not mutate BrushDabSequence or BrushDab', () {
      final dab = onePixelDab(globalX: 0, globalY: 0);
      final sequence = BrushDabSequence([dab]);
      final before = BrushDabSequence.fromJson(sequence.toJson());

      materializeBrushDabSequenceOnBitmapSurface(
        surface: surface(),
        sequence: sequence,
      );

      expect(sequence, before);
      expect(sequence.dabs.single, dab);
    });
  });
}
