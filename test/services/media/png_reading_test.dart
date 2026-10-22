import 'dart:typed_data';

import 'package:anicel/src/services/media/png_reading.dart';
import 'package:anicel/src/services/media/png_writing.dart' show pngChunk;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../helpers/engine_pixels.dart';

/// What [readPngRows] reads of [png], the rows laid one after another.
Uint8List readRgba(Uint8List png) {
  final header = readPngHeader(png)!;
  final out = Uint8List(header.width * header.height * 4);
  var next = 0;
  readPngRows(png, (y, row) {
    expect(y, next, reason: 'rows arrive top to bottom');
    next += 1;
    out.setRange(y * row.length, (y + 1) * row.length, row);
  });
  expect(next, header.height);
  return out;
}

const int w = 37;
const int h = 23;

/// A picture whose every pixel differs from its neighbours, and part of it
/// clear and part half clear where it has alpha.
img.Image picture({
  required int channels,
  img.Format format = img.Format.uint8,
}) {
  final image = img.Image(
    width: w,
    height: h,
    numChannels: channels,
    format: format,
  );
  final top = image.maxChannelValue.toInt();
  for (final p in image) {
    final x = p.x;
    final y = p.y;
    final colour = [
      (x * 7 + y * 13) * top ~/ 300 % (top + 1),
      (x * 3 + y * 29) * top ~/ 500 % (top + 1),
      (x * 11 + y * 5) * top ~/ 400 % (top + 1),
    ];
    final alpha = x < 5
        ? 0
        : y < 6
        ? top ~/ 2 + 1
        : top;
    final values = switch (channels) {
      1 => [colour[0]],
      2 => [colour[0], alpha],
      3 => colour,
      _ => [...colour, alpha],
    };
    for (var c = 0; c < channels; c += 1) {
      p[c] = values[c];
    }
  }
  return image;
}

/// A picture of palette indices: [bits] to an index, the palette's entries
/// partly clear.
img.Image indexed(img.Format format) {
  final image = img.Image(
    width: w,
    height: h,
    format: format,
    withPalette: true,
    numChannels: 4,
  );
  final colours = 1 << image.bitsPerChannel;
  for (var i = 0; i < colours; i += 1) {
    image.palette!.setRgba(
      i,
      i * 53 % 256,
      i * 97 % 256,
      i * 31 % 256,
      i == 1 ? 0 : (i == 2 ? 128 : 255),
    );
  }
  for (var y = 0; y < h; y += 1) {
    for (var x = 0; x < w; x += 1) {
      image.setPixelR(x, y, (x + y * 3) % colours);
    }
  }
  return image;
}

/// [png] with a tRNS chunk of [data] laid right after its header.
Uint8List withTransparency(Uint8List png, List<int> data) => Uint8List.fromList([
  ...png.sublist(0, 33),
  ...pngChunk('tRNS', data),
  ...png.sublist(33),
]);

void main() {
  group('🎯every PNG the engine reads, read a row at a time — the same '
      'pixels', () {
    for (final filter in img.PngFilter.values) {
      test('RGBA, 8 bits, under ${filter.name}', () async {
        final png = img.encodePng(picture(channels: 4), filter: filter);
        expectSamePixels(readRgba(png), await engineRgba(png));
      });
      test('RGB, 8 bits, under ${filter.name}', () async {
        final png = img.encodePng(picture(channels: 3), filter: filter);
        expectSamePixels(readRgba(png), await engineRgba(png));
      });
    }

    for (final (name, channels) in [
      ('grey', 1),
      ('grey and alpha', 2),
      ('RGB', 3),
      ('RGBA', 4),
    ]) {
      test('$name, 16 bits', () async {
        final png = img.encodePng(
          picture(channels: channels, format: img.Format.uint16),
        );
        expect(readPngHeader(png)!.bitDepth, 16);
        expectSamePixels(readRgba(png), await engineRgba(png));
      });
    }

    for (final format in [
      img.Format.uint1,
      img.Format.uint2,
      img.Format.uint4,
      img.Format.uint8,
    ]) {
      test('grey, ${format.name}', () async {
        final png = img.encodePng(picture(channels: 1, format: format));
        expect(readPngHeader(png)!.colourType, 0);
        expectSamePixels(readRgba(png), await engineRgba(png));
      });
      test('indexed, ${format.name}, its palette partly clear', () async {
        final png = img.encodePng(indexed(format));
        expect(readPngHeader(png)!.colourType, 3);
        expectSamePixels(readRgba(png), await engineRgba(png));
      });
    }

    test('RGB with one colour made clear (tRNS)', () async {
      final source = picture(channels: 3);
      final key = source.getPixel(9, 9);
      final png = withTransparency(img.encodePng(source), [
        0,
        key.r.toInt(),
        0,
        key.g.toInt(),
        0,
        key.b.toInt(),
      ]);
      final ours = readRgba(png);
      expect(ours[(9 * w + 9) * 4 + 3], 0, reason: 'the key colour is clear');
      expectSamePixels(ours, await engineRgba(png));
    });

    test('grey with one value made clear (tRNS)', () async {
      final source = picture(channels: 1);
      final key = source.getPixel(4, 4).r.toInt();
      final png = withTransparency(img.encodePng(source), [0, key]);
      final ours = readRgba(png);
      expect(ours[(4 * w + 4) * 4 + 3], 0, reason: 'the key value is clear');
      expectSamePixels(ours, await engineRgba(png));
    });
  });

  test('a clear pixel is all zero, as the engine hands one back', () {
    final png = img.encodePng(picture(channels: 4));
    final ours = readRgba(png);
    expect(ours.sublist(0, 4), [0, 0, 0, 0]);
  });

  test('an interlaced PNG is not read a row at a time', () {
    final png = img.encodePng(picture(channels: 4));
    png[28] = 1;
    expect(() => readPngRows(png, (_, _) {}), throwsUnsupportedError);
  });

  test('a PNG cut short says so', () {
    final png = img.encodePng(picture(channels: 4), level: 0);
    final cut = png.sublist(0, png.length ~/ 2);
    expect(() => readPngRows(cut, (_, _) {}), throwsFormatException);
  });

  test('bytes that are not a PNG have no header', () {
    expect(readPngHeader(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
