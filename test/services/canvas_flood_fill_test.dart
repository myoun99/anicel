import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_selection.dart';

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  /// A white 8×8 RGB raster with [black] pixels inked.
  Uint8List rasterWithInk(Set<(int, int)> black) {
    final rgb = Uint8List(8 * 8 * 4);
    rgb.fillRange(0, rgb.length, 255);
    for (final (x, y) in black) {
      final base = (y * 8 + x) * 4;
      rgb[base] = 0;
      rgb[base + 1] = 0;
      rgb[base + 2] = 0;
    }
    return rgb;
  }

  /// A closed box outline (2,2)..(5,5) — interior = (3..4, 3..4).
  Set<(int, int)> boxOutline() => {
    for (var x = 2; x <= 5; x += 1) ...{(x, 2), (x, 5)},
    for (var y = 3; y <= 4; y += 1) ...{(2, y), (5, y)},
  };

  int maskAt(FloodFillRegion region, int x, int y) =>
      region.mask[(y - region.top) * region.width + (x - region.left)];

  group('floodFillRegion', () {
    test('fills the enclosed interior and stops at the ink', () {
      final region = floodFillRegion(
        rgb: rasterWithInk(boxOutline()),
        width: 8,
        height: 8,
        seedX: 3,
        seedY: 3,
        options: const FloodFillOptions(expandPx: 0, antiAlias: false),
      )!;

      expect(
        (region.left, region.top, region.width, region.height),
        (3, 3, 2, 2),
      );
      expect(region.mask, everyElement(255));
    });

    test('tolerance gates which neighbors join the region', () {
      // A near-white pixel 40/channel away from the white seed.
      final rgb = rasterWithInk(const {});
      final base = (3 * 8 + 4) * 4;
      rgb[base] = 215;
      rgb[base + 1] = 215;
      rgb[base + 2] = 215;

      FloodFillRegion fill(int tolerance) => floodFillRegion(
        rgb: rgb,
        width: 8,
        height: 8,
        seedX: 3,
        seedY: 3,
        options: FloodFillOptions(
          tolerance: tolerance,
          expandPx: 0,
          antiAlias: false,
        ),
      )!;

      expect(maskAt(fill(32), 4, 3), 0);
      expect(maskAt(fill(64), 4, 3), 255);
    });

    test('expand grows one pixel under the ink line', () {
      final region = floodFillRegion(
        rgb: rasterWithInk(boxOutline()),
        width: 8,
        height: 8,
        seedX: 3,
        seedY: 3,
        options: const FloodFillOptions(expandPx: 1, antiAlias: false),
      )!;

      expect(
        (region.left, region.top, region.width, region.height),
        (2, 2, 4, 4),
      );
      // 4-neighbor growth: the edge midpoints join, the corners do not.
      expect(maskAt(region, 3, 2), 255);
      expect(maskAt(region, 2, 3), 255);
      expect(maskAt(region, 2, 2), 0);
    });

    test('anti-alias softens the mask edge only', () {
      final region = floodFillRegion(
        rgb: rasterWithInk(boxOutline()),
        width: 8,
        height: 8,
        seedX: 3,
        seedY: 3,
        options: const FloodFillOptions(expandPx: 0, antiAlias: true),
      )!;

      for (final value in region.mask) {
        expect(value, greaterThan(0));
        expect(value, lessThan(256));
      }
      // Every pixel of the 2×2 region borders the outside → all softened.
      expect(region.mask, everyElement(lessThan(255)));
    });

    test('an out-of-bounds seed fills nothing', () {
      expect(
        floodFillRegion(
          rgb: rasterWithInk(const {}),
          width: 8,
          height: 8,
          seedX: 8,
          seedY: 0,
        ),
        isNull,
      );
    });
  });

  group('buildFillDab', () {
    Frame frame(String id) =>
        Frame(id: FrameId(id), duration: 1, strokes: const []);

    Layer inkLayer() => Layer(
      id: const LayerId('ink'),
      name: 'Ink',
      frames: [frame('ink-frame')],
      timeline: {
        0: TimelineExposure.drawing(const FrameId('ink-frame'), length: 1),
      },
    );

    Cut cutWith(List<Layer> layers) => Cut(
      id: const CutId('cut'),
      name: 'Cut',
      layers: layers,
      duration: 24,
      canvasSize: canvasSize,
    );

    /// The box outline as an actual surface (opaque black RGBA).
    BitmapSurface outlineSurface() {
      final tiles = <TileCoord, Uint8List>{};
      for (final (x, y) in boxOutline()) {
        final coord = TileCoord(x: x ~/ 4, y: y ~/ 4);
        final buffer = tiles.putIfAbsent(coord, () => Uint8List(4 * 4 * 4));
        final index = ((y % 4) * 4 + (x % 4)) * 4;
        buffer[index + 3] = 255;
      }
      return BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 4,
        tiles: {
          for (final entry in tiles.entries)
            entry.key: BitmapTile(
              coord: entry.key,
              size: 4,
              pixels: entry.value,
            ),
        },
      );
    }

    test('wraps the region as one COLOR STAMP dab centered on it (R15-⑥: '
        'exact bytes, no tip-mask resampling)', () {
      final surface = outlineSurface();
      final dab = buildFillDab(
        cut: cutWith([inkLayer()]),
        frameIndex: 0,
        surfaceResolver: (_, _) => surface,
        point: CanvasPoint(x: 3, y: 3),
        color: 0xFF3366CC,
        options: const FloodFillOptions(expandPx: 0, antiAlias: false),
      )!;

      expect(dab.size, 2);
      expect(dab.center, CanvasPoint(x: 4, y: 4));
      expect(dab.color, 0xFF3366CC);
      expect(dab.opacity, 1);
      final stamp = dab.stamp!;
      expect((stamp.width, stamp.height), (2, 2));
      for (var index = 0; index < 4; index += 1) {
        expect(
          stamp.rgba.sublist(index * 4, index * 4 + 4),
          [0x33, 0x66, 0xCC, 255],
          reason: 'fill color at full mask coverage, byte-exact',
        );
      }
    });

    test('a seed off the canvas fills nothing', () {
      expect(
        buildFillDab(
          cut: cutWith([]),
          frameIndex: 0,
          surfaceResolver: (_, _) => null,
          point: CanvasPoint(x: -1, y: 0),
          color: 0xFF000000,
        ),
        isNull,
      );
    });

    test('REFERENCE layers gate the fill source (R20-C2): a flagged line '
        'layer wins over paint layers; no flag = fill what you see', () {
      // A paint layer whose opaque blob covers the whole canvas — without
      // the reference filter it becomes the seed color and the barrier
      // box on the ink layer is invisible to the fill.
      final blobTiles = <TileCoord, BitmapTile>{};
      for (var ty = 0; ty < 2; ty += 1) {
        for (var tx = 0; tx < 2; tx += 1) {
          final pixels = Uint8List(4 * 4 * 4);
          for (var i = 0; i < pixels.length; i += 4) {
            pixels[i] = 200; // opaque red-ish everywhere
            pixels[i + 3] = 255;
          }
          blobTiles[TileCoord(x: tx, y: ty)] = BitmapTile(
            coord: TileCoord(x: tx, y: ty),
            size: 4,
            pixels: pixels,
          );
        }
      }
      final blobSurface = BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 4,
        tiles: blobTiles,
      );
      final inkSurface = outlineSurface();
      final paintLayer = Layer(
        id: const LayerId('paint'),
        name: 'Paint',
        frames: [frame('paint-frame')],
        timeline: {
          0: TimelineExposure.drawing(const FrameId('paint-frame'), length: 1),
        },
      );
      BitmapSurface? resolve(Layer layer, Frame _) =>
          layer.id == const LayerId('ink') ? inkSurface : blobSurface;

      // No reference flag: the blob hides the box → the fill floods the
      // whole canvas (fill what you see).
      final unflagged = buildFillDab(
        cut: cutWith([inkLayer(), paintLayer]),
        frameIndex: 0,
        surfaceResolver: resolve,
        point: CanvasPoint(x: 3, y: 3),
        color: 0xFF3366CC,
        options: const FloodFillOptions(expandPx: 0, antiAlias: false),
      )!;
      expect(unflagged.stamp!.width, 8, reason: 'blob = one flat region');

      // Ink flagged as fill reference: the fill reads ONLY the ink layer
      // — the box contains it exactly like the single-layer case.
      final flagged = buildFillDab(
        cut: cutWith([inkLayer().copyWith(isFillReference: true), paintLayer]),
        frameIndex: 0,
        surfaceResolver: resolve,
        point: CanvasPoint(x: 3, y: 3),
        color: 0xFF3366CC,
        options: const FloodFillOptions(expandPx: 0, antiAlias: false),
      )!;
      expect((flagged.stamp!.width, flagged.stamp!.height), (2, 2));

      // The flag itself persists through the layer's JSON.
      final reopened = Layer.fromJson(
        inkLayer().copyWith(isFillReference: true).toJson(),
      );
      expect(reopened.isFillReference, isTrue);
      expect(Layer.fromJson(inkLayer().toJson()).isFillReference, isFalse);
    });

    group('Fill Beyond Canvas (pasteboard)', () {
      /// An outline surface whose ink may sit at NEGATIVE world coords.
      BitmapSurface outlineSurfaceAt(Set<(int, int)> ink) {
        final tiles = <TileCoord, Uint8List>{};
        for (final (x, y) in ink) {
          final coord = TileCoord.fromPixel(pixelX: x, pixelY: y, tileSize: 4);
          final buffer = tiles.putIfAbsent(coord, () => Uint8List(4 * 4 * 4));
          final index = ((y % 4) * 4 + (x % 4)) * 4;
          buffer[index + 3] = 255;
        }
        return BitmapSurface(
          canvasSize: canvasSize,
          tileSize: 4,
          tiles: {
            for (final entry in tiles.entries)
              entry.key: BitmapTile(
                coord: entry.key,
                size: 4,
                pixels: entry.value,
              ),
          },
        );
      }

      /// A closed box from (-3,2) to (4,5): walls cross the canvas's left
      /// edge; interior = x in [-2, 3], y in [3, 4].
      Set<(int, int)> boxAcrossLeftEdge() => {
        for (var x = -3; x <= 4; x += 1) ...{(x, 2), (x, 5)},
        for (var y = 3; y <= 4; y += 1) ...{(-3, y), (4, y)},
      };

      test('a closed region crossing the canvas edge fills whole, off-canvas '
          'pixels included', () {
        final surface = outlineSurfaceAt(boxAcrossLeftEdge());
        final dab = buildFillDab(
          cut: cutWith([inkLayer()]),
          frameIndex: 0,
          surfaceResolver: (_, _) => surface,
          point: CanvasPoint(x: 0, y: 3),
          color: 0xFF3366CC,
          options: const FloodFillOptions(
            expandPx: 0,
            antiAlias: false,
            extendBeyondCanvas: true,
          ),
        )!;

        // Interior 6×2 at world (-2, 3) → center (1, 4).
        final stamp = dab.stamp!;
        expect((stamp.width, stamp.height), (6, 2));
        expect(dab.center, CanvasPoint(x: 1, y: 4));
        expect(dab.size, 6);
      });

      test('the same region WITHOUT the option clips at the canvas edge '
          '(default boundary unchanged)', () {
        final surface = outlineSurfaceAt(boxAcrossLeftEdge());
        final dab = buildFillDab(
          cut: cutWith([inkLayer()]),
          frameIndex: 0,
          surfaceResolver: (_, _) => surface,
          point: CanvasPoint(x: 0, y: 3),
          color: 0xFF3366CC,
          options: const FloodFillOptions(expandPx: 0, antiAlias: false),
        )!;

        // Canvas boundary is the wall: interior x in [0, 3] only.
        expect((dab.stamp!.width, dab.stamp!.height), (4, 2));
        expect(dab.center, CanvasPoint(x: 2, y: 4));
      });

      test('an OPEN region refuses to fill and reports the leak', () {
        var leaked = false;
        final dab = buildFillDab(
          cut: cutWith([inkLayer()]),
          frameIndex: 0,
          surfaceResolver: (_, _) => outlineSurfaceAt(const {}),
          point: CanvasPoint(x: 3, y: 3),
          color: 0xFF3366CC,
          options: const FloodFillOptions(
            expandPx: 0,
            antiAlias: false,
            extendBeyondCanvas: true,
          ),
          onOpenRegion: () => leaked = true,
        );

        expect(dab, isNull);
        expect(leaked, isTrue);
      });

      test('the same open tap WITHOUT the option floods to the canvas wall '
          'as before', () {
        final dab = buildFillDab(
          cut: cutWith([inkLayer()]),
          frameIndex: 0,
          surfaceResolver: (_, _) => outlineSurfaceAt(const {}),
          point: CanvasPoint(x: 3, y: 3),
          color: 0xFF3366CC,
          options: const FloodFillOptions(expandPx: 0, antiAlias: false),
        )!;

        expect((dab.stamp!.width, dab.stamp!.height), (8, 8));
      });
    });

    test(
      'committed through the stroke funnel the mask lands 1:1 unattenuated',
      () {
        // The parity pin: hardness=1, opacity/flow=1 and dab size = mask
        // size must reproduce the region EXACTLY on the committed surface —
        // no falloff, no resampling drift.
        final surface = outlineSurface();
        final dab = buildFillDab(
          cut: cutWith([inkLayer()]),
          frameIndex: 0,
          surfaceResolver: (_, _) => surface,
          point: CanvasPoint(x: 3, y: 3),
          color: 0xFF3366CC,
          options: const FloodFillOptions(expandPx: 0, antiAlias: false),
        )!;

        final coordinator = BrushFrameEditingCoordinator(
          initialFrameKey: BrushFrameKey(
            projectId: const ProjectId('project'),
            trackId: const TrackId('track'),
            cutId: const CutId('cut'),
            layerId: const LayerId('fill'),
            frameId: const FrameId('fill-frame'),
          ),
          frameStore: BrushFrameStore(),
          sessionStore: BrushFrameEditSessionStore(
            canvasSize: canvasSize,
            tileSize: 4,
          ),
          historyPolicy: const BrushHistoryPolicy(
            userUndoLimit: 8,
            deferredBakeRatio: 0,
          ),
        );
        coordinator.commitSourceStroke(sourceDabs: [dab]);

        final committed = coordinator.frameStore.bakedSurfaceOrNull(
          coordinator.activeFrameKey,
        )!;

        for (var y = 0; y < 8; y += 1) {
          for (var x = 0; x < 8; x += 1) {
            final inside = x >= 3 && x <= 4 && y >= 3 && y <= 4;
            expect(
              surfacePixelRgba(committed, x, y),
              inside ? 0x3366CCFF : 0,
              reason: 'pixel ($x, $y)',
            );
          }
        }
      },
    );
  });

  group('buildShapeFillDab', () {
    int alphaAt(BrushDab dab, int x, int y) {
      final stamp = dab.stamp!;
      final left = (dab.center.x - stamp.width / 2).round();
      final top = (dab.center.y - stamp.height / 2).round();
      final lx = x - left;
      final ly = y - top;
      if (lx < 0 || ly < 0 || lx >= stamp.width || ly >= stamp.height) {
        return 0;
      }
      return stamp.rgba[(ly * stamp.width + lx) * 4 + 3];
    }

    test('fills the outline with the colour, corners and all', () {
      // 유저 확정: 올가미 채우기는 A — 내부에 뭐가 있든 채운다. There is no
      // picture in this test at all, which is the point: a shape fill has
      // no seed, no tolerance and nothing to read.
      final dab = buildShapeFillDab(
        shape: CanvasSelectionShape.rect(
          left: 10,
          top: 10,
          right: 40,
          bottom: 30,
        ),
        color: 0xFF3366CC,
        options: const FloodFillOptions(expandPx: 0, antiAlias: false),
      )!;
      expect(alphaAt(dab, 25, 20), 255, reason: 'the middle');
      expect(alphaAt(dab, 11, 11), 255, reason: 'a corner is inside a box');
      expect(alphaAt(dab, 5, 20), 0, reason: 'outside stays out');
      final stamp = dab.stamp!;
      expect(stamp.rgba[3 * 4 + 0], anyOf(0, 0x33));
      expect(dab.color, 0xFF3366CC);
    });

    // TP1: 유저 — "필 툴도 불투명도 설정하면 그거대로 채워지게".
    test('the fill carries an opacity, and defaults to full', () {
      // The coverage MASK is untouched by opacity — a half-opaque fill is
      // still the same shape. What carries it is the dab, because the
      // stroke funnel multiplies a stamp dab by `BrushDab.opacity`; that
      // multiply is why the cut stamp had to hard-code 1 before every tool
      // had a field of its own.
      final shape = CanvasSelectionShape.rect(
        left: 0,
        top: 0,
        right: 10,
        bottom: 10,
      );
      const options = FloodFillOptions(expandPx: 0, antiAlias: false);
      final full = buildShapeFillDab(
        shape: shape,
        color: 0xFF000000,
        options: options,
      )!;
      expect(full.opacity, 1.0, reason: 'unasked is unchanged');

      final half = buildShapeFillDab(
        shape: shape,
        color: 0xFF000000,
        opacity: 0.5,
        options: options,
      )!;
      expect(half.opacity, 0.5);
      expect(
        alphaAt(half, 5, 5),
        alphaAt(full, 5, 5),
        reason: 'the mask is the shape, not the strength',
      );
    });

    test('the ellipse loses the box corners it was drawn in', () {
      final dab = buildShapeFillDab(
        shape: CanvasSelectionShape.ellipse(
          left: 0,
          top: 0,
          right: 60,
          bottom: 60,
        ),
        color: 0xFF000000,
        options: const FloodFillOptions(expandPx: 0, antiAlias: false),
      )!;
      expect(alphaAt(dab, 30, 30), 255);
      expect(alphaAt(dab, 2, 2), 0);
    });

    test('an outline enclosing nothing fills nothing', () {
      // Three collinear points have no area — the same rule that makes a
      // lasso dragged in a straight line cut nothing.
      final dab = buildShapeFillDab(
        shape: CanvasSelectionShape([
          CanvasPoint(x: 0, y: 0),
          CanvasPoint(x: 10, y: 0),
          CanvasPoint(x: 20, y: 0),
        ]),
        color: 0xFF000000,
      );
      expect(dab, isNull);
    });

    test('anti-alias softens the edge and leaves the inside alone', () {
      // 유저 확정 ②: AA follows the fill, on by default. It is the SAME
      // post-pass the flood uses — that is why it needed no rasterizer.
      final shape = CanvasSelectionShape.rect(
        left: 10,
        top: 10,
        right: 40,
        bottom: 30,
      );
      final hard = buildShapeFillDab(
        shape: shape,
        color: 0xFF000000,
        options: const FloodFillOptions(expandPx: 0, antiAlias: false),
      )!;
      final soft = buildShapeFillDab(
        shape: shape,
        color: 0xFF000000,
        options: const FloodFillOptions(expandPx: 0, antiAlias: true),
      )!;
      expect(alphaAt(hard, 10, 20), 255);
      expect(alphaAt(soft, 10, 20), lessThan(255));
      expect(alphaAt(soft, 10, 20), greaterThan(0));
      expect(alphaAt(soft, 25, 20), 255, reason: 'only the edge softens');
    });
  });
}
