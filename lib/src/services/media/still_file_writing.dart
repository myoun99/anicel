/// The still files an export writes in the formats the engine has no
/// encoder for: BMP, TGA, TIFF and WebP (I-117 — 유저 2026-10-21: 「새
/// 출력형식으로서 BMP TGA TIFF WEBP」).
///
/// Each writer takes the picture as bytes — rows from the top, three
/// channels (RGB) or four (RGBA, the colour NOT premultiplied) — and gives
/// back the whole file. They run in an isolate of the caller's, so nothing
/// here touches the engine.
///
/// ⚠️BMP, TGA and TIFF are written here rather than through the `image`
/// package's encoders: its BMP marks a 24-bit file BI_BITFIELDS, which the
/// format only defines for 16 and 32 bits; its TGA writes no compression;
/// its TIFF writes no ExtraSamples, so a reader cannot tell a fourth channel
/// is alpha. Its WebP encoder is lossless (VP8L) and round-trips exactly —
/// that one is used.
library;

import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A still picture as the writers take it: [pixels] row by row from the
/// top, [channels] bytes a pixel — 3 (RGB) or 4 (RGBA, straight alpha).
typedef StillPixels = ({
  Uint8List pixels,
  int width,
  int height,
  int channels,
});

/// 72 dots per inch in pixels per metre — what BMP records its resolution
/// in.
const int _pixelsPerMetreAt72Dpi = 2835;

/// [picture] as a BMP: 24 bits a pixel with no alpha (BITMAPINFOHEADER), or
/// 32 with the alpha named by its mask (BITMAPV5HEADER, BI_BITFIELDS) — the
/// header a reader needs to know the fourth byte is alpha. Rows are stored
/// bottom-up, the format's own order.
Uint8List encodeBmp(StillPixels picture) {
  final (:pixels, :width, :height, :channels) = picture;
  final alpha = channels == 4;
  final infoSize = alpha ? 124 : 40;
  final stride = (width * (alpha ? 4 : 3) + 3) & ~3;
  final imageSize = stride * height;
  final offset = 14 + infoSize;
  final out = ByteData(offset + imageSize);
  out
    ..setUint8(0, 0x42) // 'B'
    ..setUint8(1, 0x4D) // 'M'
    ..setUint32(2, offset + imageSize, Endian.little)
    ..setUint32(10, offset, Endian.little)
    ..setUint32(14, infoSize, Endian.little)
    ..setInt32(18, width, Endian.little)
    // Positive: the rows run bottom-up.
    ..setInt32(22, height, Endian.little)
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, alpha ? 32 : 24, Endian.little)
    // BI_BITFIELDS for the masked 32 bits, BI_RGB for 24.
    ..setUint32(30, alpha ? 3 : 0, Endian.little)
    ..setUint32(34, imageSize, Endian.little)
    ..setInt32(38, _pixelsPerMetreAt72Dpi, Endian.little)
    ..setInt32(42, _pixelsPerMetreAt72Dpi, Endian.little);
  if (alpha) {
    out
      ..setUint32(54, 0x00FF0000, Endian.little)
      ..setUint32(58, 0x0000FF00, Endian.little)
      ..setUint32(62, 0x000000FF, Endian.little)
      ..setUint32(66, 0xFF000000, Endian.little)
      // LCS_sRGB: the colours are sRGB, as every picture this app hands out.
      ..setUint32(70, 0x73524742, Endian.little)
      // LCS_GM_IMAGES — the rendering intent BMP gives a picture.
      ..setUint32(122, 4, Endian.little);
  }
  final bytes = out.buffer.asUint8List();
  for (var y = 0; y < height; y += 1) {
    var to = offset + (height - 1 - y) * stride;
    var from = y * width * channels;
    for (var x = 0; x < width; x += 1) {
      bytes[to] = pixels[from + 2];
      bytes[to + 1] = pixels[from + 1];
      bytes[to + 2] = pixels[from];
      if (alpha) {
        bytes[to + 3] = pixels[from + 3];
      }
      to += alpha ? 4 : 3;
      from += channels;
    }
  }
  return bytes;
}

/// The widest side a TGA can name — its header spells sizes in 16 bits.
const int tgaMaxSide = 0xFFFF;

/// [picture] as a run-length compressed TGA (image type 10), 24 bits a
/// pixel or 32 with eight bits of alpha, rows bottom-up (the format's
/// default origin), closed by the TGA 2.0 footer.
///
/// 🗣️유저 2026-10-21 (I-117): 「TGA는 압축을 기본? … 압축 기본하고 옵션안둬도
/// 아무 영향없을거같긴한데」 — compressed, with no option: RLE loses
/// nothing. A packet never runs past its row's end — the 2.0 spec asks
/// that of every writer, and readers count on it.
Uint8List encodeTga(StillPixels picture) {
  final (:pixels, :width, :height, :channels) = picture;
  if (width > tgaMaxSide || height > tgaMaxSide) {
    throw ArgumentError('A TGA side is at most $tgaMaxSide pixels');
  }
  final alpha = channels == 4;
  final depth = alpha ? 4 : 3;
  // ⚠️A COPYING builder: the packets are views of the one [row] every row
  // is laid in, and a builder that kept the views would write the last
  // row's pixels into every row.
  final out = BytesBuilder()
    ..add([
      0, // no image id
      0, // no colour map
      10, // true colour, run-length encoded
      0, 0, 0, 0, 0, // colour map spec
      0, 0, 0, 0, // x and y origin
      width & 0xFF, width >> 8,
      height & 0xFF, height >> 8,
      depth * 8,
      // The alpha bits; origin bits 0 = bottom-left.
      if (alpha) 8 else 0,
    ]);
  final row = Uint8List(width * depth);
  for (var y = height - 1; y >= 0; y -= 1) {
    var from = y * width * channels;
    for (var x = 0; x < width; x += 1) {
      final to = x * depth;
      row[to] = pixels[from + 2];
      row[to + 1] = pixels[from + 1];
      row[to + 2] = pixels[from];
      if (alpha) {
        row[to + 3] = pixels[from + 3];
      }
      from += channels;
    }
    _tgaRowPackets(row, width, depth, out);
  }
  out
    ..add(Uint8List(8)) // no extension area, no developer directory
    ..add('TRUEVISION-XFILE.'.codeUnits)
    ..addByte(0);
  return out.takeBytes();
}

/// One row's pixels ([depth] bytes each) as RLE packets: a run of two or
/// more equal pixels as one repeat packet, everything between runs as raw
/// packets — at most 128 pixels a packet either way.
void _tgaRowPackets(Uint8List row, int width, int depth, BytesBuilder out) {
  bool same(int a, int b) {
    for (var i = 0; i < depth; i += 1) {
      if (row[a * depth + i] != row[b * depth + i]) {
        return false;
      }
    }
    return true;
  }

  var at = 0;
  while (at < width) {
    var run = 1;
    while (at + run < width && run < 128 && same(at, at + run)) {
      run += 1;
    }
    if (run > 1) {
      out
        ..addByte(0x80 | (run - 1))
        ..add(Uint8List.sublistView(row, at * depth, (at + 1) * depth));
      at += run;
      continue;
    }
    final start = at;
    var count = 0;
    while (at < width && count < 128) {
      if (at + 1 < width && same(at, at + 1)) {
        break;
      }
      at += 1;
      count += 1;
    }
    out
      ..addByte(count - 1)
      ..add(Uint8List.sublistView(row, start * depth, at * depth));
  }
}

/// About how many raw bytes a TIFF strip holds before it is deflated — the
/// size libtiff's own writer aims its strips at, so a reader never has to
/// hold the whole picture to read a row.
const int _tiffStripBytes = 64 * 1024;

/// [picture] as a TIFF: 8 bits a channel, RGB or RGBA with the fourth
/// channel marked UNASSOCIATED alpha (ExtraSamples 2 — the colour is not
/// premultiplied), in strips each deflated (Compression 8, Adobe Deflate).
///
/// Deflate loses nothing and every reader we hand pictures to reads it —
/// the same call the TGA's compression made, and with no option either.
Uint8List encodeTiff(StillPixels picture) {
  final (pixels: _, :width, :height, :channels) = picture;
  final rowsPerStrip = (_tiffStripBytes ~/ (width * channels)).clamp(1, height);
  final strips = _deflatedStrips(picture, rowsPerStrip);

  final file = _TiffFile();
  // 'II', 42, and where the directory is — written last.
  file.putAligned(const [0x49, 0x49, 42, 0, 0, 0, 0, 0]);
  final stripOffsets = [for (final strip in strips) file.putAligned(strip)];
  final bitsAt = file.putAligned(_shorts(List<int>.filled(channels, 8)));
  final resolutionAt = file.putAligned(_longs(const [72, 1, 72, 1]));
  // One strip's offset and byte count fit their entries' own value fields;
  // more are written out, and the entries point at them.
  final oneStrip = strips.length == 1;
  final offsets = oneStrip
      ? stripOffsets.single
      : file.putAligned(_longs(stripOffsets));
  final counts = oneStrip
      ? strips.single.length
      : file.putAligned(_longs([for (final strip in strips) strip.length]));

  return file.finish([
    (256, _tiffLong, 1, width),
    (257, _tiffLong, 1, height),
    (258, _tiffShort, channels, bitsAt),
    (259, _tiffShort, 1, 8), // Adobe Deflate
    (262, _tiffShort, 1, 2), // RGB
    (273, _tiffLong, strips.length, offsets),
    (277, _tiffShort, 1, channels),
    (278, _tiffLong, 1, rowsPerStrip),
    (279, _tiffLong, strips.length, counts),
    (282, _tiffRational, 1, resolutionAt),
    (283, _tiffRational, 1, resolutionAt + 8),
    (284, _tiffShort, 1, 1), // chunky: RGBRGB…
    (296, _tiffShort, 1, 2), // the resolution is per inch
    if (channels == 4) (338, _tiffShort, 1, 2), // unassociated alpha
  ]);
}

/// [picture]'s rows, [rowsPerStrip] at a time, each run deflated.
List<Uint8List> _deflatedStrips(StillPixels picture, int rowsPerStrip) {
  final (:pixels, :width, :height, :channels) = picture;
  final rowBytes = width * channels;
  return [
    for (var y = 0; y < height; y += rowsPerStrip)
      Uint8List.fromList(
        ZLibEncoder().convert(
          Uint8List.sublistView(
            pixels,
            y * rowBytes,
            (y + rowsPerStrip).clamp(0, height) * rowBytes,
          ),
        ),
      ),
  ];
}

/// The TIFF field types the directory writes.
const int _tiffShort = 3;
const int _tiffLong = 4;
const int _tiffRational = 5;

/// A little-endian TIFF being laid down: every offset it names lands on a
/// word boundary, and the header learns where the directory is last.
class _TiffFile {
  final BytesBuilder _out = BytesBuilder(copy: false);
  int _at = 0;

  /// Lays [bytes] at the next word boundary, and says where they start.
  int putAligned(List<int> bytes) {
    if (_at.isOdd) {
      _out.addByte(0);
      _at += 1;
    }
    final start = _at;
    _out.add(bytes);
    _at += bytes.length;
    return start;
  }

  /// The file, ended by its one directory: each entry its tag, type, count,
  /// and its value — or, where the values do not fit four bytes, where they
  /// are.
  Uint8List finish(List<(int, int, int, int)> entries) {
    final ifd = ByteData(2 + entries.length * 12 + 4)
      ..setUint16(0, entries.length, Endian.little);
    for (final (i, (tag, type, count, value)) in entries.indexed) {
      final entry = 2 + i * 12;
      ifd
        ..setUint16(entry, tag, Endian.little)
        ..setUint16(entry + 2, type, Endian.little)
        ..setUint32(entry + 4, count, Endian.little);
      // One SHORT sits in the value field's first two bytes.
      if (type == _tiffShort && count == 1) {
        ifd.setUint16(entry + 8, value, Endian.little);
      } else {
        ifd.setUint32(entry + 8, value, Endian.little);
      }
    }
    final ifdAt = putAligned(ifd.buffer.asUint8List());
    final bytes = _out.takeBytes();
    ByteData.sublistView(bytes).setUint32(4, ifdAt, Endian.little);
    return bytes;
  }
}

Uint8List _shorts(List<int> values) {
  final data = ByteData(values.length * 2);
  for (var i = 0; i < values.length; i += 1) {
    data.setUint16(i * 2, values[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

Uint8List _longs(List<int> values) {
  final data = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i += 1) {
    data.setUint32(i * 4, values[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

/// [picture] as a lossless WebP (VP8L), through the `image` package's
/// encoder — with an alpha channel only when [picture] has one.
Uint8List encodeWebp(StillPixels picture) => img.WebPEncoder().encode(
  img.Image.fromBytes(
    width: picture.width,
    height: picture.height,
    bytes: picture.pixels.buffer,
    bytesOffset: picture.pixels.offsetInBytes,
    numChannels: picture.channels,
    rowStride: picture.width * picture.channels,
  ),
);
