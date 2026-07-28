import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/native_engine_path.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';

/// R18 A-0: the native engine core must be BYTE-IDENTICAL to the Dart
/// reference implementation — randomized stamps (paint and erase, edge
/// alphas, fractional opacities) materialized through both paths and
/// compared per pixel. Skips (loudly) when no locally built binary is
/// found; CI/dev machines with the standalone cmake build run it.
void main() {
  // R26/2A: resolved per platform (and via QA_ENGINE_PATH on CI) so these
  // byte-parity pins are not silently Windows-only.
  final dllPath = nativeEngineLibraryPathOrNull();
  final available = dllPath != null;

  setUp(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
  });

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  // Flattens over the PASTEBOARD rect (strokes clip there now, so tiles
  // can sit at negative coords) — the byte compare covers off-canvas
  // painting too.
  Uint8List snapshot(BitmapSurface surface, CanvasSize canvasSize) {
    final left = canvasSize.pasteboardLeft;
    final top = canvasSize.pasteboardTop;
    final width = canvasSize.pasteboardRightExclusive - left;
    final height = canvasSize.pasteboardBottomExclusive - top;
    final bytes = Uint8List(width * height * 4);
    for (final tile in surface.tiles.values) {
      final pixels = tile.pixels;
      for (var y = 0; y < tile.size; y += 1) {
        final globalY = tile.coord.y * tile.size + y;
        if (globalY >= canvasSize.pasteboardBottomExclusive) {
          break;
        }
        if (globalY < top) {
          continue;
        }
        for (var x = 0; x < tile.size; x += 1) {
          final globalX = tile.coord.x * tile.size + x;
          if (globalX >= canvasSize.pasteboardRightExclusive) {
            break;
          }
          if (globalX < left) {
            continue;
          }
          final source = (y * tile.size + x) * 4;
          final target = ((globalY - top) * width + (globalX - left)) * 4;
          bytes.setRange(target, target + 4, pixels, source);
        }
      }
    }
    return bytes;
  }

  test('native stamp blend == Dart reference, byte for byte (randomized)', () {
    if (!available) {
      markTestSkipped(
        'qa_engine.dll not built — run: cmake -S packages/qa_native/src -B '
        'build/native_standalone && cmake --build build/native_standalone '
        '--config Release',
      );
      return;
    }
    expect(
      QaNativeEngine.instance,
      isNotNull,
      reason: 'the locally built engine must load',
    );

    const canvasSize = CanvasSize(width: 96, height: 64);
    final random = Random(20260714);

    for (var round = 0; round < 24; round += 1) {
      final width = 1 + random.nextInt(60);
      final height = 1 + random.nextInt(40);
      final rgba = Uint8List(width * height * 4);
      for (var i = 0; i < rgba.length; i += 1) {
        // Edge-biased alphas: plenty of 0s and 255s plus the full range.
        final roll = random.nextInt(10);
        rgba[i] = roll == 0
            ? 0
            : roll == 1
            ? 255
            : random.nextInt(256);
      }
      final erase = round.isOdd;
      final opacityRoll = round % 3;
      final opacity = opacityRoll == 0
          ? 1.0
          : opacityRoll == 1
          ? 0.5
          : random.nextDouble();
      final dab = BrushDab(
        center: CanvasPoint(
          x: random.nextInt(canvasSize.width).toDouble(),
          y: random.nextInt(canvasSize.height).toDouble(),
        ),
        color: 0xFF000000,
        size: max(width, height).toDouble(),
        opacity: opacity,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.square,
        pressure: 1,
        sequence: 0,
        stamp: BrushStampImage(
          id: 'parity-$round',
          width: width,
          height: height,
          rgba: rgba,
        ),
        erase: erase,
      );

      // A non-blank base so blends exercise real destination bytes.
      final baseRgba = Uint8List(48 * 48 * 4);
      for (var i = 0; i < baseRgba.length; i += 1) {
        baseRgba[i] = random.nextInt(256);
      }
      final base = materializeBrushDabSequenceOnBitmapSurface(
        surface: BitmapSurface(canvasSize: canvasSize, tileSize: 32),
        sequence: BrushDabSequence([
          BrushDab(
            center: CanvasPoint(x: 30, y: 30),
            color: 0xFF000000,
            size: 48,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.square,
            pressure: 1,
            sequence: 0,
            stamp: BrushStampImage(
              id: 'base-$round',
              width: 48,
              height: 48,
              rgba: baseRgba,
            ),
          ),
        ]),
      ).surface;

      QaNativeEngine.debugForceDartFallback = true;
      final dartResult = materializeBrushDabSequenceOnBitmapSurface(
        surface: base,
        sequence: BrushDabSequence([dab]),
      );
      QaNativeEngine.debugForceDartFallback = false;
      final nativeResult = materializeBrushDabSequenceOnBitmapSurface(
        surface: base,
        sequence: BrushDabSequence([dab]),
      );

      expect(
        snapshot(nativeResult.surface, canvasSize),
        snapshot(dartResult.surface, canvasSize),
        reason:
            'round $round (erase=$erase opacity=$opacity '
            '${width}x$height) must be byte-identical',
      );
      expect(
        nativeResult.dirtyTiles.coords.toSet(),
        dartResult.dirtyTiles.coords.toSet(),
        reason: 'round $round dirty tiles must agree',
      );
    }
  });

  test('native generic dab blend == Dart reference, byte for byte '
      '(randomized, all shape/mask modes)', () {
    if (!available) {
      markTestSkipped(
        'qa_engine.dll not built — run: cmake -S packages/qa_native/src -B '
        'build/native_standalone && cmake --build build/native_standalone '
        '--config Release',
      );
      return;
    }
    expect(
      QaNativeEngine.instance,
      isNotNull,
      reason: 'the locally built engine must load',
    );

    const canvasSize = CanvasSize(width: 96, height: 64);
    final random = Random(20260713);

    BrushTipMask randomMask(String id) {
      final size = 3 + random.nextInt(22);
      final alpha = Uint8List(size * size);
      for (var i = 0; i < alpha.length; i += 1) {
        final roll = random.nextInt(8);
        alpha[i] = roll == 0
            ? 0
            : roll == 1
            ? 255
            : random.nextInt(256);
      }
      return BrushTipMask(id: id, size: size, alpha: alpha);
    }

    CanvasPoint randomCenter() {
      // Includes off-canvas overhang so region clamping gets exercised.
      return CanvasPoint(
        x: random.nextDouble() * (canvasSize.width + 20) - 10,
        y: random.nextDouble() * (canvasSize.height + 20) - 10,
      );
    }

    for (var round = 0; round < 40; round += 1) {
      final mode = round % 8;
      final heavy = mode == 6;
      final anyMask = mode == 7 && random.nextBool();
      final tipMask = (mode == 4 || mode == 5 || heavy || anyMask)
          ? randomMask('tip-$round')
          : null;
      final dualMask = (heavy || (mode == 7 && random.nextBool()))
          ? randomMask('dual-$round')
          : null;
      final textureMask = (heavy || (mode == 7 && random.nextBool()))
          ? randomMask('texture-$round')
          : null;
      // Mode map: 0 plain round, 1 ellipse, 2 square, 3 rotated rect,
      // 4 unrotated tip, 5 rotated tip, 6 tip+dual+texture, 7 chaos.
      final isRoundTip =
          mode == 0 || mode == 1 || (mode == 7 && random.nextBool());
      final roundness =
          (mode == 1 || mode == 3 || mode == 5 || heavy || mode == 7)
          ? 0.2 + random.nextDouble() * 0.8
          : 1.0;
      final angleDegrees = (mode == 3 || mode == 5 || heavy)
          ? random.nextDouble() * 360.0 - 180.0
          : (mode == 7 && random.nextBool())
          ? random.nextDouble() * 90.0
          : 0.0;

      final dabs = <BrushDab>[];
      for (var i = 0; i < 3; i += 1) {
        dabs.add(
          BrushDab(
            center: randomCenter(),
            color:
                (0xFF000000 |
                (random.nextInt(256) << 16) |
                (random.nextInt(256) << 8) |
                random.nextInt(256)),
            size: 2.0 + random.nextDouble() * 48.0,
            opacity: i == 0 ? 1.0 : random.nextDouble(),
            flow: i == 1 ? 0.5 : 0.05 + random.nextDouble() * 0.95,
            hardness: random.nextDouble(),
            tipShape: isRoundTip ? BrushTipShape.round : BrushTipShape.square,
            pressure: 1,
            sequence: i,
            roundness: roundness,
            angleDegrees: angleDegrees,
            tipMask: tipMask,
            dualMask: dualMask,
            dualMaskScale: dualMask == null
                ? 1.0
                : 0.3 + random.nextDouble() * 2.0,
            dualOffsetU: dualMask == null ? 0.0 : random.nextDouble(),
            dualOffsetV: dualMask == null ? 0.0 : random.nextDouble(),
            textureMask: textureMask,
            textureScale: textureMask == null
                ? 1.0
                : 0.3 + random.nextDouble() * 2.0,
            textureDensity: textureMask == null ? 1.0 : random.nextDouble(),
            erase: round % 3 == 2 && i > 0,
          ),
        );
      }
      final sequence = BrushDabSequence(dabs);

      // A partially painted base (built through the Dart reference so both
      // runs start from the identical surface).
      QaNativeEngine.debugForceDartFallback = true;
      final base = materializeBrushDabSequenceOnBitmapSurface(
        surface: BitmapSurface(canvasSize: canvasSize, tileSize: 32),
        sequence: BrushDabSequence([
          BrushDab(
            center: CanvasPoint(x: 30, y: 28),
            color: 0xFF3366CC,
            size: 44,
            opacity: 0.9,
            flow: 1,
            hardness: 0.4,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: 0,
          ),
        ]),
      ).surface;

      final dartResult = materializeBrushDabSequenceOnBitmapSurface(
        surface: base,
        sequence: sequence,
      );
      QaNativeEngine.debugForceDartFallback = false;
      final nativeResult = materializeBrushDabSequenceOnBitmapSurface(
        surface: base,
        sequence: sequence,
      );

      expect(
        snapshot(nativeResult.surface, canvasSize),
        snapshot(dartResult.surface, canvasSize),
        reason:
            'round $round (mode $mode roundness=$roundness '
            'angle=$angleDegrees tip=${tipMask?.size} dual=${dualMask?.size} '
            'texture=${textureMask?.size}) must be byte-identical',
      );
      expect(
        nativeResult.dirtyTiles.coords.toSet(),
        dartResult.dirtyTiles.coords.toSet(),
        reason: 'round $round dirty tiles must agree',
      );
    }
  });

  test('native path handles mixed stamp + generic dab sequences', () {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    const canvasSize = CanvasSize(width: 96, height: 64);
    final random = Random(99);
    final stampRgba = Uint8List(24 * 24 * 4);
    for (var i = 0; i < stampRgba.length; i += 1) {
      stampRgba[i] = random.nextInt(256);
    }
    final sequence = BrushDabSequence([
      BrushDab(
        center: CanvasPoint(x: 20, y: 20),
        color: 0xFFCC2200,
        size: 30,
        opacity: 0.8,
        flow: 0.9,
        hardness: 0.5,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: 0,
      ),
      BrushDab(
        center: CanvasPoint(x: 40, y: 30),
        color: 0xFF000000,
        size: 24,
        opacity: 0.7,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.square,
        pressure: 1,
        sequence: 1,
        stamp: BrushStampImage(
          id: 'mixed-stamp',
          width: 24,
          height: 24,
          rgba: stampRgba,
        ),
      ),
      BrushDab(
        center: CanvasPoint(x: 32, y: 26),
        color: 0xFF000000,
        size: 26,
        opacity: 0.6,
        flow: 1,
        hardness: 0.3,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: 2,
        erase: true,
      ),
    ]);

    QaNativeEngine.debugForceDartFallback = true;
    final dartResult = materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: 32),
      sequence: sequence,
    );
    QaNativeEngine.debugForceDartFallback = false;
    final nativeResult = materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: 32),
      sequence: sequence,
    );
    // A second native run with the SAME stamp instance rides the stamp
    // upload cache (A-1.5) — must stay byte-identical.
    final nativeRepeat = materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: 32),
      sequence: sequence,
    );

    expect(
      snapshot(nativeResult.surface, canvasSize),
      snapshot(dartResult.surface, canvasSize),
    );
    expect(
      nativeResult.dirtyTiles.coords.toSet(),
      dartResult.dirtyTiles.coords.toSet(),
    );
    expect(
      snapshot(nativeRepeat.surface, canvasSize),
      snapshot(dartResult.surface, canvasSize),
      reason: 'stamp upload cache reuse must stay byte-identical',
    );
  });

  test('native flood fill == Dart reference (frontier-stepped, '
      'randomized)', () {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final engine = QaNativeEngine.instance!;
    final random = Random(20260714);

    for (var round = 0; round < 10; round += 1) {
      // Sizes spanning one to many 256px compose tiles.
      final width = 200 + random.nextInt(500);
      final height = 150 + random.nextInt(400);
      // RGBX (R22-D): X stays 0 everywhere — the SIMD compare contract.
      final source = Uint8List(width * height * 4);
      for (var i = 0; i < source.length; i += 4) {
        source[i] = 200;
        source[i + 1] = 200;
        source[i + 2] = 200;
      }
      // Blobby content: random rectangles of random colors — tolerance
      // then forms real regions with edges crossing tile boundaries.
      for (var blob = 0; blob < 30; blob += 1) {
        final r = random.nextInt(256);
        final g = random.nextInt(256);
        final b = random.nextInt(256);
        final left = random.nextInt(width);
        final top = random.nextInt(height);
        final blobWidth = 1 + random.nextInt(width - left);
        final blobHeight = 1 + random.nextInt(height - top);
        for (var y = top; y < top + blobHeight; y += 1) {
          var offset = (y * width + left) * 4;
          for (var x = 0; x < blobWidth; x += 1) {
            source[offset] = r;
            source[offset + 1] = g;
            source[offset + 2] = b;
            offset += 4;
          }
        }
      }
      final seedX = random.nextInt(width);
      final seedY = random.nextInt(height);
      final options = FloodFillOptions(
        tolerance: const [0, 16, 48][round % 3],
        expandPx: round % 2,
        antiAlias: round.isOdd,
      );

      // Dart reference: plain heap raster, bytes fully present.
      QaNativeEngine.debugForceDartFallback = true;
      final dartRegion = floodFillRegion(
        rgb: source,
        width: width,
        height: height,
        seedX: seedX,
        seedY: seedY,
        options: options,
        ensureComposed: (_) {},
      );
      QaNativeEngine.debugForceDartFallback = false;

      // Native: a LAZY composer copies tile spans from the source into
      // the native rgb view on demand — the real frontier-step path.
      final handles = engine.acquireFloodRaster(
        width: width,
        height: height,
        composeTileSize: 256,
      );
      var composeCalls = 0;
      void composeAt(int index) {
        final x = index % width;
        final y = index ~/ width;
        final tileIndex = (y >> 8) * handles.tilesX + (x >> 8);
        if (handles.composedView[tileIndex] != 0) {
          return;
        }
        handles.composedView[tileIndex] = 1;
        composeCalls += 1;
        final left = (x >> 8) << 8;
        final top = (y >> 8) << 8;
        final right = min(left + 256, width);
        final bottom = min(top + 256, height);
        for (var yy = top; yy < bottom; yy += 1) {
          final start = (yy * width + left) * 4;
          handles.rgbView.setRange(
            start,
            (yy * width + right) * 4,
            source,
            start,
          );
        }
      }

      final nativeRegion = floodFillRegion(
        rgb: handles.rgbView,
        width: width,
        height: height,
        seedX: seedX,
        seedY: seedY,
        options: options,
        ensureComposed: composeAt,
        nativeHandles: handles,
      );

      expect(nativeRegion, isNotNull);
      expect(dartRegion, isNotNull);
      expect(composeCalls, greaterThan(0));
      expect(
        (
          nativeRegion!.left,
          nativeRegion.top,
          nativeRegion.width,
          nativeRegion.height,
        ),
        (dartRegion!.left, dartRegion.top, dartRegion.width, dartRegion.height),
        reason:
            'round $round (${width}x$height seed $seedX,$seedY '
            'tol ${options.tolerance}) region geometry must agree',
      );
      expect(
        nativeRegion.mask,
        dartRegion.mask,
        reason: 'round $round mask must be byte-identical',
      );
    }
  });

  test('native fill compose == Dart reference, byte for byte '
      '(layers, opacity, sparse tiles)', () {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    const canvasSize = CanvasSize(width: 600, height: 520);

    BitmapSurface randomSurface(int seed) {
      final surfaceRandom = Random(seed);
      const tileSize = 64;
      final tiles = <TileCoord, BitmapTile>{};
      for (var ty = 0; ty < (canvasSize.height + 63) ~/ 64; ty += 1) {
        for (var tx = 0; tx < (canvasSize.width + 63) ~/ 64; tx += 1) {
          if (surfaceRandom.nextInt(3) == 0) {
            continue; // Sparse: some coordinates stay empty.
          }
          final pixels = Uint8List(tileSize * tileSize * 4);
          for (var i = 0; i < pixels.length; i += 1) {
            final roll = surfaceRandom.nextInt(6);
            pixels[i] = roll == 0
                ? 0
                : roll == 1
                ? 255
                : surfaceRandom.nextInt(256);
          }
          final coord = TileCoord(x: tx, y: ty);
          tiles[coord] = BitmapTile(
            coord: coord,
            size: tileSize,
            pixels: pixels,
          );
        }
      }
      return BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: tiles,
      );
    }

    Frame frame(String id) =>
        Frame(id: FrameId(id), duration: 1, strokes: const []);
    Layer layerWith(String id, double opacity) => Layer(
      id: LayerId(id),
      name: id,
      opacity: opacity,
      frames: [frame('$id-frame')],
      timeline: {0: TimelineExposure.drawing(FrameId('$id-frame'), length: 1)},
    );
    final cut = Cut(
      id: const CutId('cut'),
      name: 'Cut',
      layers: [layerWith('below', 1.0), layerWith('above', 0.55)],
      duration: 24,
      canvasSize: canvasSize,
    );
    final surfaces = {
      const LayerId('below'): randomSurface(1),
      const LayerId('above'): randomSurface(2),
    };

    LazyCanvasRasterRgb rasterFor() => LazyCanvasRasterRgb(
      cut: cut,
      frameIndex: 0,
      surfaceResolver: (layer, _) => surfaces[layer.id],
    );
    void composeAll(LazyCanvasRasterRgb raster) {
      for (var y = 0; y < canvasSize.height; y += 256) {
        for (var x = 0; x < canvasSize.width; x += 256) {
          raster.ensureComposedAt(y * canvasSize.width + x);
        }
      }
    }

    QaNativeEngine.debugForceDartFallback = true;
    final dartRaster = rasterFor();
    composeAll(dartRaster);
    QaNativeEngine.debugForceDartFallback = false;
    final nativeRaster = rasterFor();
    composeAll(nativeRaster);

    expect(
      Uint8List.fromList(nativeRaster.rgb),
      Uint8List.fromList(dartRaster.rgb),
      reason: 'composed raster must be byte-identical',
    );

    // End to end: the whole fill tap (compose + flood + stamp build)
    // must produce the identical dab through both paths.
    QaNativeEngine.debugForceDartFallback = true;
    final dartDab = buildFillDab(
      cut: cut,
      frameIndex: 0,
      surfaceResolver: (layer, _) => surfaces[layer.id],
      point: CanvasPoint(x: 300, y: 260),
      color: 0xFF3366CC,
      options: const FloodFillOptions(tolerance: 40),
    );
    QaNativeEngine.debugForceDartFallback = false;
    final nativeDab = buildFillDab(
      cut: cut,
      frameIndex: 0,
      surfaceResolver: (layer, _) => surfaces[layer.id],
      point: CanvasPoint(x: 300, y: 260),
      color: 0xFF3366CC,
      options: const FloodFillOptions(tolerance: 40),
    );

    expect(nativeDab, isNotNull);
    expect(dartDab, isNotNull);
    expect(nativeDab!.center, dartDab!.center);
    expect(nativeDab.stamp!.width, dartDab.stamp!.width);
    expect(nativeDab.stamp!.height, dartDab.stamp!.height);
    expect(
      nativeDab.stamp!.rgba,
      dartDab.stamp!.rgba,
      reason: 'the whole fill tap must be byte-identical end to end',
    );
  });

  test('native premultiply == Dart reference, byte for byte (randomized)', () {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final random = Random(7);
    for (var round = 0; round < 12; round += 1) {
      final size = 1 + random.nextInt(48);
      final bytes = Uint8List(size * size * 4);
      for (var i = 0; i < bytes.length; i += 1) {
        // Edge-biased: plenty of alpha 0 / 255 plus the full range.
        final roll = random.nextInt(6);
        bytes[i] = roll == 0
            ? 0
            : roll == 1
            ? 255
            : random.nextInt(256);
      }
      final tile = BitmapTile(
        coord: TileCoord(x: 0, y: 0),
        size: size,
        pixels: bytes,
      );

      QaNativeEngine.debugForceDartFallback = true;
      final dartUpload = BitmapTileImageCache.premultipliedTileUpload(tile);
      QaNativeEngine.debugForceDartFallback = false;
      final nativeUpload = BitmapTileImageCache.premultipliedTileUpload(tile);
      // Copy the native view out before releasing it: the comparison
      // below outlives the scratch.
      final dartResult = Uint8List.fromList(dartUpload.view);
      final nativeResult = Uint8List.fromList(nativeUpload.view);
      dartUpload.free();
      nativeUpload.free();

      expect(
        nativeResult,
        dartResult,
        reason: 'round $round (${size}x$size) must be byte-identical',
      );
    }
  });
}
