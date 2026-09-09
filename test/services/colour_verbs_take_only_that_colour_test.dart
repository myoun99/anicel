import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/cel_pixel_overwrite.dart';

/// 색 삭제 / 색 남기기 — the button half of I-8. 유저 2026-08-27 (I-8-Q2):
/// 「허용차 설정 없애고 색이 같을때만 삭제하면 필요없을거같은데」, so these
/// match EXACTLY and the graded version is the effect.
void main() {
  const canvas = CanvasSize(width: 512, height: 512);
  final origin = TileCoord(x: 0, y: 0);
  const black = 0xFF000000;

  BitmapSurface surfaceWith(Map<(int, int), List<int>> pixels) {
    final bytes = Uint8List(256 * 256 * 4);
    for (final entry in pixels.entries) {
      final offset = ((entry.key.$2 * 256) + entry.key.$1) * 4;
      bytes.setRange(offset, offset + 4, entry.value);
    }
    return BitmapSurface(
      canvasSize: canvas,
      tileSize: 256,
      tiles: {
        origin: BitmapTile(size: 256, pixels: bytes),
      },
    );
  }

  List<int> pixelAt(BitmapSurface surface, int x, int y) {
    final offset = ((y * 256) + x) * 4;
    return surface
        .tileAt(origin)!
        .readPixels((_, view) => List<int>.from(view.sublist(offset, offset + 4)));
  }

  /// The whole tile, no mask — the "범위는 전체" case.
  void wholeTile(void Function(TileCoord coord, Uint8List? mask) visit) =>
      visit(origin, null);

  ({BitmapSurface surface, CelPixelRestore? restore}) run(
    BitmapSurface surface,
    CelPixelVerb verb, {
    int argb = black,
  }) => overwriteCelPixels(
    surface: surface,
    channel: verb.channel,
    walk: wholeTile,
    value: Uint8List.fromList([0]),
    selector: verb.selectorFor(argb),
  );

  test('색 삭제 empties only the pixels that ARE that colour', () {
    final before = surfaceWith({
      (0, 0): [0, 0, 0, 255], // the key colour
      (1, 0): [10, 20, 30, 255], // something else
      (2, 0): [1, 0, 0, 255], // ONE off — tolerance is 0
    });
    final after = run(before, CelPixelVerb.deleteColour).surface;
    expect(pixelAt(after, 0, 0)[3], 0);
    expect(pixelAt(after, 1, 0), [10, 20, 30, 255]);
    expect(
      pixelAt(after, 2, 0)[3],
      255,
      reason: 'the button matches exactly — a near colour is the fx\'s job',
    );
  });

  test('색 남기기 empties everything that is NOT that colour', () {
    final before = surfaceWith({
      (0, 0): [0, 0, 0, 255],
      (1, 0): [10, 20, 30, 255],
    });
    final after = run(before, CelPixelVerb.keepColour).surface;
    expect(pixelAt(after, 0, 0)[3], 255);
    expect(pixelAt(after, 1, 0)[3], 0);
  });

  test('the colour bytes survive under the zeroed alpha', () {
    final before = surfaceWith({
      (0, 0): [0, 0, 0, 255],
    });
    final after = run(before, CelPixelVerb.deleteColour).surface;
    // ★This is what makes the undo below sound: the selector reads R, G and
    // B, and an alpha write leaves them exactly as they were.
    expect(pixelAt(after, 0, 0).sublist(0, 3), [0, 0, 0]);
  });

  test('undo puts every pixel back, because the selector re-picks the same '
      'ones', () {
    final before = surfaceWith({
      (0, 0): [0, 0, 0, 255],
      (1, 0): [0, 0, 0, 128], // same colour, softer edge
      (2, 0): [10, 20, 30, 200], // untouched
      (3, 0): [0, 0, 0, 0], // already empty, must not be "restored" to ink
    });
    final forward = run(before, CelPixelVerb.deleteColour);
    expect(forward.restore, isNotNull);
    final undone = overwriteCelPixels(
      surface: forward.surface,
      channel: CelPixelVerb.deleteColour.channel,
      walk: wholeTile,
      restore: forward.restore,
      selector: CelPixelVerb.deleteColour.selectorFor(black),
    ).surface;
    for (final x in [0, 1, 2, 3]) {
      expect(
        pixelAt(undone, x, 0),
        pixelAt(before, x, 0),
        reason: 'pixel $x came back exactly',
      );
    }
  });

  test('a verb with no selector still takes everything the mask covers', () {
    final before = surfaceWith({
      (0, 0): [0, 0, 0, 255],
      (1, 0): [10, 20, 30, 255],
    });
    final after = run(before, CelPixelVerb.clearPixels).surface;
    expect(pixelAt(after, 0, 0)[3], 0);
    expect(pixelAt(after, 1, 0)[3], 0);
  });

  test('the verb, not the channel, says which of the two alpha verbs it is',
      () {
    // 색 삭제 and 픽셀 삭제 are BOTH alpha writes of zero — the whole reason
    // the channel stopped being the verb.
    expect(CelPixelVerb.deleteColour.channel, CelPixelVerb.clearPixels.channel);
    expect(CelPixelVerb.deleteColour.selectsByColour, isTrue);
    expect(CelPixelVerb.clearPixels.selectsByColour, isFalse);
    expect(CelPixelVerb.clearPixels.selectorFor(black), isNull);
  });

  test('the selector reads the swatch RGB and ignores its alpha', () {
    final opaque = CelPixelVerb.deleteColour.selectorFor(0xFF102030)!;
    final ghostly = CelPixelVerb.deleteColour.selectorFor(0x00102030)!;
    expect(opaque.matches(0x10, 0x20, 0x30), isTrue);
    expect(ghostly.matches(0x10, 0x20, 0x30), isTrue);
    expect(opaque.tolerance, 0);
  });
}
