import 'dart:typed_data';

/// [pixels] — four bytes a texel — with each texel's first and third bytes
/// swapped: RGBA laid as BGRA, and BGRA as RGBA. A copy; [pixels] stands.
///
/// One for every reader of a picture laid the other way: a cursor's pixels
/// as Windows reads them (`drawing_cursor.dart`), a screen read off
/// Flutter as the engine laid it (`ScreenCheck`).
Uint8List redAndBlueSwapped(ByteData pixels) {
  final bytes = Uint8List.fromList(
    pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes),
  );
  for (var i = 0; i + 3 < bytes.length; i += 4) {
    final red = bytes[i];
    bytes[i] = bytes[i + 2];
    bytes[i + 2] = red;
  }
  return bytes;
}
