import 'dart:typed_data';

import '../../services/persistence/anicel_incremental_writer.dart'
    show anicelCrc32;

/// C1-v1 (R28): stamps a PNG as sRGB.
///
/// The app's WORKING COLOR SPACE IS sRGB — every brush, fill and
/// composite treats the 8-bit bytes as sRGB, exactly like the drawing
/// stage of TVPaint/CSP pipelines (color conversion for delivery
/// happens downstream in compositing). Flutter's PNG encoder writes no
/// color-space chunk, so consumers had to guess; this inserts the
/// standard trio right after IHDR so Photoshop/browsers/editors read
/// the colors identically:
///
///  - `sRGB` (rendering intent: perceptual) — the authoritative tag;
///  - `gAMA` 45455 and `cHRM` sRGB primaries — the spec's mandated
///    fallbacks for readers that predate the sRGB chunk.
///
/// Pixels are untouched — this is a label, not a conversion.
Uint8List tagPngAsSrgb(Uint8List png) {
  // Signature (8) + IHDR (4 len + 4 type + 13 data + 4 crc) = 33.
  const insertAt = 33;
  if (png.length < insertAt || png[1] != 0x50 /* 'P' */ ) {
    return png; // Not a PNG we understand — pass through untouched.
  }

  Uint8List chunk(String type, List<int> data) {
    final typeAndData = Uint8List(4 + data.length);
    for (var i = 0; i < 4; i += 1) {
      typeAndData[i] = type.codeUnitAt(i);
    }
    typeAndData.setAll(4, data);
    final out = BytesBuilder(copy: false);
    final header = ByteData(4)..setUint32(0, data.length);
    out.add(header.buffer.asUint8List());
    out.add(typeAndData);
    final crc = ByteData(4)..setUint32(0, anicelCrc32(typeAndData));
    out.add(crc.buffer.asUint8List());
    return out.takeBytes();
  }

  Uint8List be32(int value) =>
      (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

  final builder = BytesBuilder(copy: false)
    ..add(Uint8List.sublistView(png, 0, insertAt))
    ..add(chunk('sRGB', const [0]))
    ..add(chunk('gAMA', be32(45455)))
    ..add(
      chunk('cHRM', [
        ...be32(31270), ...be32(32900), // white point
        ...be32(64000), ...be32(33000), // red
        ...be32(30000), ...be32(60000), // green
        ...be32(15000), ...be32(6000), // blue
      ]),
    )
    ..add(Uint8List.sublistView(png, insertAt));
  return builder.takeBytes();
}
