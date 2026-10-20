/// A PNG read by the app itself, a row at a time — the reader a picture
/// takes when it is too big for the engine's decoder to hand back whole
/// (`pictureSideLimit`), the counterpart of what `png_writing.dart` writes.
///
/// 🗣️유저 2026-10-18 (a-picture-past-the-texture-limit-is-decoded-squashed
/// -Q1): 「원본 해상도 그대로 — GPU 를 거치지 않는 디코더로 블록씩 읽는다」 ·
/// 「메모리/시간관련 대가는 최대한 개선하면서 해결」. So it holds two rows of
/// the picture, never the picture: rows are inflated (the engine's zlib) and
/// unfiltered as the compressed stream arrives, and each is handed on before
/// the next is read. 🔬A 20000×1080 PNG in `flutter test` on the Surface:
/// the `image` package took 1.6 s and held the picture twice over.
///
/// ⚠️Read as stored: no colour profile (iCCP), no gamma (gAMA) and no EXIF
/// turn is applied — the engine's decoder applies a profile, so a picture
/// of a wide-gamut file can come out a little apart from the same picture
/// small enough for the engine.
library;

import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import '../../core/rgba_premultiply.dart';
import 'png_writing.dart'
    show pngIndexed, pngPaeth, pngRgb, pngRgba, pngSignature;

/// IHDR colour types the writer has no name for: one grey channel, and
/// grey with alpha.
const int _pngGrey = 0;
const int _pngGreyAlpha = 4;

/// What a PNG says of itself before its first row.
typedef PngHeader = ({
  int width,
  int height,
  int bitDepth,
  int colourType,
  bool interlaced,
});

/// The header of [bytes], or null when they are not a PNG.
PngHeader? readPngHeader(Uint8List bytes) {
  if (!_startsLikePng(bytes) || bytes.length < 33) {
    return null;
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(12) != _type('IHDR')) {
    return null;
  }
  return (
    width: data.getUint32(16),
    height: data.getUint32(20),
    bitDepth: bytes[24],
    colourType: bytes[25],
    interlaced: bytes[28] != 0,
  );
}

/// Every row of the PNG [bytes], top to bottom, as straight RGBA8, handed
/// to [row] with its index — a buffer this goes on writing into, so what
/// [row] keeps it copies.
///
/// A pixel left fully clear is all zero, as the engine's decoder hands one
/// back. Throws [UnsupportedError] for an interlaced PNG (its passes do
/// not arrive as rows) and [FormatException] for bytes that do not read.
void readPngRows(
  Uint8List bytes,
  void Function(int y, Uint8List rgba) row,
) {
  final header = readPngHeader(bytes);
  if (header == null) {
    throw const FormatException('Not a PNG.');
  }
  if (header.interlaced) {
    throw UnsupportedError('An interlaced PNG is not read a row at a time.');
  }
  final chunks = _chunksOf(bytes);
  final rows = _PngRows(
    header,
    _Samples.of(header, (name) => _dataOf(bytes, chunks, name)),
    row,
  );
  final inflater = ZLibDecoder().startChunkedConversion(rows);
  for (final chunk in chunks) {
    if (chunk.type == _type('IDAT')) {
      inflater.add(Uint8List.sublistView(bytes, chunk.start, chunk.end));
    }
  }
  inflater.close();
}

bool _startsLikePng(Uint8List bytes) {
  if (bytes.length < pngSignature.length) {
    return false;
  }
  for (var i = 0; i < pngSignature.length; i += 1) {
    if (bytes[i] != pngSignature[i]) {
      return false;
    }
  }
  return true;
}

int _type(String name) =>
    name.codeUnitAt(0) << 24 |
    name.codeUnitAt(1) << 16 |
    name.codeUnitAt(2) << 8 |
    name.codeUnitAt(3);

typedef _Chunk = ({int type, int start, int end});

/// Every chunk of [bytes] up to IEND: its type and where its data lies.
List<_Chunk> _chunksOf(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final chunks = <_Chunk>[];
  var at = pngSignature.length;
  while (at + 8 <= bytes.length) {
    final length = data.getUint32(at);
    final type = data.getUint32(at + 4);
    final start = at + 8;
    final end = start + length;
    if (end + 4 > bytes.length) {
      throw const FormatException('A PNG chunk runs past the file.');
    }
    if (type == _type('IEND')) {
      break;
    }
    chunks.add((type: type, start: start, end: end));
    at = end + 4;
  }
  return chunks;
}

Uint8List? _dataOf(Uint8List bytes, List<_Chunk> chunks, String name) {
  for (final chunk in chunks) {
    if (chunk.type == _type(name)) {
      return Uint8List.sublistView(bytes, chunk.start, chunk.end);
    }
  }
  return null;
}

/// How a row's samples become RGBA8: the palette an indexed picture looks
/// its colours up in, or the one sample value a grey or RGB picture is
/// clear at (tRNS).
final class _Samples {
  _Samples._(this.header, this.palette, this.clear);

  factory _Samples.of(
    PngHeader header,
    Uint8List? Function(String name) chunk,
  ) {
    final transparency = chunk('tRNS');
    if (header.colourType == pngIndexed) {
      return _Samples._(
        header,
        _paletteOf(chunk('PLTE'), transparency, 1 << header.bitDepth),
        null,
      );
    }
    return _Samples._(header, null, _clearOf(header, transparency));
  }

  final PngHeader header;

  /// 256 RGBA entries; past those PLTE gives, opaque black.
  final Uint8List? palette;

  /// The sample values, one a channel, that tRNS makes clear.
  final List<int>? clear;

  /// [raw] — a row's samples, one a channel ([_unpack]) — as RGBA8 in
  /// [rgba].
  void toRgba(Uint16List raw, Uint8List rgba) {
    final palette = this.palette;
    if (palette != null) {
      _indexedToRgba(raw, palette, rgba);
    } else if (_channels(header.colourType) <= 2) {
      _greyToRgba(raw, rgba);
    } else {
      _colourToRgba(raw, rgba);
    }
  }

  /// Palette indices as the colours they look up.
  static void _indexedToRgba(
    Uint16List raw,
    Uint8List palette,
    Uint8List rgba,
  ) {
    for (var x = 0; x < raw.length; x += 1) {
      rgba.setRange(x * 4, x * 4 + 4, palette, raw[x] * 4);
    }
  }

  /// Grey samples — alone, or each with its alpha — clear where tRNS names
  /// the grey.
  void _greyToRgba(Uint16List raw, Uint8List rgba) {
    final depth = header.bitDepth;
    final channels = _channels(header.colourType);
    final key = clear?.first;
    for (var s = 0, o = 0; s < raw.length; s += channels, o += 4) {
      final grey = _to8(raw[s], depth);
      rgba[o] = grey;
      rgba[o + 1] = grey;
      rgba[o + 2] = grey;
      rgba[o + 3] = channels == 2
          ? _to8(raw[s + 1], depth)
          : raw[s] == key
          ? 0
          : 255;
    }
  }

  /// RGB samples — alone, or each with its alpha — clear where tRNS names
  /// the colour.
  void _colourToRgba(Uint16List raw, Uint8List rgba) {
    final depth = header.bitDepth;
    final channels = _channels(header.colourType);
    final key = clear;
    for (var s = 0, o = 0; s < raw.length; s += channels, o += 4) {
      rgba[o] = _to8(raw[s], depth);
      rgba[o + 1] = _to8(raw[s + 1], depth);
      rgba[o + 2] = _to8(raw[s + 2], depth);
      rgba[o + 3] = channels == 4
          ? _to8(raw[s + 3], depth)
          : key != null &&
                raw[s] == key[0] &&
                raw[s + 1] == key[1] &&
                raw[s + 2] == key[2]
          ? 0
          : 255;
    }
  }

  /// As the engine's decoder (libpng) takes them: no more colours than an
  /// index of the picture's depth reaches, and a tRNS longer than those is
  /// no tRNS at all — the image package writes 256 of each at any depth.
  static Uint8List _paletteOf(
    Uint8List? colours,
    Uint8List? alphas,
    int reach,
  ) {
    final palette = Uint8List(256 * 4);
    for (var i = 0; i < 256; i += 1) {
      palette[i * 4 + 3] = 255;
    }
    final given = colours == null ? 0 : colours.length ~/ 3;
    final count = given < reach ? given : reach;
    for (var i = 0; i < count; i += 1) {
      palette[i * 4] = colours![i * 3];
      palette[i * 4 + 1] = colours[i * 3 + 1];
      palette[i * 4 + 2] = colours[i * 3 + 2];
    }
    if (alphas == null || alphas.length > count) {
      return palette;
    }
    for (var i = 0; i < alphas.length; i += 1) {
      palette[i * 4 + 3] = alphas[i];
    }
    return palette;
  }

  /// tRNS of a grey picture is one sample, of an RGB picture three — of any
  /// other length the engine's decoder reads none.
  static List<int>? _clearOf(PngHeader header, Uint8List? transparency) {
    final channels = switch (header.colourType) {
      _pngGrey => 1,
      pngRgb => 3,
      _ => 0,
    };
    if (transparency == null ||
        channels == 0 ||
        transparency.length != channels * 2) {
      return null;
    }
    return [
      for (var c = 0; c < channels; c += 1)
        transparency[c * 2] << 8 | transparency[c * 2 + 1],
    ];
  }
}

/// Rows inflated into place, unfiltered against the row above, and turned
/// into straight RGBA8.
final class _PngRows implements Sink<List<int>> {
  _PngRows(this._header, this._samples, this._row)
    : _rgba = Uint8List(_header.width * 4),
      _raw = Uint16List(_header.width * _channels(_header.colourType)) {
    final bits = _header.bitDepth * _channels(_header.colourType);
    final rowBytes = (_header.width * bits + 7) >> 3;
    _step = bits < 8 ? 1 : bits >> 3;
    _line = Uint8List(rowBytes + 1);
    _above = Uint8List(rowBytes + 1);
  }

  final PngHeader _header;
  final _Samples _samples;
  final void Function(int y, Uint8List rgba) _row;
  final Uint8List _rgba;

  /// A row's samples, one a channel, as numbers ([_unpack]).
  final Uint16List _raw;

  /// The bytes of one whole pixel — what a filter looks back by.
  late final int _step;
  late Uint8List _line;
  late Uint8List _above;
  var _filled = 0;
  var _y = 0;

  @override
  void add(List<int> chunk) {
    var at = 0;
    while (at < chunk.length && _y < _header.height) {
      final room = _line.length - _filled;
      final left = chunk.length - at;
      final take = room < left ? room : left;
      _line.setRange(_filled, _filled + take, chunk, at);
      _filled += take;
      at += take;
      if (_filled == _line.length) {
        _finishLine();
      }
    }
  }

  @override
  void close() {
    if (_y < _header.height) {
      throw const FormatException('A PNG ends before its last row.');
    }
  }

  void _finishLine() {
    _unfilter(_line, _above, _step);
    _toRgba();
    _row(_y, _rgba);
    _y += 1;
    _filled = 0;
    final done = _line;
    _line = _above;
    _above = done;
  }

  /// The row in [_line] as straight RGBA8 in [_rgba] — a pixel left fully
  /// clear all zero ([zeroFullyClearPixels]), as the engine's decoder hands
  /// one back. An RGBA8 picture, the common one, is its bytes as they lie.
  void _toRgba() {
    if (_header.bitDepth == 8 && _header.colourType == pngRgba) {
      _rgba.setRange(0, _rgba.length, _line, 1);
    } else {
      _unpack(_line, _header.bitDepth, _raw);
      _samples.toRgba(_raw, _rgba);
    }
    zeroFullyClearPixels(_rgba);
  }
}

int _channels(int colourType) => switch (colourType) {
  _pngGrey => 1,
  pngRgb => 3,
  pngIndexed => 1,
  _pngGreyAlpha => 2,
  pngRgba => 4,
  _ => throw FormatException('PNG colour type $colourType.'),
};

/// [line] — a filter byte, then a row's bytes — unfiltered in place against
/// [above], the row before it already unfiltered (all zero for the first).
/// [step] is how far back a filter's left neighbour lies.
void _unfilter(Uint8List line, Uint8List above, int step) {
  final filter = line[0];
  final end = line.length;
  switch (filter) {
    case 0:
      return;
    case 1:
      for (var i = 1 + step; i < end; i += 1) {
        line[i] = line[i] + line[i - step];
      }
    case 2:
      for (var i = 1; i < end; i += 1) {
        line[i] = line[i] + above[i];
      }
    case 3:
      for (var i = 1; i < end; i += 1) {
        final left = i > step ? line[i - step] : 0;
        line[i] = line[i] + ((left + above[i]) >> 1);
      }
    case 4:
      for (var i = 1; i < end; i += 1) {
        final left = i > step ? line[i - step] : 0;
        final upLeft = i > step ? above[i - step] : 0;
        line[i] = line[i] + pngPaeth(left, above[i], upLeft);
      }
    default:
      throw FormatException('PNG filter $filter.');
  }
}

/// The samples of [line] (past its filter byte), one a channel, as numbers
/// in [raw] — [depth] bits each, packed as a PNG packs them.
void _unpack(Uint8List line, int depth, Uint16List raw) {
  switch (depth) {
    case 8:
      raw.setRange(0, raw.length, line, 1);
    case 16:
      for (var i = 0; i < raw.length; i += 1) {
        raw[i] = line[1 + i * 2] << 8 | line[2 + i * 2];
      }
    default:
      final top = (1 << depth) - 1;
      for (var i = 0; i < raw.length; i += 1) {
        final bit = i * depth;
        raw[i] = line[1 + (bit >> 3)] >> (8 - depth - (bit & 7)) & top;
      }
  }
}

/// A [depth]-bit sample as eight bits — of sixteen, its high byte, as the
/// engine's decoder keeps it.
int _to8(int sample, int depth) => switch (depth) {
  8 => sample,
  16 => sample >> 8,
  _ => sample * 255 ~/ ((1 << depth) - 1),
};
