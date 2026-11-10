// The first lift compiles the kernels and the pool's: tens of seconds on a
// machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/cel_pixel_overwrite.dart';
import 'package:anicel/src/services/cel_pixel_region.dart';

/// A SELECTION'S LIFT ON THE ENGINE (flip lane ⓒ): on the app's grid what a
/// selection takes off a cel is the kernel's (lift.wgsl), held byte for byte
/// to the Dart gather, over boxes that straddle tile edges and whole pixels
/// or a feather's.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const side = 128;
  const canvas = CanvasSize(width: 512, height: 512);
  final ledger = EngineTileLedger.instance;

  tearDown(() => debugSelectionLiftInDart = false);

  BitmapTile tileOf(int seed) {
    final bytes = Uint8List(side * side * 4);
    for (var i = 0; i < side * side; i += 1) {
      final o = i * 4;
      if ((i + seed) % 5 == 0) {
        continue;
      }
      bytes
        ..[o] = (i * 31 + seed) % 256
        ..[o + 1] = (i * 17) % 256
        ..[o + 2] = (i * 13 + 5) % 256
        ..[o + 3] = (i * 7 + seed) % 256;
    }
    return BitmapTile(size: side, pixels: bytes);
  }

  BitmapSurface artwork() => BitmapSurface(
    canvasSize: canvas,
    tileSize: side,
    tiles: {
      TileCoord(x: 0, y: 0): tileOf(0),
      TileCoord(x: 1, y: 0): tileOf(3),
      TileCoord(x: 0, y: 1): tileOf(7),
      TileCoord(x: -1, y: -1): tileOf(11),
    },
  );

  Uint8List maskOf(int width, int height) => Uint8List.fromList([
    for (var i = 0; i < width * height; i += 1)
      switch (i % 5) {
        0 => 0,
        1 => 255,
        _ => (i * 37) % 256,
      },
  ]);

  final boxes = <String, ({int left, int top, int width, int height})>{
    'inside a tile': (left: 5, top: 9, width: 40, height: 30),
    'across a tile edge': (left: 100, top: 20, width: 60, height: 20),
    'across four tiles, one of them none': (
      left: 100,
      top: 100,
      width: 60,
      height: 60,
    ),
    'off the top-left': (left: -30, top: -20, width: 50, height: 40),
    'of a tile alone': (left: 128, top: 0, width: 128, height: 128),
  };

  for (final MapEntry(key: name, value: box) in boxes.entries) {
    for (final whole in [true, false]) {
      test('$name, ${whole ? 'whole pixels' : 'a feather'}: as the gather in '
          'Dart', () {
        final surface = artwork();
        final (:left, :top, :width, :height) = box;
        final mask = maskOf(width, height);
        ({Uint8List rgba, bool liftedAnything}) gathered() =>
            gatherMaskedSurfacePixels(
              surface: surface,
              mask: mask,
              left: left,
              top: top,
              width: width,
              height: height,
              takeWholePixels: whole,
            );
        debugSelectionLiftInDart = true;
        final inDart = gathered();
        debugSelectionLiftInDart = false;
        final reads = ledger.debugTileReads;
        final onEngine = gathered();
        expect(onEngine.rgba, inDart.rgba);
        expect(onEngine.liftedAnything, inDart.liftedAnything);
        expect(ledger.debugTileReads, reads, reason: 'no tile read back');
      });
    }
  }

  test('a box over no tile lifts nothing, and asks the engine nothing', () {
    final lifted = gatherMaskedSurfacePixels(
      surface: artwork(),
      mask: Uint8List(100)..fillRange(0, 100, 255),
      left: 300,
      top: 300,
      width: 10,
      height: 10,
      takeWholePixels: true,
    );
    expect(lifted.liftedAnything, isFalse);
    expect(lifted.rgba, Uint8List(400));
  });

  test('a mask over nothing painted lifts nothing', () {
    final lifted = gatherMaskedSurfacePixels(
      surface: artwork(),
      mask: Uint8List(100),
      left: 10,
      top: 10,
      width: 10,
      height: 10,
      takeWholePixels: true,
    );
    expect(lifted.liftedAnything, isFalse);
    expect(lifted.rgba, Uint8List(400));
  });

  test('the gather in Dart is the one those compare against: it reads the '
      'engine\'s tiles back', () {
    final surface = artwork();
    final verbed = overwriteCelPixels(
      surface: surface,
      channel: CelPixelChannel.colour,
      walk: celPixelWalkFor(surface: surface),
      value: Uint8List.fromList([1, 2, 3]),
    ).surface;
    debugSelectionLiftInDart = true;
    final reads = ledger.debugTileReads;
    gatherMaskedSurfacePixels(
      surface: verbed,
      mask: Uint8List(4)..fillRange(0, 4, 255),
      left: 1,
      top: 0,
      width: 2,
      height: 2,
      takeWholePixels: true,
    );
    expect(ledger.debugTileReads, greaterThan(reads));
  });

  test('a lift off what a verb left reads none of it back', () {
    final surface = artwork();
    final verbed = overwriteCelPixels(
      surface: surface,
      channel: CelPixelChannel.colour,
      walk: celPixelWalkFor(surface: surface),
      value: Uint8List.fromList([1, 2, 3]),
    ).surface;
    final reads = ledger.debugTileReads;
    final lifted = gatherMaskedSurfacePixels(
      surface: verbed,
      mask: Uint8List(4)..fillRange(0, 4, 255),
      left: 1,
      top: 0,
      width: 2,
      height: 2,
      takeWholePixels: true,
    );
    expect(ledger.debugTileReads, reads);
    expect(lifted.liftedAnything, isTrue);
    expect(lifted.rgba.sublist(0, 3), [1, 2, 3]);
  });
}
