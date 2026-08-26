import 'dart:io';
import 'dart:typed_data';

import '../../models/import/tvpp_parse.dart';

/// Decodes one .tvpp image slot to straight (un-premultiplied) RGBA.
///
/// The pixel side of the format, verified pixel-perfect against
/// TVPaint's own PNG export of the same clip (376/376 images, spec in
/// memory `tvpp-format-notes`):
///
///  * Storage pixels are **premultiplied BGRA**, and the premultiply
///    rounds UP: `p = (v·a + 254) ~/ 255`. Grayscale ink hides a channel
///    swap, so any change here must be re-verified on a COLOUR layer.
///  * Rows are PackBits: byte `c >= 0x80` runs the next 4-byte pixel
///    `257 - c` times, `c < 0x80` copies `c + 1` literal pixels. A run
///    never crosses a row boundary.
///  * `DBOD` records are the whole canvas, row by row.
///  * `SRAW` type-64 records are a 96×67 thumbnail, a table of
///    `(totalTiles, X)` pairs, then 64×64 tiles in row-major order (edge
///    tiles truncated). Two tile encodings exist, selected by X:
///      X > 0: tile 0 is X bytes of bare rows; after that each tile is a
///        12-byte copy marker `(0, 0, srcTile)` or `u32 size` + rows.
///      X == 0: every tile is a 12-byte record `(a, anchor, c)`; `c == 0`
///        is empty, `c > 0` starts a chain — the c bytes belong to the
///        NEXT tile, then `u32 size` continues tile-by-tile until a zero.
///  * v12 wraps records in a zlib chain (64KB blocks); v11 stores them
///    raw. [decodeTvppSlotRgba] handles both via [TvppSlot.compressed].
class TvppRasterDecodeException implements Exception {
  const TvppRasterDecodeException(this.message);

  final String message;

  @override
  String toString() => 'TvppRasterDecodeException: $message';
}

/// Straight RGBA bytes (width × height × 4) for [slot], or null for a
/// hold slot (no image there by definition).
Uint8List? decodeTvppSlotRgba({
  required Uint8List fileBytes,
  required TvppSlot slot,
  required int width,
  required int height,
}) {
  if (slot.kind == TvppSlotKind.hold) {
    return null;
  }
  final Uint8List record;
  if (slot.compressed) {
    record = _reassembleZchk(fileBytes, slot.chunkOffset, slot.chunkLength);
  } else {
    // v11 stores the record body as a bare chunk payload — its magic and
    // length live in the CHUNK header the parser already consumed.
    // Re-synthesize them so both wrappers hand the decoder the same
    // record shape (offsets in the tiled reader count from the magic).
    final body = Uint8List.sublistView(
      fileBytes,
      slot.chunkOffset,
      slot.chunkOffset + slot.chunkLength,
    );
    record = Uint8List(8 + body.length);
    record.setAll(0, (slot.v11WholeCanvas ? 'DBOD' : 'SRAW').codeUnits);
    ByteData.sublistView(record, 4, 8).setUint32(0, body.length);
    record.setAll(8, body);
  }
  final premul = _decodeRecord(record, width, height);
  return _straightRgba(premul, width, height);
}

// ---------------------------------------------------------------------------
// v12 ZCHK reassembly
// ---------------------------------------------------------------------------

/// A ZCHK payload is `'SRAW' u32 total-8 | 'czmp' u32 | u32 blocks |
/// u32 100 | u32 blockRaw | u32 blockComp | zlib × blocks` — the streams
/// simply follow one another. Dart's ZLibDecoder stops at each stream's
/// end but does not report how many bytes it consumed, so the next
/// stream is found by scanning for the next valid zlib header and
/// letting a failed inflate reject false positives.
Uint8List _reassembleZchk(Uint8List bytes, int offset, int length) {
  final end = offset + length;
  if (length < 32) {
    throw const TvppRasterDecodeException('ZCHK 페이로드가 너무 짧다.');
  }
  final expected = ByteData.sublistView(bytes, offset + 4, offset + 8)
          .getUint32(0) +
      8;
  final out = BytesBuilder(copy: false);
  var p = offset + 32;
  while (out.length < expected && p < end - 1) {
    var found = false;
    for (var q = p; q < end - 1; q++) {
      if (bytes[q] != 0x78 || (bytes[q] * 256 + bytes[q + 1]) % 31 != 0) {
        continue;
      }
      try {
        out.add(
          ZLibDecoder().convert(Uint8List.sublistView(bytes, q, end)),
        );
        p = q + 8;
        found = true;
        break;
      } on Object {
        continue;
      }
    }
    if (!found) {
      break;
    }
  }
  final data = out.toBytes();
  if (data.length < expected) {
    throw TvppRasterDecodeException(
      'ZCHK 재조립 실패: ${data.length}/$expected 바이트.',
    );
  }
  return Uint8List.sublistView(data, 0, expected);
}

// ---------------------------------------------------------------------------
// PackBits + tile assembly (premultiplied BGRA words, one per pixel)
// ---------------------------------------------------------------------------

class _PackBits {
  _PackBits(this.data, this.at);

  final Uint8List data;
  int at;

  /// Decodes exactly [count] pixels into [out] (32-bit words) through
  /// [place] — or just consumes them when [out] is null.
  void take(int count, Uint32List? out, int Function(int nth)? place) {
    var got = 0;
    while (got < count) {
      if (at >= data.length) {
        throw const TvppRasterDecodeException('레코드가 끝났는데 행이 남았다.');
      }
      final c = data[at];
      if (c >= 0x80) {
        final run = 257 - c;
        if (at + 5 > data.length) {
          throw const TvppRasterDecodeException('런 레코드가 잘렸다.');
        }
        if (out != null) {
          final v = (data[at + 1] << 24) |
              (data[at + 2] << 16) |
              (data[at + 3] << 8) |
              data[at + 4];
          for (var k = 0; k < run && got + k < count; k++) {
            final i = place!(got + k);
            if (i >= 0) {
              out[i] = v;
            }
          }
        }
        got += run;
        at += 5;
      } else {
        final literal = c + 1;
        if (at + 1 + literal * 4 > data.length) {
          throw const TvppRasterDecodeException('리터럴 레코드가 잘렸다.');
        }
        if (out != null) {
          for (var k = 0; k < literal && got + k < count; k++) {
            final q = at + 1 + k * 4;
            final i = place!(got + k);
            if (i >= 0) {
              out[i] = (data[q] << 24) |
                  (data[q + 1] << 16) |
                  (data[q + 2] << 8) |
                  data[q + 3];
            }
          }
        }
        got += literal;
        at += 1 + literal * 4;
      }
    }
    if (got != count) {
      throw const TvppRasterDecodeException('런이 행 경계를 넘었다.');
    }
  }
}

Uint32List _decodeRecord(Uint8List record, int width, int height) {
  if (record.length < 8) {
    throw const TvppRasterDecodeException('레코드가 너무 짧다.');
  }
  final magic = String.fromCharCodes(record, 0, 4);
  if (magic == 'DBOD') {
    return _decodeWholeCanvas(record, width, height);
  }
  if (magic == 'SRAW') {
    return _decodeTiled(record, width, height);
  }
  throw TvppRasterDecodeException('알 수 없는 래스터 매직 «$magic».');
}

Uint32List _decodeWholeCanvas(Uint8List record, int width, int height) {
  final img = Uint32List(width * height);
  final pb = _PackBits(record, 8);
  for (var y = 0; y < height; y++) {
    final row = y * width;
    pb.take(width, img, (nth) => row + nth);
  }
  return img;
}

Uint32List _decodeTiled(Uint8List record, int width, int height) {
  const tile = 64;
  final cols = (width + tile - 1) ~/ tile;
  final rows = (height + tile - 1) ~/ tile;
  final total = cols * rows;
  final img = Uint32List(width * height);

  final pb = _PackBits(record, 24)..take(96 * 67, null, null); // thumbnail

  // Table: (totalTiles, X) pairs — count varies per file; read while the
  // first word matches.
  var x = -1;
  while (pb.at + 8 <= record.length &&
      ByteData.sublistView(record, pb.at, pb.at + 4).getUint32(0) == total) {
    x = ByteData.sublistView(record, pb.at + 4, pb.at + 8).getUint32(0);
    pb.at += 8;
  }
  if (x < 0) {
    throw const TvppRasterDecodeException('타일 표가 없다.');
  }

  void tileRows(int t, int declaredSize) {
    final tr = t ~/ cols, tc = t % cols;
    final tw = tc == cols - 1 ? width - tc * tile : tile;
    final th = tr == rows - 1 ? height - tr * tile : tile;
    final from = pb.at;
    for (var y = 0; y < th; y++) {
      final gy = tr * tile + y;
      final gx0 = tc * tile;
      pb.take(tw, img, (nth) => gy * width + gx0 + nth);
    }
    if (pb.at - from != declaredSize) {
      throw TvppRasterDecodeException(
        '타일 $t 크기 불일치: ${pb.at - from} ≠ $declaredSize.',
      );
    }
  }

  void copyTile(int dst, int src) {
    if (dst == src || src < 0 || src >= total) {
      return;
    }
    final dr = dst ~/ cols, dc = dst % cols;
    final sr = src ~/ cols, sc = src % cols;
    final tw = dc == cols - 1 ? width - dc * tile : tile;
    final th = dr == rows - 1 ? height - dr * tile : tile;
    for (var y = 0; y < th; y++) {
      final gy = dr * tile + y, sy = sr * tile + y;
      if (sy >= height) {
        continue;
      }
      for (var xx = 0; xx < tw; xx++) {
        final gx = dc * tile + xx, sx = sc * tile + xx;
        if (gx < width && sx < width) {
          img[gy * width + gx] = img[sy * width + sx];
        }
      }
    }
  }

  if (x > 0) {
    tileRows(0, x);
    for (var t = 1; t < total; t++) {
      if (pb.at + 12 <= record.length) {
        final v = ByteData.sublistView(record, pb.at, pb.at + 12);
        if (v.getUint32(0) == 0 && v.getUint32(4) == 0 && v.getUint32(8) < total) {
          copyTile(t, v.getUint32(8));
          pb.at += 12;
          continue;
        }
      }
      if (pb.at + 4 > record.length) {
        throw const TvppRasterDecodeException('타일 크기 필드가 잘렸다.');
      }
      final size =
          ByteData.sublistView(record, pb.at, pb.at + 4).getUint32(0);
      pb.at += 4;
      tileRows(t, size);
    }
  } else {
    var t = 0;
    while (t < total) {
      if (pb.at + 12 > record.length) {
        break; // the encoder truncates its trailing record — measured.
      }
      final size =
          ByteData.sublistView(record, pb.at + 8, pb.at + 12).getUint32(0);
      pb.at += 12;
      if (size == 0) {
        t += 1;
        continue;
      }
      var ti = t + 1;
      var next = size;
      while (next > 0 && ti < total && pb.at + next <= record.length) {
        tileRows(ti, next);
        ti += 1;
        if (pb.at + 4 > record.length) {
          next = 0;
          break;
        }
        next = ByteData.sublistView(record, pb.at, pb.at + 4).getUint32(0);
        pb.at += 4;
      }
      t = ti;
    }
  }
  return img;
}

// ---------------------------------------------------------------------------
// Premultiplied BGRA → straight RGBA
// ---------------------------------------------------------------------------

/// TVPaint's own PNG export computes `v = ⌊p·255 / a⌋` (the inverse of
/// its ceiling premultiply) — matching it exactly is what made the
/// 376-image comparison land on zero differences.
Uint8List _straightRgba(Uint32List premul, int width, int height) {
  final out = Uint8List(width * height * 4);
  for (var i = 0; i < premul.length; i++) {
    final v = premul[i];
    final a = v & 0xff;
    if (a == 0) {
      continue;
    }
    final b = (v >>> 24) & 0xff;
    final g = (v >>> 16) & 0xff;
    final r = (v >>> 8) & 0xff;
    int un(int p) {
      final s = (p * 255) ~/ a;
      return s > 255 ? 255 : s;
    }

    final o = i * 4;
    out[o] = un(r);
    out[o + 1] = un(g);
    out[o + 2] = un(b);
    out[o + 3] = a;
  }
  return out;
}
