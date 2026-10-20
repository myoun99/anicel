/// The pieces of every PNG this app writes itself: the animated piece a
/// trimmed moving picture is carried as (`encodeAnimatedPng`) and the still
/// an export writes without an alpha channel (F-335).
///
/// ↩️The animated writer held them for itself, and the sRGB stamp framed its
/// chunks a second time. The still without alpha was the third writer, so
/// they are spelled here once.
library;

import 'dart:convert' show ByteConversionSink;
import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import '../persistence/anicel_incremental_writer.dart'
    show anicelCrc32Finish, anicelCrc32Start, anicelCrc32Update;

/// The eight bytes a PNG file opens with.
const List<int> pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// IHDR colour types: three channels, one palette index, four channels.
const int pngRgb = 2;
const int pngIndexed = 3;
const int pngRgba = 6;

/// IHDR of an 8-bit, uninterlaced [width] × [height] picture whose pixels
/// are of [colourType] ([pngRgb], [pngIndexed] or [pngRgba]).
Uint8List pngHeader({
  required int width,
  required int height,
  required int colourType,
}) => pngChunk('IHDR', [
  ...pngUint32(width),
  ...pngUint32(height),
  8, // bit depth
  colourType,
  0, 0, 0, // compression, filter, interlace
]);

/// A still picture: [imageData] (a finished [PngImageData]) as its one IDAT.
Uint8List encodeStillPng({
  required int width,
  required int height,
  required int colourType,
  required Uint8List imageData,
}) =>
    (BytesBuilder(copy: false)
          ..add(pngSignature)
          ..add(pngHeader(width: width, height: height, colourType: colourType))
          ..add(pngChunk('IDAT', imageData))
          ..add(pngChunk('IEND', const [])))
        .takeBytes();

/// A PNG chunk: length, type, [data] — led by [sequence] when there is one
/// (an fdAT's number) — and the CRC over all of it but the length.
///
/// ⚠️Folded piece by piece, never spread into one list: a frame's pixels
/// are megabytes, and a literal that spread them would build a list of that
/// many boxed integers to checksum it.
Uint8List pngChunk(String type, List<int> data, {int? sequence}) {
  final parts = [
    Uint8List.fromList(type.codeUnits),
    if (sequence != null) pngUint32(sequence),
    if (data is Uint8List) data else Uint8List.fromList(data),
  ];
  var crc = anicelCrc32Start;
  var length = 0;
  for (final part in parts.skip(1)) {
    length += part.length;
  }
  for (final part in parts) {
    crc = anicelCrc32Update(crc, part);
  }
  final out = BytesBuilder(copy: false)..add(pngUint32(length));
  for (final part in parts) {
    out.add(part);
  }
  return (out..add(pngUint32(anicelCrc32Finish(crc)))).takeBytes();
}

/// [value] as the four big-endian bytes every PNG number is.
Uint8List pngUint32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

/// One picture's rows, filtered and deflated as they come — the body of its
/// IDAT (or of an animation frame's fdAT). It holds a few rows, never the
/// picture.
///
/// [filtered] puts each row under the filter that leaves it smallest by
/// libpng's guess — the least sum of its bytes read as signed, a tie to the
/// lower filter. Unfiltered, every row is under filter 0: the PNG spec's own
/// advice for a palette.
final class PngImageData {
  PngImageData({
    required int width,
    required this.bytesPerPixel,
    this.filtered = true,
  }) : _stride = width * bytesPerPixel {
    _deflate = ZLibEncoder().startChunkedConversion(
      ByteConversionSink.withCallback(
        (bytes) =>
            _out = bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      ),
    );
  }

  final int bytesPerPixel;
  final bool filtered;
  final int _stride;
  late final ByteConversionSink _deflate;

  /// What [finish] hands back, set when the deflate closes.
  late Uint8List _out;

  /// The row before the one being filtered; null on the first.
  Uint8List? _above;

  /// Each filter's answer for the row being filtered, by filter number.
  late final List<Uint8List> _candidates = [
    for (var type = 0; type < _filterTypes.length; type += 1)
      Uint8List(_stride),
  ];

  /// The byte that leads a row under each filter.
  static final _filterTypes = [
    for (var type = 0; type < 5; type += 1) Uint8List.fromList([type]),
  ];

  /// The next row down: [bytesPerPixel] bytes a pixel, a row's worth.
  void add(Uint8List row) {
    if (row.length != _stride) {
      throw ArgumentError.value(row.length, 'row', 'a row is $_stride bytes');
    }
    if (!filtered) {
      _deflate
        ..add(_filterTypes[0])
        ..add(row);
      return;
    }
    var best = 0;
    var bestCost = _filter(0, row);
    for (var type = 1; type < _filterTypes.length; type += 1) {
      final cost = _filter(type, row);
      if (cost < bestCost) {
        bestCost = cost;
        best = type;
      }
    }
    _deflate
      ..add(_filterTypes[best])
      ..add(_candidates[best]);
    (_above ??= Uint8List(_stride)).setAll(0, row);
  }

  /// The deflated rows; nothing more can be added.
  Uint8List finish() {
    _deflate.close();
    return _out;
  }

  /// [row] under filter [type] into its candidate, and what that costs.
  ///
  /// ⚠️One loop a filter, not one predictor switched per byte: this runs
  /// five times over every byte of the picture (measured 10-11, a 2436×1678
  /// RGB picture compiled ahead of time: about 100 ms, against 145–170 ms
  /// switched).
  int _filter(int type, Uint8List row) {
    final into = _candidates[type];
    final above = _above;
    final bpp = bytesPerPixel;
    var cost = 0;
    switch (type) {
      case 0:
        for (var i = 0; i < _stride; i += 1) {
          final f = row[i];
          into[i] = f;
          cost += f < 128 ? f : 256 - f;
        }
      case 1:
        for (var i = 0; i < _stride; i += 1) {
          final f = (row[i] - (i < bpp ? 0 : row[i - bpp])) & 0xFF;
          into[i] = f;
          cost += f < 128 ? f : 256 - f;
        }
      case 2:
        for (var i = 0; i < _stride; i += 1) {
          final f = (row[i] - (above == null ? 0 : above[i])) & 0xFF;
          into[i] = f;
          cost += f < 128 ? f : 256 - f;
        }
      case 3:
        for (var i = 0; i < _stride; i += 1) {
          final left = i < bpp ? 0 : row[i - bpp];
          final up = above == null ? 0 : above[i];
          final f = (row[i] - ((left + up) >> 1)) & 0xFF;
          into[i] = f;
          cost += f < 128 ? f : 256 - f;
        }
      default:
        for (var i = 0; i < _stride; i += 1) {
          final left = i < bpp ? 0 : row[i - bpp];
          final up = above == null ? 0 : above[i];
          final upLeft = above == null || i < bpp ? 0 : above[i - bpp];
          final f = (row[i] - pngPaeth(left, up, upLeft)) & 0xFF;
          into[i] = f;
          cost += f < 128 ? f : 256 - f;
        }
    }
    return cost;
  }
}

/// The Paeth predictor: of [a] (left), [b] (up) and [c] (up-left), the one
/// nearest to a + b − c, ties to the earlier — what a row is filtered by
/// here, and unfiltered by when one is read (`readPngRows`).
int pngPaeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) {
    return a;
  }
  return pb <= pc ? b : c;
}
