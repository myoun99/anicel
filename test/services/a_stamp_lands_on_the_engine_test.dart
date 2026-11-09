// The first landing compiles the executor and the stamp's kernels: 40 s on
// a machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';

/// 🚨WHAT A PROGRAM COMMITS LANDS ON THE ENGINE (flip lane ⓒ): a fill, a
/// lift's hole and its landing, a stroke re-derived from its dabs — each a
/// tile the engine made, compared with the one under it, so a commit that
/// changes nothing names no tile and one that empties a tile drops it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvas = CanvasSize(width: 320, height: 256);
  const ink = [200, 100, 50, 255];

  BrushStampImage solid(
    int width,
    int height,
    List<int> pixel, {
    String id = 'solid',
  }) => BrushStampImage(
    id: id,
    width: width,
    height: height,
    rgba: Uint8List.fromList([
      for (var at = 0; at < width * height; at += 1) ...pixel,
    ]),
  );

  BrushDab dabOf(
    BrushStampImage stamp, {
    required int left,
    required int top,
    double opacity = 1,
    bool erase = false,
    int sequence = 0,
  }) => BrushDab(
    center: CanvasPoint(x: left + stamp.width / 2, y: top + stamp.height / 2),
    color: 0xFF000000,
    size: stamp.width.toDouble(),
    opacity: opacity,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: sequence,
    erase: erase,
    stamp: stamp,
  );

  BrushSurfaceMaterialization landed(
    BitmapSurface surface,
    List<BrushDab> dabs,
  ) => materializeBrushDabSequenceOnBitmapSurface(
    surface: surface,
    sequence: BrushDabSequence(dabs),
  );

  BitmapSurface empty({PasteboardReach reach = PasteboardReach.whole}) =>
      BitmapSurface(canvasSize: canvas, pasteboardReach: reach);

  /// [canvas]'s pixel (x, y) of [surface], straight.
  List<int> pixelAt(BitmapSurface surface, int x, int y) {
    final tile = surface.tileAt(TileCoord(x: x >> 7, y: y >> 7));
    if (tile == null) {
      return const [0, 0, 0, 0];
    }
    final at = ((y & 127) * 128 + (x & 127)) * 4;
    return tile.pixels.sublist(at, at + 4);
  }

  final painted = landed(empty(), [
    dabOf(solid(128, 128, const [10, 20, 30, 255]), left: 0, top: 0),
  ]).surface;

  test('a stamp lands its pixels on a tile the engine made', () {
    final result = landed(empty(), [
      dabOf(solid(10, 10, ink), left: 10, top: 20),
    ]);
    expect(result.dirtyTiles.coords, [TileCoord(x: 0, y: 0)]);
    final tile = result.surface.tileAt(TileCoord(x: 0, y: 0))!;
    expect(tile.isOnEngine, isTrue, reason: 'no CPU copy of what it made');
    expect(pixelAt(result.surface, 12, 22), ink);
    expect(pixelAt(result.surface, 9, 20), const [0, 0, 0, 0]);
    expect(pixelAt(result.surface, 12, 19), const [0, 0, 0, 0]);
  });

  test('each tile a stamp crosses takes its part, in row order', () {
    final result = landed(empty(), [
      dabOf(solid(16, 8, ink), left: 120, top: 124),
    ]);
    expect(result.dirtyTiles.coords, [
      TileCoord(x: 0, y: 0),
      TileCoord(x: 1, y: 0),
      TileCoord(x: 0, y: 1),
      TileCoord(x: 1, y: 1),
    ]);
    expect(pixelAt(result.surface, 127, 127), ink);
    expect(pixelAt(result.surface, 128, 127), ink);
    expect(pixelAt(result.surface, 127, 128), ink);
    expect(pixelAt(result.surface, 135, 131), ink);
    expect(pixelAt(result.surface, 136, 131), const [0, 0, 0, 0]);
  });

  test('a stamp lays at its opacity over what the tile holds', () {
    final result = landed(painted, [
      dabOf(solid(10, 10, ink), left: 10, top: 20, opacity: 0.5),
    ]);
    final [red, green, blue, alpha] = pixelAt(result.surface, 12, 22);
    expect(alpha, 255);
    expect(red, inInclusiveRange(104, 106));
    expect(green, inInclusiveRange(59, 61));
    expect(blue, inInclusiveRange(39, 41));
    expect(pixelAt(result.surface, 5, 5), const [10, 20, 30, 255]);
    expect(
      pixelAt(painted, 12, 22),
      const [10, 20, 30, 255],
      reason: 'the surface it lands on is not written',
    );
  });

  test('an erase stamp takes what it covers, whatever its colour', () {
    final result = landed(painted, [
      dabOf(solid(10, 10, ink), left: 10, top: 20, erase: true),
    ]);
    expect(pixelAt(result.surface, 12, 22), const [0, 0, 0, 0]);
    expect(pixelAt(result.surface, 5, 5), const [10, 20, 30, 255]);
  });

  test('an erase that empties a tile drops it and still names it', () {
    final result = landed(painted, [
      dabOf(solid(128, 128, ink), left: 0, top: 0, erase: true),
    ]);
    expect(result.surface.tileAt(TileCoord(x: 0, y: 0)), isNull);
    expect(result.dirtyTiles.coords, [TileCoord(x: 0, y: 0)]);
  });

  test('a stamp that changes nothing names no tile', () {
    final nothing = landed(painted, [
      dabOf(solid(10, 10, const [9, 9, 9, 0]), left: 10, top: 20),
    ]);
    expect(nothing.hasChanges, isFalse);
    expect(identical(nothing.surface, painted), isTrue);
  });

  test('a stamp at no opacity does not land', () {
    final nothing = landed(painted, [
      dabOf(solid(10, 10, ink), left: 10, top: 20, opacity: 0),
    ]);
    expect(nothing.hasChanges, isFalse);
  });

  test('a stamp keeps what the wall leaves of it, and no more', () {
    final result = landed(empty(reach: PasteboardReach.none), [
      dabOf(solid(20, 10, ink), left: 310, top: 30),
    ]);
    expect(pixelAt(result.surface, 319, 32), ink);
    // Past the canvas, on the tile the canvas's edge cuts.
    final tile = result.surface.tileAt(TileCoord(x: 2, y: 0))!;
    const past = ((32 * 128) + (320 - 256)) * 4;
    expect(tile.pixels.sublist(past, past + 4), const [0, 0, 0, 0]);
  });

  test('a stamp wholly past the wall lands nothing', () {
    final nothing = landed(empty(reach: PasteboardReach.none), [
      dabOf(solid(20, 10, ink), left: 400, top: 30),
    ]);
    expect(nothing.hasChanges, isFalse);
  });

  test('a program means what it says dab by dab: the hole, then the '
      'piece', () {
    final result = landed(painted, [
      dabOf(solid(10, 10, ink), left: 10, top: 20, erase: true),
      dabOf(
        solid(4, 4, const [1, 2, 3, 255], id: 'piece'),
        left: 12,
        top: 22,
        sequence: 1,
      ),
    ]);
    expect(pixelAt(result.surface, 13, 23), const [1, 2, 3, 255]);
    expect(pixelAt(result.surface, 10, 20), const [0, 0, 0, 0]);
    expect(result.dirtyTiles.coords, [TileCoord(x: 0, y: 0)]);
  });

  test('brush dabs land as one stroke, on what the stamp before left', () {
    BrushDab brush({required int sequence, bool erase = false}) => BrushDab(
      center: CanvasPoint(x: 40, y: 40),
      color: 0xFFC86432,
      size: 20,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: sequence,
      erase: erase,
    );
    final result = landed(empty(), [
      dabOf(solid(64, 64, const [10, 20, 30, 255]), left: 8, top: 8),
      brush(sequence: 1, erase: true),
    ]);
    expect(pixelAt(result.surface, 40, 40), const [0, 0, 0, 0]);
    expect(pixelAt(result.surface, 12, 12), const [10, 20, 30, 255]);
    expect(
      result.surface.tileAt(TileCoord(x: 0, y: 0))!.isOnEngine,
      isTrue,
    );

    final over = landed(empty(), [brush(sequence: 0)]);
    expect(pixelAt(over.surface, 40, 40), const [200, 100, 50, 255]);
  });

  test('a stamp landed again is uploaded once', () {
    final stamp = solid(64, 64, ink, id: 'moved');
    var surface = landed(empty(), [dabOf(stamp, left: 0, top: 0)]).surface;
    final once = GpuStampPicture.liveBytes;
    surface = landed(surface, [dabOf(stamp, left: 5, top: 5)]).surface;
    expect(GpuStampPicture.liveBytes - once, lessThanOrEqualTo(0));
    expect(pixelAt(surface, 68, 68), ink);
  });

  group('a stroke\'s picture composited once', () {
    Uint8List strokeOf(List<int> pixel, int count) => Uint8List.fromList([
      for (var at = 0; at < count; at += 1) ...pixel,
    ]);
    final bounds = DirtyRegion(
      left: 10,
      top: 20,
      rightExclusive: 20,
      bottomExclusive: 30,
    );

    test('lands in its blend, once', () {
      final result = compositeStrokePixelsOntoBitmapSurface(
        surface: landed(empty(), [
          dabOf(solid(128, 128, const [100, 200, 40, 255]), left: 0, top: 0),
        ]).surface,
        strokePixels: strokeOf(const [128, 128, 128, 255], 100),
        bounds: bounds,
        blendMode: BrushBlendMode.multiply,
      );
      final [red, green, blue, alpha] = pixelAt(result.surface, 12, 22);
      expect(alpha, 255);
      expect(red, inInclusiveRange(49, 51));
      expect(green, inInclusiveRange(99, 101));
      expect(blue, inInclusiveRange(19, 21));
      expect(
        result.surface.tileAt(TileCoord(x: 0, y: 0))!.isOnEngine,
        isTrue,
      );
    });

    test('erases where it is an eraser\'s', () {
      final result = compositeStrokePixelsOntoBitmapSurface(
        surface: painted,
        strokePixels: strokeOf(const [0, 0, 0, 255], 100),
        bounds: bounds,
        erase: true,
      );
      expect(pixelAt(result.surface, 12, 22), const [0, 0, 0, 0]);
      expect(result.dirtyTiles.coords, [TileCoord(x: 0, y: 0)]);
    });

    test('a picture of nothing names no tile', () {
      final result = compositeStrokePixelsOntoBitmapSurface(
        surface: painted,
        strokePixels: strokeOf(const [0, 0, 0, 0], 100),
        bounds: bounds,
      );
      expect(result.hasChanges, isFalse);
      expect(identical(result.surface, painted), isTrue);
    });
  });
}
