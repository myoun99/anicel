import 'dart:typed_data';

import '../../services/media/png_writing.dart' show pngChunk, pngUint32;

/// C1-v1 (R28): stamps a PNG as sRGB.
///
/// The app's WORKING COLOR SPACE IS sRGB — every brush, fill and
/// composite treats the 8-bit bytes as sRGB, exactly like the drawing
/// stage of TVPaint/CSP pipelines (color conversion for delivery
/// happens downstream in compositing). Neither Flutter's PNG encoder nor
/// this app's own (`encodeStillPng`, the PNG without alpha) writes a
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

  final builder = BytesBuilder(copy: false)
    ..add(Uint8List.sublistView(png, 0, insertAt))
    ..add(pngChunk('sRGB', const [0]))
    ..add(pngChunk('gAMA', pngUint32(45455)))
    ..add(
      pngChunk('cHRM', [
        ...pngUint32(31270), ...pngUint32(32900), // white point
        ...pngUint32(64000), ...pngUint32(33000), // red
        ...pngUint32(30000), ...pngUint32(60000), // green
        ...pngUint32(15000), ...pngUint32(6000), // blue
      ]),
    )
    ..add(Uint8List.sublistView(png, insertAt));
  return builder.takeBytes();
}
