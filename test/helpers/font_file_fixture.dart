import 'dart:convert';
import 'dart:typed_data';

/// One record of a font file's `name` table, as a test writes it.
typedef FontNameRecord = ({
  int platform,
  int encoding,
  int language,
  int nameId,
  String text,
});

/// The family's name written for Windows in English — the record a font
/// file is called by first.
FontNameRecord windowsEnglishFamily(String text) =>
    (platform: 3, encoding: 1, language: 0x0409, nameId: 1, text: text);

/// THE BYTES OF A FONT FILE THAT SAYS WHAT A TEST WANTS IT TO SAY — its
/// table directory and the tables the app reads (`head`, `cmap`, `name`,
/// `OS/2`), and no glyph at all: a file to be READ, not drawn with.
///
/// What the engine does with a font is measured with the app's own files
/// (`assets/fonts/`), which have glyphs.
Uint8List fontFileSaying({
  String family = 'Probe Sans',
  List<FontNameRecord>? names,
  int weight = 400,
  bool italic = false,

  /// The maker's word on embedding; null leaves the OS/2 table out.
  int? fsType = 0,
  int kind = 0x00010000,
  bool withHead = true,
  bool withCmap = true,
  int headMagic = 0x5F0F3CF5,

  /// `head`'s own style bits — what a file with no OS/2 table is read by.
  int macStyle = 0,

  /// How long `head` is: 54 in every font there is.
  int headLength = 54,

  /// How long the OS/2 table is: 64 carries the slant, 10 the weight and
  /// the word on embedding, and a shorter one neither.
  int os2Length = 64,

  /// The OS/2 table's own style bits, in place of the ones [italic] sets.
  int? fsSelection,
}) {
  final tables = <String, Uint8List>{
    if (withHead)
      'head': _head(magic: headMagic, macStyle: macStyle, length: headLength),
    if (withCmap) 'cmap': Uint8List(4),
    'name': _nameTable(names ?? [windowsEnglishFamily(family)]),
    if (fsType != null)
      'OS/2': _os2(
        weight: weight,
        fsSelection: fsSelection ?? (italic ? 0x0001 : 0x0040),
        fsType: fsType,
        length: os2Length,
      ),
  };
  final out = BytesBuilder();
  final directory = ByteData(12 + tables.length * 16)
    ..setUint32(0, kind)
    ..setUint16(4, tables.length);
  var offset = directory.lengthInBytes;
  var record = 12;
  for (final entry in tables.entries) {
    final tag = latin1.encode(entry.key);
    for (var i = 0; i < 4; i += 1) {
      directory.setUint8(record + i, tag[i]);
    }
    directory
      ..setUint32(record + 8, offset)
      ..setUint32(record + 12, entry.value.length);
    offset += entry.value.length;
    record += 16;
  }
  out.add(directory.buffer.asUint8List());
  tables.values.forEach(out.add);
  return out.toBytes();
}

/// [faces] as one collection file (.ttc): its header, then each face with
/// its tables moved to where they now lie.
Uint8List fontCollectionOf(List<Uint8List> faces) {
  final header = ByteData(12 + faces.length * 4)
    ..setUint32(0, 0x74746366) // 'ttcf'
    ..setUint32(4, 0x00010000)
    ..setUint32(8, faces.length);
  final out = BytesBuilder();
  var offset = header.lengthInBytes;
  final moved = <Uint8List>[];
  for (var index = 0; index < faces.length; index += 1) {
    header.setUint32(12 + index * 4, offset);
    final face = Uint8List.fromList(faces[index]);
    final data = ByteData.sublistView(face);
    final count = data.getUint16(4);
    for (var table = 0; table < count; table += 1) {
      final at = 12 + table * 16 + 8;
      data.setUint32(at, data.getUint32(at) + offset);
    }
    moved.add(face);
    offset += face.length;
  }
  out.add(header.buffer.asUint8List());
  moved.forEach(out.add);
  return out.toBytes();
}

/// A `head` table [length] long, saying what of [magic] and [macStyle] a
/// table that long has room to say.
Uint8List _head({
  required int magic,
  required int macStyle,
  required int length,
}) {
  final head = ByteData(length);
  if (length >= 16) {
    head.setUint32(12, magic);
  }
  if (length >= 46) {
    head.setUint16(44, macStyle);
  }
  return head.buffer.asUint8List();
}

/// An OS/2 table [length] long, saying what a table that long has room to.
Uint8List _os2({
  required int weight,
  required int fsSelection,
  required int fsType,
  required int length,
}) {
  final os2 = ByteData(length);
  if (length >= 6) {
    os2.setUint16(4, weight);
  }
  if (length >= 10) {
    os2.setUint16(8, fsType);
  }
  if (length >= 64) {
    os2.setUint16(62, fsSelection);
  }
  return os2.buffer.asUint8List();
}

Uint8List _nameTable(List<FontNameRecord> records) {
  final strings = BytesBuilder();
  final header = ByteData(6 + records.length * 12)
    ..setUint16(2, records.length)
    ..setUint16(4, 6 + records.length * 12);
  for (var index = 0; index < records.length; index += 1) {
    final record = records[index];
    // Windows and Unicode names are UTF-16BE; a Macintosh one is a byte a
    // letter.
    final Uint8List text;
    if (record.platform == 1) {
      text = latin1.encode(record.text);
    } else {
      final wide = ByteData(record.text.length * 2);
      for (var i = 0; i < record.text.length; i += 1) {
        wide.setUint16(i * 2, record.text.codeUnitAt(i));
      }
      text = wide.buffer.asUint8List();
    }
    final at = 6 + index * 12;
    header
      ..setUint16(at, record.platform)
      ..setUint16(at + 2, record.encoding)
      ..setUint16(at + 4, record.language)
      ..setUint16(at + 6, record.nameId)
      ..setUint16(at + 8, text.length)
      ..setUint16(at + 10, strings.length);
    strings.add(text);
  }
  return (BytesBuilder()
        ..add(header.buffer.asUint8List())
        ..add(strings.toBytes()))
      .toBytes();
}
