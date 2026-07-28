import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/qap_incremental_writer.dart'
    show qapCrc32;
import 'package:anicel/src/ui/export/png_srgb.dart';

/// C1-v1 (R28): exported PNGs carry the sRGB/gAMA/cHRM trio right
/// after IHDR — a label, never a pixel change.
void main() {
  Uint8List chunk(String type, List<int> data) {
    final typeAndData = Uint8List(4 + data.length)
      ..setAll(0, type.codeUnits)
      ..setAll(4, data);
    final out = BytesBuilder()
      ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
      ..add(typeAndData)
      ..add(
        (ByteData(4)..setUint32(0, qapCrc32(typeAndData))).buffer.asUint8List(),
      );
    return out.takeBytes();
  }

  Uint8List minimalPng() {
    final ihdrData = ByteData(13)
      ..setUint32(0, 1) // width
      ..setUint32(4, 1) // height
      ..setUint8(8, 8) // bit depth
      ..setUint8(9, 6); // color type RGBA
    final out = BytesBuilder()
      ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
      ..add(chunk('IHDR', ihdrData.buffer.asUint8List()))
      ..add(chunk('IDAT', const [1, 2, 3]))
      ..add(chunk('IEND', const []));
    return out.takeBytes();
  }

  String typeAt(Uint8List png, int offset) =>
      String.fromCharCodes(png.sublist(offset + 4, offset + 8));

  test('inserts sRGB + gAMA + cHRM after IHDR, CRCs valid, original '
      'bytes untouched', () {
    final original = minimalPng();
    final tagged = tagPngAsSrgb(original);

    // Chunk walk: IHDR, sRGB, gAMA, cHRM, IDAT, IEND.
    var offset = 8;
    final types = <String>[];
    while (offset < tagged.length) {
      final data = ByteData.sublistView(tagged);
      final length = data.getUint32(offset);
      types.add(typeAt(tagged, offset));
      final typeAndData = Uint8List.sublistView(
        tagged,
        offset + 4,
        offset + 8 + length,
      );
      expect(
        data.getUint32(offset + 8 + length),
        qapCrc32(typeAndData),
        reason: 'CRC of ${types.last}',
      );
      offset += 12 + length;
    }
    expect(types, ['IHDR', 'sRGB', 'gAMA', 'cHRM', 'IDAT', 'IEND']);

    // The original IHDR head and IDAT tail are byte-identical.
    expect(tagged.sublist(0, 33), original.sublist(0, 33));
    expect(
      tagged.sublist(tagged.length - (original.length - 33)),
      original.sublist(33),
    );
  });

  test('non-PNG bytes pass through untouched', () {
    final junk = Uint8List.fromList(List.generate(40, (i) => i));
    expect(tagPngAsSrgb(junk), junk);
  });
}
