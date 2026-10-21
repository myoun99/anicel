import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/services/media/still_file_writing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The four stills the engine has no encoder for (I-117): each file is read
/// back by a decoder that is not ours — the `image` package's, and where the
/// engine reads the format (BMP, WebP) the engine's too — and must give
/// every pixel back.
void main() {
  /// A picture that walks the writers' edges: an odd width (BMP pads rows
  /// to four bytes), a row longer than a TGA packet (128), runs that meet
  /// across a row's end, and an alpha that is neither 0 nor 255.
  StillPixels picture(int width, int height, {required bool alpha}) {
    final channels = alpha ? 4 : 3;
    final pixels = Uint8List(width * height * channels);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final at = (y * width + x) * channels;
        // Long flat runs that carry over the row's end, then a busy stretch.
        final flat = x < width ~/ 2;
        pixels[at] = flat ? 200 : (x * 37 + y * 11) & 0xFF;
        pixels[at + 1] = flat ? 120 : (x * 13 + y * 7) & 0xFF;
        pixels[at + 2] = flat ? 40 : (x * 5 + y * 3) & 0xFF;
        if (alpha) {
          pixels[at + 3] = flat ? 255 : (x * 9 + y) & 0xFF;
        }
      }
    }
    return (pixels: pixels, width: width, height: height, channels: channels);
  }

  /// Every pixel of [decoded] against [want].
  void expectSamePixels(img.Image? decoded, StillPixels want) {
    expect(decoded, isNotNull);
    final image = decoded!;
    expect((image.width, image.height), (want.width, want.height));
    // A decoder may hand an RGB file back with four channels (the WebP one
    // always does); then its alpha must be whole everywhere.
    for (var y = 0; y < want.height; y += 1) {
      for (var x = 0; x < want.width; x += 1) {
        final at = (y * want.width + x) * want.channels;
        final pixel = image.getPixel(x, y);
        expect(
          [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt(), pixel.a.toInt()],
          [
            ...want.pixels.sublist(at, at + 3),
            if (want.channels == 4) want.pixels[at + 3] else 255,
          ],
          reason: 'pixel ($x, $y)',
        );
      }
    }
  }

  final writers = <String, (Uint8List Function(StillPixels), img.Decoder)>{
    'BMP': (encodeBmp, img.BmpDecoder()),
    'TGA': (encodeTga, img.TgaDecoder()),
    'TIFF': (encodeTiff, img.TiffDecoder()),
    'WebP': (encodeWebp, img.WebPDecoder()),
  };

  for (final MapEntry(key: name, value: (write, decoder)) in writers.entries) {
    group(name, () {
      for (final alpha in [false, true]) {
        final channels = alpha ? 'RGBA' : 'RGB';
        test('$channels — every pixel comes back', () {
          for (final (width, height) in [(1, 1), (7, 5), (301, 9)]) {
            final want = picture(width, height, alpha: alpha);
            expectSamePixels(decoder.decode(write(want)), want);
          }
        });
      }
    });
  }

  group('BMP', () {
    ByteData head(Uint8List file) => ByteData.sublistView(file);

    test('RGB is 24 bits, BI_RGB, with the plain 40-byte header — '
        'BI_BITFIELDS is only defined for 16 and 32 bits', () {
      final file = head(encodeBmp(picture(7, 5, alpha: false)));
      expect(file.getUint32(14, Endian.little), 40);
      expect(file.getUint16(28, Endian.little), 24);
      expect(file.getUint32(30, Endian.little), 0);
    });

    test('RGBA is 32 bits with the alpha named by the V5 header mask', () {
      final file = head(encodeBmp(picture(7, 5, alpha: true)));
      expect(file.getUint32(14, Endian.little), 124);
      expect(file.getUint16(28, Endian.little), 32);
      expect(file.getUint32(30, Endian.little), 3);
      expect(file.getUint32(66, Endian.little), 0xFF000000);
      // sRGB, and the intent field where the V5 header keeps it.
      expect(file.getUint32(70, Endian.little), 0x73524742);
      expect(file.getUint32(122, Endian.little), 4);
    });
  });

  group('TGA', () {
    test('is run-length encoded (type 10) and closed by the 2.0 footer', () {
      final file = encodeTga(picture(301, 9, alpha: true));
      expect(file[2], 10);
      expect(file[16], 32);
      expect(file[17], 8, reason: 'eight bits of alpha, origin bottom-left');
      expect(
        String.fromCharCodes(file.sublist(file.length - 18, file.length - 1)),
        'TRUEVISION-XFILE.',
      );
      expect(file.last, 0);
    });

    test('a flat picture is written smaller than its pixels', () {
      final flat = (
        pixels: Uint8List(640 * 480 * 3),
        width: 640,
        height: 480,
        channels: 3,
      );
      expect(encodeTga(flat).length, lessThan(flat.pixels.length ~/ 50));
    });

    test('🚨no packet runs past its row\'s end, though the colour does — '
        'every row\'s packets add up to exactly its width', () {
      const width = 301;
      const height = 9;
      final file = encodeTga(picture(width, height, alpha: false));
      var at = 18;
      for (var row = 0; row < height; row += 1) {
        var pixels = 0;
        while (pixels < width) {
          final head = file[at];
          final count = (head & 0x7F) + 1;
          at += 1 + ((head & 0x80) != 0 ? 3 : count * 3);
          pixels += count;
        }
        expect(pixels, width, reason: 'row $row');
      }
    });

    test('a side past 65535 is refused — the header cannot name it', () {
      final wide = (
        pixels: Uint8List(65536 * 3),
        width: 65536,
        height: 1,
        channels: 3,
      );
      expect(() => encodeTga(wide), throwsArgumentError);
    });
  });

  group('TIFF', () {
    /// [file]'s first IFD as tag → (count, value-or-offset).
    Map<int, (int, int)> tags(Uint8List file) {
      final data = ByteData.sublistView(file);
      final ifd = data.getUint32(4, Endian.little);
      final count = data.getUint16(ifd, Endian.little);
      return {
        for (var i = 0; i < count; i += 1)
          data.getUint16(ifd + 2 + i * 12, Endian.little): (
            data.getUint32(ifd + 2 + i * 12 + 4, Endian.little),
            data.getUint16(ifd + 2 + i * 12 + 2, Endian.little) == 3 &&
                    data.getUint32(ifd + 2 + i * 12 + 4, Endian.little) == 1
                ? data.getUint16(ifd + 2 + i * 12 + 8, Endian.little)
                : data.getUint32(ifd + 2 + i * 12 + 8, Endian.little),
          ),
      };
    }

    test('RGBA marks its fourth channel UNASSOCIATED alpha — the colour is '
        'not premultiplied', () {
      final written = tags(encodeTiff(picture(7, 5, alpha: true)));
      expect(written[277]!.$2, 4);
      expect(written[338], (1, 2));
    });

    test('RGB names no extra sample', () {
      final written = tags(encodeTiff(picture(7, 5, alpha: false)));
      expect(written[277]!.$2, 3);
      expect(written.containsKey(338), isFalse);
    });

    test('is deflated (Adobe Deflate, 8), and a big picture comes in strips '
        'a reader can take one at a time', () {
      final big = picture(400, 300, alpha: true);
      final file = encodeTiff(big);
      final written = tags(file);
      expect(written[259]!.$2, 8);
      expect(written[273]!.$1, greaterThan(1));
      expect(written[279]!.$1, written[273]!.$1);
      expectSamePixels(img.TiffDecoder().decode(file), big);
    });

    test('tags stand in ascending order, as the format requires', () {
      final order = tags(encodeTiff(picture(7, 5, alpha: true))).keys.toList();
      expect(order, [...order]..sort());
    });

    test('every offset it names lands on a word boundary — the directory '
        'and each value kept outside its entry, as TIFF 6.0 asks, and the '
        'strips with them', () {
      final file = encodeTiff(picture(400, 300, alpha: true));
      final data = ByteData.sublistView(file);
      final written = tags(file);
      List<int> longsAt((int, int) entry) => [
        for (var i = 0; i < entry.$1; i += 1)
          data.getUint32(entry.$2 + i * 4, Endian.little),
      ];
      final stripOffsets = longsAt(written[273]!);
      final stripBytes = longsAt(written[279]!);
      expect(
        stripBytes.take(stripBytes.length - 1).any((bytes) => bytes.isOdd),
        isTrue,
        reason: 'the premise: a strip of odd length with another after it',
      );
      expect([
        data.getUint32(4, Endian.little),
        ...stripOffsets,
        written[273]!.$2,
        written[279]!.$2,
        written[258]!.$2,
        written[282]!.$2,
        written[283]!.$2,
      ], everyElement(predicate<int>((offset) => offset.isEven, 'even')));
    });
  });

  group('WebP', () {
    /// The VP8L header's alpha_is_used bit (bit 28 after the 0x2F
    /// signature that follows the RIFF, WEBP and chunk heads).
    bool alphaIsUsed(Uint8List file) {
      expect(file[20], 0x2F);
      return (ByteData.sublistView(file).getUint32(21, Endian.little) >>
              28 &
          1) ==
          1;
    }

    test('is lossless (VP8L) and says it carries alpha only when it does', () {
      final rgb = encodeWebp(picture(7, 5, alpha: false));
      expect(String.fromCharCodes(rgb.sublist(12, 16)), 'VP8L');
      expect(alphaIsUsed(rgb), isFalse);
      expect(alphaIsUsed(encodeWebp(picture(7, 5, alpha: true))), isTrue);
    });
  });

  group('the engine reads them too', () {
    Future<Uint8List> engineRgba(WidgetTester tester, Uint8List file) async {
      final rgba = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(file);
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        frame.image.dispose();
        codec.dispose();
        return Uint8List.sublistView(data!);
      });
      return rgba!;
    }

    /// [picture] with its alpha held to 255 and 128: the engine keeps a
    /// picture premultiplied, so a half-covered colour comes back within a
    /// step or two — the alpha itself, exactly.
    StillPixels twoAlphas(int width, int height, {required bool alpha}) {
      final source = picture(width, height, alpha: alpha);
      if (alpha) {
        for (var at = 3; at < source.pixels.length; at += 4) {
          source.pixels[at] = source.pixels[at] == 255 ? 255 : 128;
        }
      }
      return source;
    }

    for (final MapEntry(key: name, value: write) in {
      'BMP': encodeBmp,
      'WebP': encodeWebp,
    }.entries) {
      for (final alpha in [false, true]) {
        testWidgets('$name ${alpha ? 'RGBA' : 'RGB'}', (tester) async {
          final want = twoAlphas(7, 5, alpha: alpha);
          final got = await engineRgba(tester, write(want));
          for (var p = 0; p < want.width * want.height; p += 1) {
            final from = p * want.channels;
            final cover = alpha ? want.pixels[from + 3] : 255;
            expect(got[p * 4 + 3], cover, reason: 'alpha of pixel $p');
            for (var c = 0; c < 3; c += 1) {
              expect(
                got[p * 4 + c],
                cover == 255
                    ? want.pixels[from + c]
                    : closeTo(want.pixels[from + c], 2),
                reason: 'channel $c of pixel $p',
              );
            }
          }
        });
      }
    }
  });
}
