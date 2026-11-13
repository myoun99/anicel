import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart';

/// R27 #4: the live overlay's PRE-BLEND must be byte-identical to the
/// pen-up commit — for EVERY brush blend mode, erase included. This is the
/// user's rule verbatim: "블렌드모드를 다른걸로 해두더라도 오차가 없어야" — the tile
/// on screen while drawing IS the committed tile, not an approximation
/// of it. Randomized bases (missing / partial tiles) and edge-biased
/// stroke alphas; any single byte of drift fails.
void main() {
  Uint8List randomPixels(Random random, int byteLength) {
    final bytes = Uint8List(byteLength);
    for (var i = 0; i < byteLength; i += 1) {
      final roll = random.nextInt(10);
      bytes[i] = roll == 0
          ? 0
          : roll == 1
          ? 255
          : random.nextInt(256);
    }
    return bytes;
  }

  const tileSize = 32;
  const canvasSize = CanvasSize(width: 96, height: 64);

  BitmapSurface randomSurface(Random random) {
    final tiles = <TileCoord, BitmapTile>{};
    for (var tileY = -1; tileY * tileSize < canvasSize.height; tileY += 1) {
      for (var tileX = -1; tileX * tileSize < canvasSize.width; tileX += 1) {
        if (random.nextInt(3) == 0) {
          continue; // Missing tiles: the transparent-read branches.
        }
        final coord = TileCoord(x: tileX, y: tileY);
        tiles[coord] = BitmapTile(
          size: tileSize,
          pixels: randomPixels(random, tileSize * tileSize * 4),
        );
      }
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: tiles,
    );
  }

  /// Every stroke mode pre-blends now — color included (user rule 07-23:
  /// one display pipeline, live == commit unconditionally).
  const preBlendModes = [
    BrushBlendMode.color,
    BrushBlendMode.erase,
    BrushBlendMode.behind,
    BrushBlendMode.add,
    BrushBlendMode.darken,
    BrushBlendMode.multiply,
    BrushBlendMode.colorBurn,
    BrushBlendMode.lighten,
    BrushBlendMode.screen,
    BrushBlendMode.colorDodge,
    BrushBlendMode.overlay,
    BrushBlendMode.softLight,
    BrushBlendMode.hardLight,
    BrushBlendMode.difference,
    BrushBlendMode.exclusion,
  ];

  void runAllModes({required int seed}) {
    final random = Random(seed);
    for (final mode in preBlendModes) {
      final surface = randomSurface(random);
      // A stroke region straddling tile boundaries and the canvas edge.
      final bounds = DirtyRegion(
        left: 7,
        top: 5,
        rightExclusive: 71,
        bottomExclusive: 53,
      );
      final width = bounds.rightExclusive - bounds.left;
      final height = bounds.bottomExclusive - bounds.top;
      final stroke = randomPixels(random, width * height * 4);

      // What the pen-up will land: the REAL commit.
      final committed = compositeStrokePixelsOntoBitmapSurface(
        surface: surface,
        strokePixels: stroke,
        bounds: bounds,
        erase: mode == BrushBlendMode.erase,
        blendMode: mode,
      );
      final expected = bitmapSurfaceRegionPixels(committed.surface, bounds);

      // What the overlay shows while drawing.
      final live = preBlendStrokeOverlayPixels(
        dst: bitmapSurfaceRegionPixels(surface, bounds),
        src: stroke,
        mode: mode,
        erase: mode == BrushBlendMode.erase,
        pixelCount: width * height,
      );

      expect(
        live,
        expected,
        reason:
            '${mode.name}: the live overlay must be byte-identical to the '
            'commit',
      );
    }
  }

  /// R28: a mask must mean the same thing wherever a stroke is scaled by
  /// it — the rasterizer scales the stroke's alpha by its tile's mask, and
  /// that has to agree byte for byte with the blend the commit runs, or the
  /// live display and the commit would drift. Off the engine's grid the
  /// mask is the opacity ceiling's; ↩️it was a selection's till 2026-11-14
  /// (`cutOnTheEngineOnly`).
  test(
    'MASKED pre-blend: a tile of the rasterizer == the stroke blend by '
    'hand, mask included — every mode, byte for byte',
    () {
      const liveTile = 64;
      const bigCanvas = CanvasSize(width: 128, height: 128);
      final random = Random(90731);
      // A base on the SAME grid: the aligned case, and the one production
      // always runs.
      final baseTiles = <TileCoord, BitmapTile>{};
      for (var tileY = 0; tileY < 2; tileY += 1) {
        for (var tileX = 0; tileX < 2; tileX += 1) {
          final coord = TileCoord(x: tileX, y: tileY);
          baseTiles[coord] = BitmapTile(
            size: liveTile,
            pixels: randomPixels(random, liveTile * liveTile * 4),
          );
        }
      }
      final base = BitmapSurface(
        canvasSize: bigCanvas,
        tileSize: liveTile,
        tiles: baseTiles,
      );
      // A ceiling neither whole nor nothing (both of which take shortcuts).
      const ceiling = 0.6;
      final maskBytes = strokeCoverageMask(
        pixelCount: liveTile * liveTile,
        opacity: ceiling,
      )!;

      int mul255Round(int value, int alpha) {
        final product = value * alpha + 128;
        return (product + (product >> 8)) >> 8;
      }

      for (final mode in preBlendModes) {
        final rasterizer = BrushLiveStrokeRasterizer(
          pasteboard: bigCanvas.pasteboardAt(PasteboardReach.whole),
          tileSize: liveTile,
        )..strokeOpacity = ceiling;
        rasterizer.blendFrom([
          BrushDab(
            center: CanvasPoint(x: 32, y: 32),
            color: 0x90C04010,
            size: 60,
            opacity: 0.7,
            flow: 0.8,
            hardness: 0.4,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: 0,
          ),
        ], from: 0);

        final blended = rasterizer.preBlendedOverlayTile(
          tileX: 0,
          tileY: 0,
          base: base,
          mode: mode,
          erase: mode == BrushBlendMode.erase,
        );
        expect(blended, isNotNull, reason: '${mode.name}: a masked result');

        // The blend by hand on the same inputs, mask included.
        final stroke = Uint8List(liveTile * liveTile * 4);
        for (var y = 0; y < liveTile; y += 1) {
          rasterizer.copyRow(0, y, liveTile, stroke, y * liveTile * 4);
        }
        final straight = preBlendStrokeOverlayPixels(
          dst: bitmapSurfaceRegionPixels(
            base,
            DirtyRegion(
              left: 0,
              top: 0,
              rightExclusive: liveTile,
              bottomExclusive: liveTile,
            ),
          ),
          src: stroke,
          mode: mode,
          erase: mode == BrushBlendMode.erase,
          pixelCount: liveTile * liveTile,
          mask: maskBytes,
        );
        final expected = Uint8List(straight.length);
        for (var o = 0; o < straight.length; o += 4) {
          final alpha = straight[o + 3];
          if (alpha == 0) {
            continue;
          }
          if (alpha == 255) {
            expected[o] = straight[o];
            expected[o + 1] = straight[o + 1];
            expected[o + 2] = straight[o + 2];
            expected[o + 3] = 255;
            continue;
          }
          expected[o] = mul255Round(straight[o], alpha);
          expected[o + 1] = mul255Round(straight[o + 1], alpha);
          expected[o + 2] = mul255Round(straight[o + 2], alpha);
          expected[o + 3] = alpha;
        }

        expect(
          blended!.readPremultiplied(Uint8List.fromList),
          expected,
          reason: '${mode.name}: the masked tile == the masked blend by hand',
        );
        rasterizer.clear();
      }
    },
  );

  test('live pre-blend == the commit, every mode, byte for byte', () {
    runAllModes(seed: 20260723);
  });

  test(
    'a tile of the rasterizer over a base on ANOTHER grid == the stroke '
    'blend by hand, premultiplied — every mode, byte for byte',
    () {
      const liveTile = 64;
      const bigCanvas = CanvasSize(width: 256, height: 256);
      final random = Random(451);
      // Base on a DIFFERENT grid (32) than the stroke tiles (64): the
      // base-rect copy walks multiple base tiles per overlay tile.
      final baseTiles = <TileCoord, BitmapTile>{};
      for (var tileY = 0; tileY < 2; tileY += 1) {
        for (var tileX = 0; tileX < 2; tileX += 1) {
          final coord = TileCoord(x: tileX, y: tileY);
          baseTiles[coord] = BitmapTile(
            size: 32,
            pixels: randomPixels(random, 32 * 32 * 4),
          );
        }
      }
      final base = BitmapSurface(
        canvasSize: bigCanvas,
        tileSize: 32,
        tiles: baseTiles,
      );

      int mul255Round(int value, int alpha) {
        final product = value * alpha + 128;
        return (product + (product >> 8)) >> 8;
      }

      for (final mode in preBlendModes) {
        final rasterizer = BrushLiveStrokeRasterizer(
          pasteboard: bigCanvas.pasteboardAt(PasteboardReach.whole),
          tileSize: liveTile,
        );
        rasterizer.blendFrom([
          BrushDab(
            center: CanvasPoint(x: 64, y: 64),
            color: 0x90C04010,
            size: 60,
            opacity: 0.7,
            flow: 0.8,
            hardness: 0.4,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: 0,
          ),
        ], from: 0);

        final blended = rasterizer.preBlendedOverlayTile(
          tileX: 0,
          tileY: 0,
          base: base,
          mode: mode,
          erase: mode == BrushBlendMode.erase,
        );
        expect(blended, isNotNull, reason: '${mode.name}: a result');

        // The blend by hand on the same inputs.
        final stroke = Uint8List(liveTile * liveTile * 4);
        for (var y = 0; y < liveTile; y += 1) {
          rasterizer.copyRow(0, y, liveTile, stroke, y * liveTile * 4);
        }
        final straight = preBlendStrokeOverlayPixels(
          dst: bitmapSurfaceRegionPixels(
            base,
            DirtyRegion(
              left: 0,
              top: 0,
              rightExclusive: liveTile,
              bottomExclusive: liveTile,
            ),
          ),
          src: stroke,
          mode: mode,
          erase: mode == BrushBlendMode.erase,
          pixelCount: liveTile * liveTile,
        );
        final expected = Uint8List(straight.length);
        for (var o = 0; o < straight.length; o += 4) {
          final alpha = straight[o + 3];
          if (alpha == 0) {
            continue;
          }
          if (alpha == 255) {
            expected[o] = straight[o];
            expected[o + 1] = straight[o + 1];
            expected[o + 2] = straight[o + 2];
            expected[o + 3] = 255;
            continue;
          }
          expected[o] = mul255Round(straight[o], alpha);
          expected[o + 1] = mul255Round(straight[o + 1], alpha);
          expected[o + 2] = mul255Round(straight[o + 2], alpha);
          expected[o + 3] = alpha;
        }

        expect(
          blended!.readPremultiplied(Uint8List.fromList),
          expected,
          reason: '${mode.name}: the tile == the blend by hand',
        );
        rasterizer.clear();
      }
    },
  );
}
