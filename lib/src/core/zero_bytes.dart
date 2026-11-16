import 'dart:typed_data';

/// Bytes of zero to copy from: a tile's worth, made once an isolate.
final Uint8List _zeros = Uint8List(1 << 16);

/// Every byte of [bytes] made 0, by copying zeros over them.
///
/// 🚨★★**NOT `fillRange(0, length, 0)`** (card
/// the-tile-cutter-is-most-of-a-raster-import, 2026-11-16): on bytes it is
/// a loop a byte at a time, about 1.3 ns each compiled ahead — 88 µs a
/// 128² tile. 🔬Cutting an 8K picture into tiles took 255 ms and 180 of
/// them were its blocks zeroed so; copied over from zeros the same cut took
/// 23 ms (Surface, profile, the same tiles). A typed list's copy is a
/// memory move.
void zeroBytes(Uint8List bytes) {
  for (var at = 0; at < bytes.length; at += _zeros.length) {
    final end = at + _zeros.length < bytes.length
        ? at + _zeros.length
        : bytes.length;
    bytes.setRange(at, end, _zeros);
  }
}
