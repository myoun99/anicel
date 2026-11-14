import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/placed_tile.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';

void main() {
  group('materializeBrushDabSequenceOnBitmapSurface', () {
    BitmapSurface surface({
      int width = 4,
      int height = 4,
      Map<TileCoord, BitmapTile> tiles = const {},
    }) {
      return BitmapSurface(
        canvasSize: CanvasSize(width: width, height: height),
        tileSize: 128,
        tiles: tiles,
      );
    }

    PlacedTile blankTile(int x, int y) {
      return (
        coord: TileCoord(x: x, y: y),
        tile: BitmapTile.blank(size: 128),
      );
    }

    int inkedPixels(BitmapSurface surface) {
      var inked = 0;
      for (final tile in surface.tiles.values) {
        for (var y = 0; y < tile.size; y += 1) {
          for (var x = 0; x < tile.size; x += 1) {
            if (readRgbaColorFromBitmapTile(tile: tile, x: x, y: y).a > 0) {
              inked += 1;
            }
          }
        }
      }
      return inked;
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
        // 없음: a pixel landed whole. Under any other step a one-pixel nib is
        // all edge and lays half of it (board
        // a-one-pixel-dab-drops-out-by-where-it-lies Q4) — these pin the blend,
        // not the edge.
        antiAlias: BrushAntiAlias.none,
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
      final original = surface(tiles: {existing.coord: existing.tile});
      final result = materializeBrushDabSequenceOnBitmapSurface(
        surface: original,
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
      );

      expect(result.surface.tileAt(existing.coord), isNot(existing));
      expect(result.dirtyTiles.contains(existing.coord), isTrue);
    });

    test('handles multi-tile dab deterministically', () {
      final original = surface(width: 256, height: 4);
      final result = materializeBrushDabSequenceOnBitmapSurface(
        surface: original,
        sequence: BrushDabSequence([squareDab(centerX: 128, centerY: 1)]),
      );

      expect(result.dirtyTiles.coords.toList(), [
        TileCoord(x: 0, y: 0),
        TileCoord(x: 1, y: 0),
      ]);
    });

    test('paints pasteboard pixels beyond the canvas edge', () {
      // Canvas 1×1 → pasteboard [-1, 2)². A square dab over [-1, 1)²
      // paints all four pasteboard pixels; nothing clips at the canvas.
      final original = surface(width: 1, height: 1);
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
      expect(inkedPixels(result.surface), 4);
    });

    test('ignores pixels outside the pasteboard', () {
      // Canvas 1×1 → 3×3 pasteboard [-1, 2)² (H2, 2026-08-22). A square
      // dab over [-2, 0)² clips to it: only the [-1, 0)² pixel survives.
      final original = surface(width: 1, height: 1);
      final result = materializeBrushDabSequenceOnBitmapSurface(
        surface: original,
        sequence: BrushDabSequence([squareDab(centerX: -1, centerY: -1)]),
      );

      expect(result.dirtyTiles.coords, {TileCoord(x: -1, y: -1)});
      final tile = result.surface.tileAt(TileCoord(x: -1, y: -1))!;
      expect(readRgbaColorFromBitmapTile(tile: tile, x: 127, y: 127).a, 255);
      expect(inkedPixels(result.surface), 1);
    });

    test('stops at the wall of the pasteboard\'s size (I-109)', () {
      // Canvas 4×4 at 1.5x → wall [-1, 5)². A square dab over [-2, 0)²
      // keeps only its [-1, 0)² pixel, as at 3x it kept all four.
      for (final (reach, inked) in [
        (PasteboardReach.whole, 4),
        (PasteboardReach.quarter, 1),
        (PasteboardReach.none, 0),
      ]) {
        final result = materializeBrushDabSequenceOnBitmapSurface(
          surface: BitmapSurface(
            canvasSize: const CanvasSize(width: 4, height: 4),
            pasteboardReach: reach,
            tileSize: 128,
          ),
          sequence: BrushDabSequence([squareDab(centerX: -1, centerY: -1)]),
        );
        expect(inkedPixels(result.surface), inked, reason: '$reach');
        expect(result.surface.pasteboardReach, reach);
      }
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
        // Half on the 16-bit scale is 32767 of 65535, which stores as 127
        // — dab/tests.rs `an_erase_takes_its_alpha_and_keeps_the_colour`.
        // ↩️128 till 2026-11-14, by the Dart tile kernel of a small grid.
        expect(pixel.a, 127);
        expect(pixel.r, 255);
        expect(erased.dirtyTiles.contains(TileCoord(x: 0, y: 0)), isTrue);
      });

      test('full erase zeroes the pixel entirely — and the tile it emptied '
          'is not kept', () {
        final painted = materializeBrushDabSequenceOnBitmapSurface(
          surface: surface(),
          sequence: BrushDabSequence([
            onePixelDab(globalX: 0, globalY: 0),
            // A second pixel in the SAME tile, so the erase below leaves a
            // tile behind to read the colour off. Erasing the only pixel
            // takes the whole tile with it (its own test says so).
            onePixelDab(globalX: 1, globalY: 1, sequence: 1),
          ]),
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
        expect(pixel.r, 0, reason: 'the erase takes the colour bytes too');
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

      // ↩️A mixed sequence was held against the per-pixel CPU reference till
      // 2026-11-14; the engine's own pins hold it now (dab/tests.rs
      // `an_erase_takes_its_alpha_and_keeps_the_colour`,
      // `a_light_press_settles_at_its_opacity`).
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
      final beforePixels = existing.tile.pixels;
      final original = surface(tiles: {existing.coord: existing.tile});

      materializeBrushDabSequenceOnBitmapSurface(
        surface: original,
        sequence: BrushDabSequence([onePixelDab(globalX: 0, globalY: 0)]),
      );

      expect(existing.tile.pixels, beforePixels);
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
