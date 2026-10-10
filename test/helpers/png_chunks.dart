import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

/// [png]'s chunks in file order: each one's type and data.
List<({String type, Uint8List data})> pngChunksOf(Uint8List png) {
  final view = ByteData.sublistView(png);
  return [
    for (var at = 8; at + 8 <= png.length; at += 12 + view.getUint32(at))
      (
        type: String.fromCharCodes(png.sublist(at + 4, at + 8)),
        data: Uint8List.sublistView(png, at + 8, at + 8 + view.getUint32(at)),
      ),
  ];
}

/// IHDR's colour type: 2 RGB, 3 a palette, 6 RGBA.
int pngColourTypeOf(Uint8List png) =>
    pngChunksOf(png).firstWhere((chunk) => chunk.type == 'IHDR').data[9];

/// The filter byte that leads each of [png]'s rows — [stride] bytes a row,
/// past that byte — read from its one IDAT.
List<int> pngRowFiltersOf(Uint8List png, {required int stride}) {
  final rows = ZLibCodec().decode(
    pngChunksOf(png).firstWhere((chunk) => chunk.type == 'IDAT').data,
  );
  return [for (var at = 0; at < rows.length; at += stride + 1) rows[at]];
}
