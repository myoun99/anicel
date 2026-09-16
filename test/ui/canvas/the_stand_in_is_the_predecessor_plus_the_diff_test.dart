import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/provisional_tile_pictures.dart';
import 'package:anicel/src/ui/canvas/tile_predecessors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-68 root fix (2026-09-11): a tile with no picture yet is drawn from
/// THE TILE THE COMMIT REPLACED plus the bytes that differ — not from
/// whatever was last decoded at the coordinate.
///
/// 유저 F-68: 「축소시 축소 바깥의 기존그림영역의 그림이 1프레임 생겼다가
/// 사라지는듯. 심지어 안사라질때도있음」 — and the lift's twin, 「그림의
/// 일부가 1프레임 이상한곳에 생겼다가 사라짐」. Both were the coordinate
/// fallback (`latestImageForCoord`) answering for a tile an edit had just
/// EMPTIED with the picture of the tile that stood there before, ink and
/// all. The fixes before this one seeded a stand-in per edit path (the lift,
/// the landing); this pins the mechanism every path shares, so the next
/// removal — a pixel verb, an undo — cannot fall through it.
///
/// ⚠️Fully opaque and fully transparent pixels throughout: the composed
/// picture is premultiplied by the engine and read back the same way, and
/// at alpha 255/0 that round trip is exact, so the assertions can be
/// byte-equal rather than tolerant.
void main() {
  const size = 16;
  const red = 0xFFFF0000;
  const blue = 0xFF0000FF;

  /// A [size]×[size] straight-RGBA tile filled with [argb], then edited by
  /// [paint] (x, y, argb → argb).
  BitmapTile tile(int argb, {int Function(int x, int y, int argb)? paint}) {
    final pixels = Uint8List(size * size * 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final c = paint == null ? argb : paint(x, y, argb);
        final o = (y * size + x) * 4;
        pixels[o] = (c >> 16) & 0xFF;
        pixels[o + 1] = (c >> 8) & 0xFF;
        pixels[o + 2] = c & 0xFF;
        pixels[o + 3] = (c >> 24) & 0xFF;
      }
    }
    return BitmapTile(size: size, pixels: pixels);
  }

  BitmapSurface surfaceOf(BitmapTile t) => BitmapSurface(
    canvasSize: const CanvasSize(width: size, height: size),
    tileSize: size,
    tiles: {TileCoord(x: 0, y: 0): t},
  );

  /// Decoded IN THE PAINTER'S SCOPE ('cel'), so the coordinate fallback's
  /// bucket holds this tile afterwards — the wrong answer the painter pins
  /// below prove is no longer reached. ⚠️A first version decoded under no
  /// scope, the bucket stayed empty, the per-pixel path drew the right
  /// pixels, and the pins passed with the fix turned OFF (mutant M1,
  /// 2026-09-11): the instrument was measuring nothing.
  Future<void> decode(BitmapTileImageCache cache, BitmapTile t) async {
    cache.ensureDecoded(
      (coord: TileCoord(x: 0, y: 0), tile: t),
      staleScope: 'cel',
    );
    for (var attempt = 0; attempt < 200; attempt += 1) {
      if (cache.imageFor(t) != null) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('the decode never landed');
  }

  Future<Uint8List> bytesOf(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  }

  List<int> rgbaAt(Uint8List px, int x, int y) {
    final o = (y * size + x) * 4;
    return [px[o], px[o + 1], px[o + 2], px[o + 3]];
  }

  group('composePredecessorStandIn', () {
    test('predecessor picture + the differing runs = the new tile, '
        'transparent where the edit ERASED', () async {
      final cache = BitmapTileImageCache();
      final before = tile(red);
      // Rows 4..7 erased, one pixel recoloured — a removal and an addition
      // in one tile, which is exactly the case the coordinate fallback got
      // half right.
      final after = tile(
        red,
        paint: (x, y, c) => (y >= 4 && y < 8) ? 0 : (x == 2 && y == 2 ? blue : c),
      );
      await decode(cache, before);
      TilePredecessors.instance.note(after, before);

      final composed = composePredecessorStandIn(
        cache: cache,
        placed: (coord: TileCoord(x: 0, y: 0), tile: after),
        predecessor: TilePredecessors.instance.of(after)!,
        rectBudget: 1000,
      );
      expect(composed.image, isNotNull);
      // Four erased rows, one run each, plus the single blue pixel.
      expect(composed.rects, 5);
      expect(cache.hasProvisional(after), isTrue, reason: 'ownership moved');
      expect(TilePredecessors.instance.of(after), isNull, reason: 'composed once');
      expect(
        identical(cache.displayImageFor(after), composed.image),
        isTrue,
        reason: 'the painter will draw exactly this',
      );

      final px = await bytesOf(composed.image!);
      expect(rgbaAt(px, 0, 0), [255, 0, 0, 255], reason: 'kept red');
      expect(rgbaAt(px, 0, 5), [0, 0, 0, 0], reason: 'the erase erased');
      expect(rgbaAt(px, 2, 2), [0, 0, 255, 255], reason: 'the addition');
    });

    test('an EMPTY predecessor composes from transparent', () async {
      final cache = BitmapTileImageCache();
      final after = tile(0, paint: (x, y, c) => y == 3 ? red : 0);
      TilePredecessors.instance.note(after, null);
      final composed = composePredecessorStandIn(
        cache: cache,
        placed: (coord: TileCoord(x: 0, y: 0), tile: after),
        predecessor: TilePredecessors.instance.of(after)!,
        rectBudget: 1000,
      );
      expect(composed.image, isNotNull);
      expect(composed.rects, 1, reason: 'one opaque row is one run');
      final px = await bytesOf(composed.image!);
      expect(rgbaAt(px, 7, 3), [255, 0, 0, 255]);
      expect(rgbaAt(px, 7, 4), [0, 0, 0, 0]);
    });

    test('over budget it composes NOTHING and keeps the predecessor for '
        'a later paint — a tile drawn by halves is the ghost again', () async {
      final cache = BitmapTileImageCache();
      final before = tile(red);
      // A checkerboard against solid red: every pixel a run of its own.
      final after = tile(red, paint: (x, y, c) => (x + y).isEven ? blue : c);
      await decode(cache, before);
      TilePredecessors.instance.note(after, before);
      final composed = composePredecessorStandIn(
        cache: cache,
        placed: (coord: TileCoord(x: 0, y: 0), tile: after),
        predecessor: TilePredecessors.instance.of(after)!,
        rectBudget: 10,
      );
      expect(composed.image, isNull);
      expect(composed.rects, 0);
      expect(cache.hasProvisional(after), isFalse);
      expect(TilePredecessors.instance.of(after), isNotNull);
    });

    test('a predecessor whose picture is not on screen declines: the '
        'difference over nothing is a tile missing its base', () {
      final cache = BitmapTileImageCache();
      final before = tile(red); // ink, never decoded
      final after = tile(red, paint: (x, y, c) => y == 0 ? 0 : c);
      TilePredecessors.instance.note(after, before);
      final composed = composePredecessorStandIn(
        cache: cache,
        placed: (coord: TileCoord(x: 0, y: 0), tile: after),
        predecessor: TilePredecessors.instance.of(after)!,
        rectBudget: 1000,
      );
      expect(composed.image, isNull);
      expect(TilePredecessors.instance.of(after), isNotNull);
    });

    test('the first answer sticks, and truth landing drops it — '
        'nothing is left to compose from', () async {
      final cache = BitmapTileImageCache();
      final first = tile(red);
      final second = tile(blue);
      final after = tile(0);
      TilePredecessors.instance.note(after, first);
      TilePredecessors.instance.note(after, second);
      expect(identical(TilePredecessors.instance.of(after)!.tile, first), isTrue);
      await decode(cache, after);
      expect(
        TilePredecessors.instance.of(after),
        isNull,
        reason: 'truth landed, nothing left to compose from',
      );
    });
  });

  group('the painter, on the first paint after a commit', () {
    Future<Uint8List> paintOnce(
      BitmapSurface surface,
      BitmapTileImageCache cache,
    ) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // White under everything, so a transparent pixel reads as white and a
      // pixel the coordinate fallback would have painted red reads as red.
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, size * 1.0, size * 1.0),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      BitmapSurfacePainter(
        surface: surface,
        showTransparentBackground: false,
        tileImageCache: cache,
        // The SAME scope for every generation: this is what arms the
        // coordinate fallback with the previous tile, which is the wrong
        // answer this test proves is no longer reached.
        staleScope: 'cel',
      ).paint(canvas, const Size(size * 1.0, size * 1.0));
      final image = await recorder.endRecording().toImage(size, size);
      return bytesOf(image);
    }

    test('an ERASE is on screen erased, before its decode lands — '
        'the F-68 shape', () async {
      final cache = BitmapTileImageCache();
      final before = tile(red);
      final a = surfaceOf(before);
      await decode(cache, before);
      // First paint: the coordinate fallback's bucket now holds `before`.
      final painted = await paintOnce(a, cache);
      expect(rgbaAt(painted, 0, 5), [255, 0, 0, 255]);

      final after = tile(red, paint: (x, y, c) => (y >= 4 && y < 8) ? 0 : c);
      final b = surfaceOf(after);
      TilePredecessors.instance.noteBetween(a, b);
      // ONE paint, no decode wait: what the user sees on the commit frame.
      final firstFrame = await paintOnce(b, cache);
      expect(
        rgbaAt(firstFrame, 0, 5),
        [255, 255, 255, 255],
        reason: 'the erased rows must NOT show the pre-erase red',
      );
      expect(rgbaAt(firstFrame, 0, 0), [255, 0, 0, 255], reason: 'kept');
    });

    test('over the rect budget, an announced tile is drawn PER PIXEL — '
        'never from the coordinate picture', () async {
      final cache = BitmapTileImageCache();
      final before = tile(red);
      final a = surfaceOf(before);
      await decode(cache, before);
      await paintOnce(a, cache);
      // A checkerboard of erased pixels: 128 runs, against a budget of 2.
      final after = tile(red, paint: (x, y, c) => (x + y).isEven ? 0 : c);
      final b = surfaceOf(after);
      TilePredecessors.instance.noteBetween(a, b);
      final was = BitmapSurfacePainter.debugPredecessorRectBudget;
      BitmapSurfacePainter.debugPredecessorRectBudget = 2;
      addTearDown(() => BitmapSurfacePainter.debugPredecessorRectBudget = was);
      final firstFrame = await paintOnce(b, cache);
      expect(
        cache.hasProvisional(after),
        isFalse,
        reason: 'nothing composed — over budget',
      );
      expect(
        rgbaAt(firstFrame, 0, 0),
        [255, 255, 255, 255],
        reason: 'erased pixel drawn per pixel: white, not the old red',
      );
      expect(rgbaAt(firstFrame, 1, 0), [255, 0, 0, 255], reason: 'kept');
    });

    test('an UNDO to a snapshot that was never decoded is on screen '
        'undone, before its decode lands', () async {
      final cache = BitmapTileImageCache();
      final original = tile(red); // the snapshot: never decoded
      final withStroke = tile(red, paint: (x, y, c) => y == 3 ? blue : c);
      final edited = surfaceOf(withStroke);
      await decode(cache, withStroke);
      expect(rgbaAt(await paintOnce(edited, cache), 0, 3), [0, 0, 255, 255]);

      // `restoreSurfaceSnapshot`: the edited surface is the predecessor of
      // the restored one.
      final restored = surfaceOf(original);
      TilePredecessors.instance.noteBetween(edited, restored);
      final firstFrame = await paintOnce(restored, cache);
      expect(
        rgbaAt(firstFrame, 0, 3),
        [255, 0, 0, 255],
        reason: 'the stroke is undone on the frame the undo lands',
      );
    });
  });
}
