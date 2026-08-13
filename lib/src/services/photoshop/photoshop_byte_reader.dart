import 'dart:convert';
import 'dart:typed_data';

/// Big-endian cursor over Photoshop file bytes — brush packs (`.abr`),
/// patterns, descriptors and documents (`.psd`/`.psb`) all share one wire
/// format, so they share one reader.
///
/// It arrived as the ABR reader and moved here when the document reader
/// needed the same cursor: two copies of a big-endian cursor is exactly the
/// duplication the repo refuses.
class PhotoshopByteReader {
  PhotoshopByteReader(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int offset = 0;

  int get length => _bytes.length;
  int get remaining => _bytes.length - offset;
  bool get isAtEnd => offset >= _bytes.length;

  int readUint8() {
    _require(1);
    return _data.getUint8(offset++);
  }

  int readInt16() {
    _require(2);
    final value = _data.getInt16(offset);
    offset += 2;
    return value;
  }

  int readUint16() {
    _require(2);
    final value = _data.getUint16(offset);
    offset += 2;
    return value;
  }

  int readInt32() {
    _require(4);
    final value = _data.getInt32(offset);
    offset += 4;
    return value;
  }

  int readUint32() {
    _require(4);
    final value = _data.getUint32(offset);
    offset += 4;
    return value;
  }

  /// A `.psb` length field. Dart integers are 64-bit on every target this
  /// app builds for, so the value comes back whole; a document that
  /// genuinely needed more than 2^63 bytes could not be opened anyway.
  int readUint64() {
    _require(8);
    final value = _data.getUint64(offset);
    offset += 8;
    return value;
  }

  double readFloat64() {
    _require(8);
    final value = _data.getFloat64(offset);
    offset += 8;
    return value;
  }

  Uint8List readBytes(int count) {
    _require(count);
    final view = Uint8List.sublistView(_bytes, offset, offset + count);
    offset += count;
    return view;
  }

  /// Fixed-length ASCII (chunk signatures, type tags).
  String readAscii(int count) => ascii.decode(readBytes(count));

  /// Pascal string: one length byte followed by that many characters.
  String readPascalString() {
    final length = readUint8();
    return latin1.decode(readBytes(length));
  }

  /// Photoshop descriptor key/classID: 4 bytes of length; zero means a
  /// four-character code, otherwise that many characters follow.
  String readKeyString() {
    final length = readInt32();
    return latin1.decode(readBytes(length == 0 ? 4 : length));
  }

  /// Photoshop unicode string: UTF-16BE code-unit count, then the units;
  /// a trailing NUL is stripped.
  String readUnicodeString() {
    final count = readInt32();
    final units = Uint16List(count);
    for (var index = 0; index < count; index += 1) {
      units[index] = readUint16();
    }
    var end = count;
    while (end > 0 && units[end - 1] == 0) {
      end -= 1;
    }
    return String.fromCharCodes(units, 0, end);
  }

  void skip(int count) {
    _require(count);
    offset += count;
  }

  void _require(int count) {
    if (count < 0 || offset + count > _bytes.length) {
      throw const FormatException('Unexpected end of Photoshop data.');
    }
  }
}

/// Decodes Photoshop's per-scanline PackBits RLE: one compressed byte count
/// per scanline, then the packed data for each in turn.
///
/// Shared by the sampled-tip reader, the pattern reader and the document
/// reader — all three are the same Photoshop compression code (1) over the
/// same kind of plane.
///
/// [bytesPerRow] is BYTES, not pixels: a 16-bit channel packs two bytes per
/// sample and the RLE runs over the bytes. [scanlineCountBytes] is 2 for
/// every format but `.psb`, whose counts are 4.
Uint8List decodePackBitsScanlines(
  PhotoshopByteReader reader, {
  required int bytesPerRow,
  required int height,
  int scanlineCountBytes = 2,
}) {
  final scanlineLengths = List<int>.generate(
    height,
    (_) => scanlineCountBytes == 4 ? reader.readUint32() : reader.readUint16(),
  );
  return decodePackBitsRows(
    reader,
    rowLengths: scanlineLengths,
    bytesPerRow: bytesPerRow,
  );
}

/// The rows of a PackBits plane whose length table has ALREADY been read.
///
/// A document's composite image puts ONE table in front of every channel's
/// rows, so the table and the rows cannot be read in one pass — which is
/// why this half is callable on its own.
Uint8List decodePackBitsRows(
  PhotoshopByteReader reader, {
  required List<int> rowLengths,
  required int bytesPerRow,
}) {
  final height = rowLengths.length;
  final output = Uint8List(bytesPerRow * height);
  for (var y = 0; y < height; y += 1) {
    final compressed = reader.readBytes(rowLengths[y]);
    var read = 0;
    var write = y * bytesPerRow;
    final rowEnd = write + bytesPerRow;
    while (read < compressed.length && write < rowEnd) {
      final control = compressed[read].toSigned(8);
      read += 1;
      if (control >= 0) {
        final count = control + 1;
        if (read + count > compressed.length || write + count > rowEnd) {
          throw const FormatException('Corrupt RLE scanline.');
        }
        output.setRange(write, write + count, compressed, read);
        read += count;
        write += count;
      } else if (control != -128) {
        final count = 1 - control;
        if (read >= compressed.length || write + count > rowEnd) {
          throw const FormatException('Corrupt RLE scanline.');
        }
        output.fillRange(write, write + count, compressed[read]);
        read += 1;
        write += count;
      }
    }
    if (write != rowEnd) {
      throw const FormatException('RLE scanline ended short.');
    }
  }
  return output;
}
