import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/services/media/png_writing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/png_chunks.dart';

/// The pieces every PNG this app writes itself is made of (F-335 made the
/// third writer). What they promise is a file the engine's own codec reads
/// back byte for byte. ⛔They put no row under a filter: each that is, is
/// on the engine (`png.wgsl`, whose own tests pin the law) — ↩️the pieces
/// held a Dart twin of it till 2026-11-16, and these tests pinned that.
void main() {
  const width = 8;
  const height = 6;
  const stride = width * 3;

  /// Three channels a pixel, every byte its own of its neighbours'.
  Uint8List picture() => Uint8List.fromList([
    for (var i = 0; i < height * stride; i += 1) (i * 37 + i ~/ stride) & 0xFF,
  ]);

  /// [png] through the engine's codec: each pixel's RGBA.
  Future<Uint8List> decoded(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    image.dispose();
    codec.dispose();
    return Uint8List.sublistView(data!);
  }

  Uint8List opaque(Uint8List rgb) => Uint8List.fromList([
    for (var p = 0; p < rgb.length; p += 3) ...[
      rgb[p],
      rgb[p + 1],
      rgb[p + 2],
      255,
    ],
  ]);

  test('🎯unfiltered, every row is under filter 0 — and reads back '
      'exact', () async {
    final pixels = picture();
    final png = encodeStillPng(
      width: width,
      height: height,
      colourType: pngRgb,
      imageData: pngDeflated(pngUnfiltered(pixels, stride)),
    );

    expect(pngColourTypeOf(png), pngRgb, reason: 'three channels, no alpha');
    expect(pngRowFiltersOf(png, stride: stride), List.filled(height, 0));
    expect(await decoded(png), opaque(pixels));
  });

  /// The reader (`readPngRows`) unfilters by it and the engine filters by
  /// the same predictor (`png.wgsl`), so a tie broken another way reads our
  /// own files back whole and every other encoder's wrong — no round trip
  /// sees it.
  test('Paeth predicts the neighbour nearest a + b - c, a tie going to a, '
      'then b', () {
    expect(pngPaeth(30, 20, 10), 30);
    expect(pngPaeth(20, 10, 30), 10);
    expect(pngPaeth(10, 20, 15), 15);
    expect(pngPaeth(6, 0, 2), 6, reason: 'a and c tie');
    expect(pngPaeth(0, 6, 2), 6, reason: 'b and c tie');
  });
}
