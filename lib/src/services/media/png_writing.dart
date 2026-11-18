/// The pieces of every PNG this app writes itself: the animated piece a
/// trimmed moving picture is carried as (`encodeAnimatedPng`) and the still
/// an export writes without an alpha channel (F-335).
///
/// ↩️The animated writer held them for itself, and the sRGB stamp framed its
/// chunks a second time. The still without alpha was the third writer, so
/// they are spelled here once.
library;

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

/// The type of the chunk every PNG opens with: what [pngHeader] writes and
/// `readPngHeader` looks for first.
const String pngHeaderType = 'IHDR';

/// IHDR of an 8-bit, uninterlaced [width] × [height] picture whose pixels
/// are of [colourType] ([pngRgb], [pngIndexed] or [pngRgba]).
Uint8List pngHeader({
  required int width,
  required int height,
  required int colourType,
}) => pngChunk(pngHeaderType, [
  ...pngUint32(width),
  ...pngUint32(height),
  8, // bit depth
  colourType,
  0, 0, 0, // compression, filter, interlace
]);

/// A still picture: [imageData] (its rows deflated, [pngDeflated]) as its one
/// IDAT.
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

/// [pixels]' rows of [rowBytes], each led by filter 0 — none: what a
/// palette's rows take (the PNG spec's own advice for one), and what a
/// picture of flat colours packs smallest as (`rgbPngOf`).
///
/// ⛔No row is put under a filter here: every one that is, is on the engine
/// (`png.wgsl`, `GpuReadout.takePngRows`). ↩️Till 2026-11-16 a writer
/// streamed its rows through `PngImageData`, which tried all five filters
/// a row in Dart — the animated PNG's frames the last (card
/// the-trimmed-apng-filters-its-rows-in-dart).
Uint8List pngUnfiltered(Uint8List pixels, int rowBytes) {
  final height = pixels.length ~/ rowBytes;
  final rows = Uint8List(height * (rowBytes + 1));
  for (var y = 0; y < height; y += 1) {
    rows.setRange(
      y * (rowBytes + 1) + 1,
      (y + 1) * (rowBytes + 1),
      pixels,
      y * rowBytes,
    );
  }
  return rows;
}

/// [rows] deflated: the body of a PNG's IDAT, or of an animation frame's
/// fdAT.
Uint8List pngDeflated(Uint8List rows) => switch (ZLibEncoder().convert(rows)) {
  final Uint8List bytes => bytes,
  final bytes => Uint8List.fromList(bytes),
};

/// The Paeth predictor: of [a] (left), [b] (up) and [c] (up-left), the one
/// nearest to a + b − c, ties to the earlier — what the engine filters a
/// row by (`png.wgsl`) and the reader unfilters one by (`readPngRows`).
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
