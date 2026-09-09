import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/ui/timeline/instruction_icon_palette.dart';

/// The raster geometry ops and the instruction icon palette — neither
/// named by a test (the audit's untested-file pass, 2026-09-05).
void main() {
  BitmapTile inkedTile(TileCoord coord, {int size = 8, int at = 0}) {
    final pixels = Uint8List(size * size * 4);
    pixels[at * 4 + 0] = 0x11;
    pixels[at * 4 + 1] = 0x22;
    pixels[at * 4 + 2] = 0x33;
    pixels[at * 4 + 3] = 0xFF;
    return BitmapTile(size: size, pixels: pixels);
  }

  BitmapSurface surfaceWith(
    Map<TileCoord, BitmapTile> tiles, {
    int width = 16,
    int height = 16,
  }) => BitmapSurface(
    canvasSize: CanvasSize(width: width, height: height),
    tileSize: 8,
    tiles: tiles,
  );

  group('the content bounds', () {
    test('an EMPTY surface has none', () {
      expect(bitmapSurfaceContentBounds(surfaceWith(const {})), isNull);
    });

    test('a surface whose only tile is transparent has none either — an '
        'allocated tile is not ink', () {
      final coord = TileCoord(x: 0, y: 0);
      expect(
        bitmapSurfaceContentBounds(
          surfaceWith({coord: BitmapTile.blank(size: 8)}),
        ),
        isNull,
      );
    });

    test('one inked pixel bounds itself, right and bottom EXCLUSIVE', () {
      final coord = TileCoord(x: 0, y: 0);
      final bounds = bitmapSurfaceContentBounds(
        surfaceWith({coord: inkedTile(coord, at: 0)}),
      )!;

      expect((bounds.left, bounds.top), (0, 0));
      expect((bounds.rightExclusive, bounds.bottomExclusive), (1, 1));
    });

    test('🚨a pixel on a NEGATIVE tile bounds into pasteboard space — the '
        'artwork off the stage is real artwork', () {
      final coord = TileCoord(x: -1, y: -1);
      final bounds = bitmapSurfaceContentBounds(
        surfaceWith({coord: inkedTile(coord, at: 0)}),
      )!;

      expect((bounds.left, bounds.top), (-8, -8));
    });

    test('two tiles bound the whole span between them', () {
      final near = TileCoord(x: 0, y: 0);
      final far = TileCoord(x: 1, y: 1);
      final bounds = bitmapSurfaceContentBounds(
        surfaceWith({near: inkedTile(near), far: inkedTile(far)}),
      )!;

      expect((bounds.left, bounds.top), (0, 0));
      expect((bounds.rightExclusive, bounds.bottomExclusive), (9, 9));
    });
  });

  group('the canvas resize', () {
    test('the same size is the SAME surface — identity, so nothing '
        'downstream rebuilds what did not change', () {
      final surface = surfaceWith(const {});
      expect(
        identical(
          resizeBitmapSurfaceCanvas(
            surface,
            const CanvasSize(width: 16, height: 16),
          ),
          surface,
        ),
        isTrue,
      );
    });

    test('🚨a resize is TOP-LEFT anchored: an in-bounds tile keeps its '
        'coordinate rather than being re-centred', () {
      final coord = TileCoord(x: 0, y: 0);
      final resized = resizeBitmapSurfaceCanvas(
        surfaceWith({coord: inkedTile(coord)}),
        const CanvasSize(width: 64, height: 64),
      );

      expect(resized.tiles.keys, [coord]);
      expect(resized.canvasSize, const CanvasSize(width: 64, height: 64));
    });

    test('a tile outside the SHRUNKEN pasteboard is dropped', () {
      final far = TileCoord(x: 40, y: 40);
      final resized = resizeBitmapSurfaceCanvas(
        surfaceWith({far: inkedTile(far)}, width: 512, height: 512),
        const CanvasSize(width: 16, height: 16),
      );

      expect(resized.tiles, isEmpty);
    });
  });

  group('the translate', () {
    test('a zero shift is just the resize', () {
      final coord = TileCoord(x: 0, y: 0);
      final surface = surfaceWith({coord: inkedTile(coord)});
      final moved = translateBitmapSurface(
        surface,
        dx: 0,
        dy: 0,
        canvasSize: const CanvasSize(width: 16, height: 16),
      );

      expect(identical(moved, surface), isTrue);
    });

    test('a WHOLE-TILE shift rebases the coordinate and keeps the pixels', () {
      final coord = TileCoord(x: 0, y: 0);
      final moved = translateBitmapSurface(
        surfaceWith({coord: inkedTile(coord)}),
        dx: 8,
        dy: 0,
        canvasSize: const CanvasSize(width: 16, height: 16),
      );

      expect(moved.tiles.keys, [TileCoord(x: 1, y: 0)]);
      final bounds = bitmapSurfaceContentBounds(moved)!;
      expect(bounds.left, 8);
    });

    /// 🚨★★★**THE TWO BRANCHES DISAGREED ABOUT WHAT FALLS OFF.** The
    /// function's own doc says the output is bounded by the TARGET
    /// canvas's pasteboard and that pixels past it clip — and the
    /// fractional branch did exactly that. The whole-tile branch built
    /// its intermediate surface at the SOURCE canvas size instead, so a
    /// rebase that carried a tile past the OLD pasteboard threw an
    /// ArgumentError where its twin, one line down, would have clipped
    /// it. One law now, and this is the case that tells them apart.
    test('🚨a WHOLE-TILE shift CLIPS at the target pasteboard, like the '
        'fractional one — it does not throw', () {
      final coord = TileCoord(x: 0, y: 0);
      final moved = translateBitmapSurface(
        surfaceWith({coord: inkedTile(coord)}),
        // A 16px canvas of 8px tiles: the pasteboard is x ∈ [-2, 4).
        // Four tiles right puts this one at x = 4, one past the wall.
        dx: 32,
        dy: 0,
        canvasSize: const CanvasSize(width: 16, height: 16),
      );

      expect(moved.tiles, isEmpty);
      expect(bitmapSurfaceContentBounds(moved), isNull);
    });

    test('🚨a FRACTIONAL shift moves the ink by exactly that many pixels, '
        'across the tile it lands in', () {
      final coord = TileCoord(x: 0, y: 0);
      final moved = translateBitmapSurface(
        surfaceWith({coord: inkedTile(coord, at: 0)}),
        dx: 3,
        dy: 2,
        canvasSize: const CanvasSize(width: 16, height: 16),
      );

      final bounds = bitmapSurfaceContentBounds(moved)!;
      expect((bounds.left, bounds.top), (3, 2));
    });

    test('fully transparent output tiles are DROPPED — a shifted surface '
        'must not grow a skirt of empty tiles', () {
      final coord = TileCoord(x: 0, y: 0);
      final moved = translateBitmapSurface(
        surfaceWith({coord: inkedTile(coord, at: 0)}),
        dx: 3,
        dy: 2,
        canvasSize: const CanvasSize(width: 16, height: 16),
      );

      expect(moved.tiles, hasLength(1));
    });
  });

  group('the instruction icon palette', () {
    test('🚨an UNKNOWN key falls back to the label glyph — a project file '
        'stays open-able when a key is not one of ours', () {
      expect(instructionIconFor('nothing-like-this'), instructionFallbackIcon);
      expect(instructionIconFor(''), instructionFallbackIcon);
    });

    test('a curated key resolves to its own glyph', () {
      expect(instructionIconFor('pan'), Icons.arrow_right_alt);
      expect(instructionIconFor('fade-in'), Icons.visibility);
    });

    test('the keys are symbolic, not glyph names — the model stores THESE', () {
      expect(instructionIconPalette.keys, contains('track-up'));
      expect(instructionIconPalette.keys, isNot(contains('zoom_in')));
    });

    test('no two keys share a glyph — a palette the user picks from has to '
        'look like a choice', () {
      expect(
        instructionIconPalette.values.toSet(),
        hasLength(instructionIconPalette.length),
      );
    });

    test('the fallback is not IN the palette — it is what a key that is not '
        'there resolves to', () {
      expect(
        instructionIconPalette.values,
        isNot(contains(instructionFallbackIcon)),
      );
    });
  });
}
