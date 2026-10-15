import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/services/media/png_writing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/png_chunks.dart';

/// The pieces every PNG this app writes itself is made of (F-335 made the
/// third writer). What they promise is a file the engine's own codec reads
/// back byte for byte, its rows under the filters libpng's guess picks.
void main() {
  const width = 8;
  const height = 6;
  const stride = width * 3;

  /// Rows that each want one filter, by the least sum of bytes read as
  /// signed: 0 black (every filter ties at nothing) · 1 a ramp (left
  /// predicts it) · 2 the ramp again (up does) · 3 each byte the mean of its
  /// left and its up · 5 stripes under stripes on the left, one flat value
  /// after another on the right (only Paeth's choice of neighbour reads
  /// both). Row 4 sets row 5 up and wants whatever it wants.
  Uint8List picture() {
    final rows = List.generate(height, (_) => Uint8List(stride));
    for (var x = 0; x < width; x += 1) {
      for (var c = 0; c < 3; c += 1) {
        rows[1][x * 3 + c] = 20 * x + 3 * c;
      }
    }
    rows[2].setAll(0, rows[1]);
    for (var i = 0; i < stride; i += 1) {
      final left = i < 3 ? 0 : rows[3][i - 3];
      rows[3][i] = (left + rows[2][i]) >> 1;
    }
    for (var x = 0; x < width; x += 1) {
      for (var c = 0; c < 3; c += 1) {
        final stripe = 50 + 30 * x + c;
        rows[4][x * 3 + c] = x < 4 ? stripe : 100;
        rows[5][x * 3 + c] = x < 4 ? stripe : 160;
      }
    }
    final pixels = Uint8List(height * stride);
    for (var y = 0; y < height; y += 1) {
      pixels.setAll(y * stride, rows[y]);
    }
    return pixels;
  }

  Uint8List rgbPng(Uint8List pixels, {required bool filtered}) {
    final data = PngImageData(
      width: width,
      bytesPerPixel: 3,
      filtered: filtered,
    );
    for (var y = 0; y < height; y += 1) {
      data.add(Uint8List.sublistView(pixels, y * stride, (y + 1) * stride));
    }
    return encodeStillPng(
      width: width,
      height: height,
      colourType: pngRgb,
      imageData: data.finish(),
    );
  }

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

  test('🎯each row goes under the filter that leaves it smallest — and every '
      'filter\'s arithmetic reads back exact', () async {
    final pixels = picture();
    final png = rgbPng(pixels, filtered: true);

    expect(pngColourTypeOf(png), pngRgb, reason: 'three channels, no alpha');
    expect(pngRowFiltersOf(png, stride: stride), [0, 1, 2, 3, anything, 4]);
    expect(await decoded(png), opaque(pixels));
  });

  test('unfiltered, every row is under filter 0 — and reads back '
      'exact', () async {
    final pixels = picture();
    final png = rgbPng(pixels, filtered: false);

    expect(pngRowFiltersOf(png, stride: stride), List.filled(height, 0));
    expect(await decoded(png), opaque(pixels));
  });

  test('a row of another length is refused', () {
    final data = PngImageData(width: width, bytesPerPixel: 3);
    expect(() => data.add(Uint8List(stride - 1)), throwsArgumentError);
  });
}
