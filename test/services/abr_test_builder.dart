import 'dart:convert';
import 'dart:typed_data';

/// Big-endian byte builder mirroring the ABR/descriptor wire format, used
/// to construct synthetic fixture files.
class AbrBytes {
  final BytesBuilder _builder = BytesBuilder();

  Uint8List get bytes => _builder.toBytes();
  int get length => _builder.length;

  void u8(int value) => _builder.addByte(value & 0xFF);

  void i16(int value) {
    u8(value >> 8);
    u8(value);
  }

  void i32(int value) {
    u8(value >> 24);
    u8(value >> 16);
    u8(value >> 8);
    u8(value);
  }

  void f64(double value) {
    final data = ByteData(8)..setFloat64(0, value);
    _builder.add(data.buffer.asUint8List());
  }

  void asciiChars(String value) => _builder.add(ascii.encode(value));

  void raw(List<int> value) => _builder.add(value);

  void pascal(String value) {
    u8(value.length);
    asciiChars(value);
  }

  /// Descriptor key/classID: zero length means four characters.
  void key(String value) {
    if (value.length == 4) {
      i32(0);
    } else {
      i32(value.length);
    }
    asciiChars(value);
  }

  /// Photoshop unicode string with a trailing NUL, as Photoshop writes.
  void unicode(String value) {
    i32(value.length + 1);
    for (final unit in value.codeUnits) {
      i16(unit);
    }
    i16(0);
  }

  void untf(String unit, double value) {
    asciiChars('UntF');
    asciiChars(unit);
    f64(value);
  }

  void text(String value) {
    asciiChars('TEXT');
    unicode(value);
  }
}

/// One samp-section entry (subversion 2 layout: 301-byte preamble).
void writeSampEntry(
  AbrBytes samp, {
  required String uuid,
  required int width,
  required int height,
  required List<int> pixels,
  bool rle = false,
  int depth = 8,
}) {
  final entry = AbrBytes();
  entry.pascal(uuid);
  // Pad the preamble (key + coordinates + unknown) out to 301 bytes.
  entry.raw(List<int>.filled(301 - 1 - uuid.length, 0));
  entry.i32(0); // top
  entry.i32(0); // left
  entry.i32(height); // bottom
  entry.i32(width); // right
  entry.i16(depth);
  entry.u8(rle ? 1 : 0);
  if (rle) {
    final rows = <List<int>>[];
    for (var y = 0; y < height; y += 1) {
      final row = pixels.sublist(y * width, (y + 1) * width);
      // Naive PackBits: encode the whole row as one literal chunk.
      rows.add([row.length - 1, ...row]);
    }
    for (final row in rows) {
      entry.i16(row.length);
    }
    for (final row in rows) {
      entry.raw(row);
    }
  } else {
    entry.raw(pixels);
  }

  final entryBytes = entry.bytes;
  samp.i32(entryBytes.length);
  samp.raw(entryBytes);
  // Entries are padded to four-byte boundaries.
  final padding = (4 - entryBytes.length % 4) % 4;
  samp.raw(List<int>.filled(padding, 0));
}

void write8bimSection(AbrBytes file, String tag, Uint8List payload) {
  file.asciiChars('8BIM');
  file.asciiChars(tag);
  file.i32(payload.length);
  file.raw(payload);
}
