import 'dart:convert';
import 'dart:io' show Directory, File, ZLibEncoder;
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

/// Writes the parts of a CLIP STUDIO PAINT file the way the format notes
/// say they are laid out (memory `csp-clip-format-notes`) — the files the
/// format was measured on came from work and stay out of the repository,
/// so the readers are pinned against bytes made here.

Uint8List _be32(int value) => (ByteData(4)..setUint32(0, value)).buffer
    .asUint8List();

Uint8List _be64(int value) => (ByteData(8)..setUint64(0, value)).buffer
    .asUint8List();

Uint8List _le32(int value) =>
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();

Uint8List _utf16be(String text) {
  final out = BytesBuilder();
  for (final unit in text.codeUnits) {
    out
      ..addByte(unit >> 8)
      ..addByte(unit & 0xff);
  }
  return out.toBytes();
}

/// The id an external chunk is named by.
String externalId(int n) =>
    'extrnlid${n.toRadixString(16).padLeft(32, '0').toUpperCase()}';

Uint8List _chunk(String kind, List<int> body) => (BytesBuilder()
      ..add(ascii.encode(kind))
      ..add(_be64(body.length))
      ..add(body))
    .toBytes();

/// A whole .clip: head, [externals] in order, the [database], foot.
Uint8List clipFileBytes({
  required List<int> database,
  Map<String, List<int>> externals = const {},
  bool withDatabase = true,
}) {
  final chunks = BytesBuilder()
    ..add(
      _chunk('CHNKHead', [
        ..._be64(0x100),
        ..._be64(0),
        ..._be64(16),
        ...List.filled(16, 7),
      ]),
    );
  externals.forEach((id, data) {
    chunks.add(
      _chunk('CHNKExta', [
        ..._be64(id.length),
        ...ascii.encode(id),
        ..._be64(data.length),
        ...data,
      ]),
    );
  });
  if (withDatabase) {
    chunks.add(_chunk('CHNKSQLi', database));
  }
  chunks.add(_chunk('CHNKFoot', const []));
  final body = chunks.toBytes();
  return (BytesBuilder()
        ..add(ascii.encode('CSFCHUNK'))
        ..add(_be64(24 + body.length))
        ..add(_be64(24))
        ..add(body))
      .toBytes();
}

/// One node of a cmt document to write. [rawValue] stands in for a value
/// of a type the reader is not meant to know.
final class CmtSpec {
  const CmtSpec(
    this.name,
    this.type, {
    this.value,
    this.rawValue,
    this.attributes = const {},
    this.children = const [],
  });

  final String name;
  final String type;
  final Object? value;
  final List<int>? rawValue;
  final Map<String, String> attributes;
  final List<CmtSpec> children;
}

/// [root] as a cmt binc document — 0110 ([doubles]) or 0100.
Uint8List cmtDocumentBytes(CmtSpec root, {bool doubles = true}) {
  final strings = <String>[];
  int index(String text) {
    final at = strings.indexOf(text);
    if (at >= 0) {
      return at;
    }
    strings.add(text);
    return strings.length - 1;
  }

  Uint8List real(num value) => doubles
      ? (ByteData(8)..setFloat64(0, value.toDouble(), Endian.little)).buffer
            .asUint8List()
      : (ByteData(4)..setFloat32(0, value.toDouble(), Endian.little)).buffer
            .asUint8List();

  Uint8List valueBytes(String type, Object? value) {
    final out = BytesBuilder();
    switch (type) {
      case 'null':
        break;
      case 'UInt32':
        out.add(_le32(value! as int));
      case 'Int32':
        out.add((ByteData(4)..setInt32(0, value! as int, Endian.little)).buffer
            .asUint8List());
      case 'Double':
        out.add((ByteData(8)
              ..setFloat64(0, (value! as num).toDouble(), Endian.little))
            .buffer
            .asUint8List());
      case 'Single':
        out.add((ByteData(4)
              ..setFloat32(0, (value! as num).toDouble(), Endian.little))
            .buffer
            .asUint8List());
      case 'String':
        out.add(_le32(index(value! as String)));
      case 'Double2' || 'Double3' || 'Float2' || 'Float3' || 'Quat':
        for (final part in value! as List<num>) {
          out.add(
            type == 'Quat'
                ? real(part)
                : type.startsWith('Double')
                ? (ByteData(8)
                        ..setFloat64(0, part.toDouble(), Endian.little))
                      .buffer
                      .asUint8List()
                : (ByteData(4)
                        ..setFloat32(0, part.toDouble(), Endian.little))
                      .buffer
                      .asUint8List(),
          );
        }
      default:
        if (!type.endsWith('[]')) {
          throw ArgumentError('no writer for $type');
        }
        final element = type.substring(0, type.length - 2);
        final items = value! as List<Object?>;
        out.add(_le32(items.length));
        for (final item in items) {
          out.add(valueBytes(element, item));
        }
    }
    return out.toBytes();
  }

  Uint8List node(CmtSpec spec) {
    final name = _le32(index(spec.name));
    final type = _le32(index(spec.type));
    final value = spec.rawValue != null
        ? Uint8List.fromList(spec.rawValue!)
        : valueBytes(spec.type, spec.value);
    final attributes = BytesBuilder()..add(_le32(spec.attributes.length));
    spec.attributes.forEach((key, text) {
      attributes
        ..add(_le32(index(key)))
        ..add(_le32(index(text)));
    });
    final attributeBytes = attributes.toBytes();
    final children = BytesBuilder()..add(_le32(spec.children.length));
    for (final child in spec.children) {
      children.add(node(child));
    }
    final out = BytesBuilder();
    if (doubles) {
      final attributesAt = 12 + 8 + value.length;
      out
        ..add(_le32(16))
        ..add(_le32(attributesAt))
        ..add(_le32(attributesAt + attributeBytes.length));
    }
    out
      ..add(name)
      ..add(type)
      ..add(value)
      ..add(attributeBytes)
      ..add(children.toBytes());
    return out.toBytes();
  }

  // Names first, the way the format keeps its type names at the front.
  final body = node(root);
  final table = BytesBuilder()..add(_le32(strings.length));
  for (final text in strings) {
    final bytes = utf8.encode(text);
    var length = bytes.length;
    do {
      final low = length & 0x7f;
      length >>= 7;
      table.addByte(length == 0 ? low : low | 0x80);
    } while (length != 0);
    table.add(bytes);
  }
  return (BytesBuilder()
        ..add(ascii.encode(doubles ? 'cmt 0110binc' : 'cmt 0100binc'))
        ..add(_le32(0))
        ..add(table.toBytes())
        ..add(body))
      .toBytes();
}

/// A track's external data: u32 LE length, then [document] in zlib.
Uint8List trackDataBytes(Uint8List document) {
  final packed = ZLibEncoder().convert(document);
  return (BytesBuilder()
        ..add(_le32(packed.length))
        ..add(packed))
      .toBytes();
}

Uint8List _section(String name, List<int> fields) => (BytesBuilder()
      ..add(_be32(name.length))
      ..add(_utf16be(name))
      ..add(fields))
    .toBytes();

/// An `Offscreen.Attribute` for a [width] × [height] picture in a
/// [columns] × [rows] grid of blocks.
Uint8List offscreenAttributeBytes({
  required int width,
  required int height,
  required int columns,
  required int rows,
  int alphaChannels = 1,
  int colourChannels = 4,
  int fill = 0,
}) {
  final parameter = _section('Parameter', [
    ..._be32(width),
    ..._be32(height),
    ..._be32(columns),
    ..._be32(rows),
    for (final v in [
      33,
      alphaChannels,
      colourChannels,
      alphaChannels + colourChannels,
      65536,
      4,
      1024,
      1,
      256,
      65536,
      256,
      256,
      8,
      8,
      0,
      0,
    ])
      ..._be32(v),
  ]);
  final initColour = _section('InitColor', [
    ..._be32(0),
    ..._be32(fill),
    ...List.filled(12, 0),
  ]);
  final blockSize = _section('BlockSize', [
    ..._be32(12),
    ..._be32(columns * rows),
    ..._be32(4),
    for (var i = 0; i < columns * rows; i += 1) ..._be32(0),
  ]);
  return (BytesBuilder()
        ..add(_be32(16))
        ..add(_be32(parameter.length))
        ..add(_be32(initColour.length))
        ..add(_be32(blockSize.length))
        ..add(parameter)
        ..add(initColour)
        ..add(blockSize))
      .toBytes();
}

/// One 256 × 256 block of a colour picture: the alpha plane, then B · G ·
/// R · unused for every pixel, from [pixel] (x, y) → (r, g, b, a).
Uint8List colourBlock((int, int, int, int) Function(int x, int y) pixel) {
  const side = 256;
  const plane = side * side;
  final block = Uint8List(plane * 5);
  for (var y = 0; y < side; y += 1) {
    for (var x = 0; x < side; x += 1) {
      final (r, g, b, a) = pixel(x, y);
      final i = y * side + x;
      block[i] = a;
      block[plane + i * 4] = b;
      block[plane + i * 4 + 1] = g;
      block[plane + i * 4 + 2] = r;
    }
  }
  return block;
}

/// An offscreen's external data: a record for every block in [blocks] (null
/// = stored empty), then the two trailing sections.
Uint8List blockRecordsBytes(Map<int, Uint8List?> blocks) {
  final out = BytesBuilder();
  blocks.forEach((number, block) {
    final begin = _utf16be('BlockDataBeginChunk');
    final end = _utf16be('BlockDataEndChunk');
    final fields = BytesBuilder()
      ..add(_be32(number))
      ..add(_be32(256 * 256 * 5))
      ..add(_be32(256))
      ..add(_be32(256));
    if (block == null) {
      fields.add(_be32(0));
    } else {
      final packed = ZLibEncoder().convert(block);
      fields
        ..add(_be32(1))
        ..add(_be32(4 + packed.length))
        ..add(_le32(packed.length))
        ..add(packed);
    }
    final record = BytesBuilder()
      ..add(_be32(19))
      ..add(begin)
      ..add(fields.toBytes())
      ..add(_be32(17))
      ..add(end);
    final bytes = record.toBytes();
    out
      ..add(_be32(4 + bytes.length))
      ..add(bytes);
  });
  for (final name in ['BlockStatus', 'BlockCheckSum']) {
    out.add(
      _section(name, [
        ..._be32(12),
        ..._be32(blocks.length),
        ..._be32(4),
        for (var i = 0; i < blocks.length; i += 1) ..._be32(1),
      ]),
    );
  }
  return out.toBytes();
}

/// The tables of a CLIP STUDIO file's database the reader asks, with the
/// columns the format notes name — the ones a program leaves out of a file
/// that does not use them (`AudioLayer`, `GradationFillInfo`) left out
/// here too.
const clipSchema = '''
  CREATE TABLE Canvas(_PW_ID INTEGER PRIMARY KEY, MainId INTEGER,
    CanvasWidth REAL, CanvasHeight REAL, CanvasRootFolder INTEGER,
    CropFrameInnerWidth INTEGER, CropFrameInnerHeight INTEGER,
    CropFrameCropOffsetX REAL, CropFrameCropOffsetY REAL,
    CropFrameInnerOffsetX REAL, CropFrameInnerOffsetY REAL);
  CREATE TABLE Layer(_PW_ID INTEGER PRIMARY KEY, MainId INTEGER,
    LayerName TEXT, LayerType INTEGER, LayerFolder INTEGER,
    LayerVisibility INTEGER, LayerOpacity INTEGER,
    LayerComposite INTEGER, LayerUuid TEXT, LayerOffsetX INTEGER,
    LayerOffsetY INTEGER, LayerRenderOffscrOffsetX INTEGER,
    LayerRenderOffscrOffsetY INTEGER, LayerFirstChildIndex INTEGER,
    LayerNextIndex INTEGER, LayerRenderMipmap INTEGER,
    ResizableOriginalMipmap INTEGER, ResizableImageInfo BLOB,
    DrawToRenderOffscreenType INTEGER, AnimationFolder INTEGER);
  CREATE TABLE Mipmap(_PW_ID INTEGER PRIMARY KEY, MainId INTEGER,
    BaseMipmapInfo INTEGER);
  CREATE TABLE MipmapInfo(_PW_ID INTEGER PRIMARY KEY, MainId INTEGER,
    ThisScale REAL, Offscreen INTEGER, NextIndex INTEGER);
  CREATE TABLE Offscreen(_PW_ID INTEGER PRIMARY KEY, MainId INTEGER,
    Attribute BLOB, BlockData TEXT);
  CREATE TABLE AnimationCutBank(_PW_ID INTEGER PRIMARY KEY,
    MainId INTEGER, FirstTimeLine INTEGER, CurrentIndex INTEGER);
  CREATE TABLE TimeLine(_PW_ID INTEGER PRIMARY KEY, MainId INTEGER,
    NextTimeLine INTEGER, TimeLineName TEXT, FrameRate REAL,
    StartFrame INTEGER, EndFrame INTEGER, FirstTrack INTEGER);
  CREATE TABLE Track(_PW_ID INTEGER PRIMARY KEY, MainId INTEGER,
    TrackNextIndex INTEGER, TrackKind INTEGER,
    LayerUuidWithTrack BLOB, TrackActionMixer TEXT,
    TrackActionMixer2 TEXT, TrackLabelFirstIndex INTEGER);
  CREATE TABLE TimeLineLabel(_PW_ID INTEGER PRIMARY KEY,
    MainId INTEGER, LabelFrame INTEGER, LabelType INTEGER,
    LabelNextIndex INTEGER);
''';

/// The bytes of a database [build] fills, made in [folder] (the file goes
/// as soon as it is read).
Uint8List clipDatabaseBytes(
  Directory folder,
  void Function(Database db) build,
) {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final path = '${folder.path}/build-$stamp.db';
  final db = sqlite3.open(path);
  try {
    build(db);
  } finally {
    db.close();
  }
  final bytes = File(path).readAsBytesSync();
  File(path).deleteSync();
  return bytes;
}

/// [uuid] as a track names its layer: its sixteen bytes.
Uint8List clipUuidBytes(String uuid) {
  final hex = uuid.replaceAll('-', '');
  return Uint8List.fromList([
    for (var i = 0; i < 32; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

/// One clip of a track document (`ActionNodeClip`): its place on the
/// timeline in ticks ([time]), the motion it plays ([motion]), and the cels
/// it keys — ticks in [keys], names in [cels]. Rate 60, as the samples.
CmtSpec clipNodeSpec({
  required List<num> time,
  required List<num> motion,
  List<num> keys = const [],
  List<String> cels = const [],
}) => CmtSpec(
  'ActionNodeClip',
  'null',
  children: [
    CmtSpec(
      'TimeClip',
      'null',
      children: [
        CmtSpec('Start', 'Double', value: time[0]),
        CmtSpec('End', 'Double', value: time[1]),
        const CmtSpec('Rate', 'Double', value: 60),
      ],
    ),
    CmtSpec(
      'MotionClip',
      'null',
      children: [
        CmtSpec('Start', 'Double', value: motion[0]),
        CmtSpec('End', 'Double', value: motion[1]),
      ],
    ),
    if (keys.isNotEmpty)
      CmtSpec(
        'AnimInfo',
        'null',
        children: [
          CmtSpec(
            'FCurve',
            'null',
            attributes: const {'Type': 'ImageCelName'},
            children: [
              CmtSpec('Frame', 'Double[]', value: keys),
              CmtSpec('Tag', 'String[]', value: cels),
            ],
          ),
        ],
      ),
  ],
);


/// A track document holding [clips].
CmtSpec clipTrackSpec(List<CmtSpec> clips) =>
    CmtSpec('celsysdocument', 'null', children: clips);
