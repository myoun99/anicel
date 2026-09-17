import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';

/// 🚨★★★A COMMITTED TILE NEVER SHOWS ANOTHER TILE'S PICTURE — nor nothing
/// (유저 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」).
/// A coordinate with bytes shows a picture of those bytes on the very
/// paint that first needs it, made inside that paint through the one door.
///
/// Every case here used to be a frame of the stale-tile family: the
/// previous generation's picture at the coordinate (F-68 ①②③: an edit that
/// REMOVED ink showed the removed ink for a frame), a stand-in composed
/// from the predecessor, the per-pixel budget's four tiles and a blank for
/// the rest, the first activation's blank layer. The oracle is the raster:
/// what a paint puts on screen for a surface whose tiles have no pictures
/// yet.
void main() {
  const tileSize = 4;
  const red = 0xFFFF0000;
  const blue = 0xFF0000FF;

  BitmapTile tileOf(int argb) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = (argb >> 16) & 0xFF;
      pixels[i + 1] = (argb >> 8) & 0xFF;
      pixels[i + 2] = argb & 0xFF;
      pixels[i + 3] = (argb >> 24) & 0xFF;
    }
    return BitmapTile(size: tileSize, pixels: pixels);
  }

  BitmapSurface surfaceOf(Map<TileCoord, BitmapTile> tiles, {int columns = 1}) =>
      BitmapSurface(
        canvasSize: CanvasSize(width: columns * tileSize, height: tileSize),
        tileSize: tileSize,
        tiles: tiles,
      );

  Future<Uint8List> painted(
    BitmapSurface surface,
    BitmapTileImageCache cache, {
    int columns = 1,
  }) async {
    final size = Size((columns * tileSize).toDouble(), tileSize.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);
    BitmapSurfacePainter(
      surface: surface,
      showTransparentBackground: false,
      tileImageCache: cache,
    ).paint(canvas, size);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size.width.toInt(), size.height.toInt());
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  List<int> rgbaAt(Uint8List pixels, int x, int y, {int width = tileSize}) {
    final o = (y * width + x) * 4;
    return [pixels[o], pixels[o + 1], pixels[o + 2], pixels[o + 3]];
  }

  test('a tile with bytes and no picture draws them on the paint that '
      'first needs it', () async {
    final cache = BitmapTileImageCache();
    final tile = tileOf(red);
    expect(cache.imageFor(tile), isNull, reason: 'premise: no picture yet');
    final pixels = await painted(surfaceOf({TileCoord(x: 0, y: 0): tile}), cache);
    expect(rgbaAt(pixels, 1, 1), [255, 0, 0, 255]);
    expect(cache.imageFor(tile), isNotNull, reason: 'made inside the paint');
  });

  test('🚨an edit that REMOVES ink shows the removal on the very next paint '
      '(F-68)', () async {
    final cache = BitmapTileImageCache();
    final coord = TileCoord(x: 0, y: 0);
    final before = await painted(surfaceOf({coord: tileOf(red)}), cache);
    expect(rgbaAt(before, 1, 1), [255, 0, 0, 255], reason: 'premise: inked');

    // The commit replaces the tile with a NEW object that holds no ink.
    final erased = surfaceOf({coord: BitmapTile.blank(size: tileSize)});
    final after = await painted(erased, cache);
    // ⛔Mutation: answer with the previous generation's picture at the
    // coordinate → the removed ink shows for a frame.
    expect(after.every((byte) => byte == 0), isTrue, reason: 'no ink left');
  });

  test('an edit that CHANGES ink shows the new bytes, never the old '
      "picture's", () async {
    final cache = BitmapTileImageCache();
    final coord = TileCoord(x: 0, y: 0);
    await painted(surfaceOf({coord: tileOf(red)}), cache);
    final after = await painted(surfaceOf({coord: tileOf(blue)}), cache);
    expect(rgbaAt(after, 1, 1), [0, 0, 255, 255]);
  });

  test('a surface of fresh tile objects draws EVERY tile on its first paint '
      '— no ration, no blank', () async {
    // More tiles than any ration this painter ever had (four per pixel,
    // thirty-two a paint): every one must show on the first paint.
    const columns = 40;
    final cache = BitmapTileImageCache();
    final surface = surfaceOf({
      for (var x = 0; x < columns; x += 1) TileCoord(x: x, y: 0): tileOf(red),
    }, columns: columns);
    final pixels = await painted(surface, cache, columns: columns);
    final blankColumns = [
      for (var x = 0; x < columns; x += 1)
        if (rgbaAt(pixels, x * tileSize + 1, 1, width: columns * tileSize)[3] ==
            0)
          x,
    ];
    // ⛔Mutation: ration the pictures per paint → the tiles past the ration
    // are blank on this frame.
    expect(blankColumns, isEmpty, reason: 'every tile shows on the first paint');
  });
}
