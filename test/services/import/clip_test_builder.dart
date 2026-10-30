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

/// A layer's `LayerEffectInfo` in the shape one sample's held (memory
/// `csp-clip-format-notes` §2 — s12, 10-17): every record it had, each
/// setting at the sample's value — CLIP STUDIO's defaults, so a word read
/// one place off lands on one that is not 0 — with the switches of the
/// effects named in [on] set, and the tone's own settings at
/// [reflectOpacity] and [posterize] — the records named in [without] left
/// out.
Uint8List layerEffectInfoBytes({
  Set<String> on = const {},
  int reflectOpacity = 1,
  int posterize = 0,
  Set<String> without = const {},
}) {
  int switchOf(String name) => on.contains(name) ? 1 : 0;
  // A record's body as words — led by their size, counting itself, when
  // [sized] (every record but the two oldest).
  (String, Uint8List) record(
    String name,
    List<int> body, {
    bool sized = true,
  }) => (
    name,
    _section(name, [
      if (sized) ..._be32(4 * (body.length + 1)),
      for (final word in body) ..._be32(word),
    ]),
  );
  List<int> f64(double value) {
    final bits = ByteData(8)..setFloat64(0, value);
    return [bits.getUint32(0), bits.getUint32(4)];
  }

  final records = [
    record('EffectEdge', [
      switchOf('EffectEdge'),
      ...f64(3),
      0xFFFFFFFF,
      0xFFFFFFFF,
      0xFFFFFFFF,
    ], sized: false),
    record('EffectTone', [
      switchOf('EffectTone'),
      ...f64(200),
      1,
      0,
      20,
      ...f64(60),
      1,
      0,
      45,
      30,
      ...List.filled(7, 0),
    ], sized: false),
    record('EffectTextureMap', [
      switchOf('EffectTextureMap'),
      30,
      0x80808080,
    ]),
    record('EffectApplyOpacity', [reflectOpacity]),
    record('EffectToneAreaColor', [111, 215, 241]),
    record('EffectTonePosterize', [posterize, 2, 60, 50, 120, 30]),
    record('EffectWaterEdge', [
      switchOf('EffectWaterEdge'),
      ...f64(5),
      ...f64(50),
      ...f64(20),
      ...f64(10),
    ]),
    record('EffectLine', [
      switchOf('EffectLine'),
      1,
      0xF0F0F0F0,
      ...List.filled(25, 0),
    ]),
  ];
  // The sample's three words after the last record, their sense unknown.
  final tail = [..._be32(0), ..._be32(1), ..._be32(200)];
  final body = [
    for (final (name, bytes) in records)
      if (!without.contains(name)) ...bytes,
    ...tail,
  ];
  return (BytesBuilder()
        ..add(_be32(8 + body.length))
        ..add(_be32(2))
        ..add(body))
      .toBytes();
}

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
    DrawToRenderOffscreenType INTEGER, AnimationFolder INTEGER,
    DrawColorMainRed INTEGER, DrawColorMainGreen INTEGER,
    DrawColorMainBlue INTEGER);
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
  CREATE TABLE VectorObjectList(_PW_ID INTEGER PRIMARY KEY,
    MainId INTEGER, CanvasId INTEGER, LayerId INTEGER, VectorData BLOB);
''';

/// A brush material's `.layer` (memory `csp-clip-format-notes` §8): a C2F
/// file of the database holding [offscreens] under [directory], [ciphered]
/// bytes of it replaced by junk in a chunk of their own, the rest plain.
///
/// The tables ahead of `Offscreen` take the pages the cipher covers, as the
/// real schema's do. [cipherOverRows] leaves them out, so the rows themselves
/// lie where nothing can read them; [pagesCut] takes that many pages off the
/// end, where a row's overflow lies.
Uint8List sutMaterialLayerBytes(
  Directory directory, {
  required List<({Uint8List attribute, Uint8List blocks})> offscreens,
  int pageSize = 1024,
  int ciphered = 5120,
  bool cipherOverRows = false,
  int pagesCut = 0,
}) {
  final path = '${directory.path}/layer${directory.listSync().length}.db';
  final database = sqlite3.open(path)
    ..execute('PRAGMA page_size = $pageSize');
  if (!cipherOverRows) {
    for (var table = 0; table < 8; table += 1) {
      database.execute('CREATE TABLE Ahead$table(_PW_ID INTEGER PRIMARY KEY)');
    }
    // A leaf of more cells than a smaller page has room for the pointers of,
    // which is what a reader trying that size meets.
    for (var row = 0; row < 540; row += 1) {
      database.execute('INSERT INTO Ahead7 DEFAULT VALUES');
    }
  }
  database.execute('''
    CREATE TABLE Offscreen(_PW_ID INTEGER PRIMARY KEY, MainId INTEGER,
      CanvasId INTEGER, LayerId INTEGER, Attribute BLOB, BlockData BLOB);
  ''');
  for (final offscreen in offscreens) {
    database.execute(
      'INSERT INTO Offscreen(MainId, CanvasId, LayerId, Attribute, BlockData) '
      'VALUES (1, 1, 2, ?, ?)',
      [offscreen.attribute, offscreen.blocks],
    );
  }
  database.close();
  final whole = File(path).readAsBytesSync();
  Uint8List chunk(List<int> body) => (BytesBuilder()
        ..add(_le32(body.length))
        ..add(ascii.encode('dATA'))
        ..add(body)
        ..add(Uint8List(4)))
      .toBytes();
  return (BytesBuilder()
        ..add([0x89, ...ascii.encode('C2F'), 0x0D, 0x0A, 0x1A, 0x0A])
        ..add(ascii.encode('HEAD'))
        ..add(Uint8List(8))
        ..add(chunk([1, 0, ...Uint8List(8), ...List.filled(ciphered, 0xA5)]))
        ..add(
          chunk([
            0,
            0,
            ...whole.sublist(ciphered, whole.length - pagesCut * pageSize),
          ]),
        )
        ..add(_le32(0))
        ..add(ascii.encode('TAIL')))
      .toBytes();
}

/// A TAR of [files], name to bytes — a brush material's own shape
/// (`catalog.zip` · `data/material_0.layer` · `thumbnail/thumbnail.png`).
Uint8List sutMaterialBytes(Map<String, Uint8List> files) {
  final out = BytesBuilder();
  files.forEach((name, bytes) {
    final head = Uint8List(512)..setRange(0, name.length, ascii.encode(name));
    final size = bytes.length.toRadixString(8).padLeft(11, '0');
    head
      ..setRange(124, 135, ascii.encode(size))
      ..setRange(257, 262, ascii.encode('ustar'));
    out
      ..add(head)
      ..add(bytes)
      ..add(Uint8List(-bytes.length % 512));
  });
  out.add(Uint8List(1024));
  return out.toBytes();
}

/// One stroke record of a vector layer's data (memory
/// `csp-clip-format-notes` §7): a [head]-byte head (88 or 92) and its
/// [points] — x, y and the radius's factor there — with a curve tool's
/// 104-byte points when [bends] gives each its control point (null =
/// straight).
Uint8List vectorStrokeBytes(
  List<(double, double, double)> points, {
  (int, int, int) colour = (0, 0, 0),
  double opacity = 1,
  double radius = 2,
  int head = 92,
  int flags = 1,
  List<(double, double)?>? bends,
}) {
  final pointSize = bends == null ? 88 : 104;
  final data = ByteData(head + points.length * pointSize)
    ..setUint32(0, head)
    ..setUint32(8, pointSize)
    ..setUint32(16, points.length)
    ..setUint32(20, flags)
    ..setUint8(40, colour.$1)
    ..setUint8(44, colour.$2)
    ..setUint8(48, colour.$3)
    ..setFloat64(64, opacity)
    ..setFloat64(head == 92 ? 80 : 76, radius);
  for (var p = 0; p < points.length; p += 1) {
    final at = head + p * pointSize;
    final (x, y, factor) = points[p];
    data
      ..setFloat64(at, x)
      ..setFloat64(at + 8, y)
      ..setFloat32(at + 56, factor);
    if (bends?[p] case (final bx, final by)) {
      data
        ..setFloat64(at + 88, bx)
        ..setFloat64(at + 96, by);
    }
  }
  return data.buffer.asUint8List();
}

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

/// One run of a text's letters in a style of its own, as
/// [clipTextAttributesBytes] writes it: [colour] and [scale] its own where
/// given, [face] where not empty.
typedef ClipTextRunSpec = ({
  int start,
  int length,
  bool bold,
  bool italic,
  (int, int, int)? colour,
  double? scale,
  String face,
});

/// A stretch of a text's letters and the one-byte value parameters 12 · 16
/// · 20 give it (an alignment, an underline, a strike).
typedef ClipTextFlagSpec = ({int start, int length, int value});

/// A text's `TextLayerAttributes` the way the format notes lay them out
/// (memory `csp-clip-format-notes` 6-1 §13): `u32 LE id · u32 LE size ·
/// bytes`, a parameter each — what `clip_lettering.dart` reads. [box] null
/// writes none; [corners] null writes the box's own, square, measured from
/// the canvas's top-left, and [withCorners] false none; [textAlign]
/// (parameter 35) and [pictureOffset] (72) null write none.
Uint8List clipTextAttributesBytes({
  ({int x0, int y0, int x1, int y1})? box = (x0: 0, y0: 0, x1: 10, y1: 10),
  double points = 12,
  (int, int, int) colour = (0, 0, 0),
  String face = 'Face',
  ({int width, int height})? boxSize,
  List<ClipTextRunSpec> runs = const [],
  List<ClipTextFlagSpec> aligns = const [],
  List<({int start, int length, double spacing})> spacings = const [],
  List<ClipTextFlagSpec> underlines = const [],
  List<ClipTextFlagSpec> strikes = const [],
  double across = 100,
  List<int>? corners,
  bool withCorners = true,
  int textFlags = 0,
  int? textAlign,
  (int, int)? pictureOffset,
}) {
  final out = BytesBuilder();
  void parameter(int id, Uint8List body) => out
    ..add(_le32(id))
    ..add(_le32(body.length))
    ..add(body);
  Uint8List flags(List<ClipTextFlagSpec> stretches) {
    final data = ByteData(4 + 14 * stretches.length)
      ..setUint32(0, stretches.length, Endian.little);
    for (final (k, stretch) in stretches.indexed) {
      data
        ..setInt32(4 + 14 * k, stretch.start, Endian.little)
        ..setUint32(8 + 14 * k, stretch.length, Endian.little)
        ..setUint8(16 + 14 * k, stretch.value);
    }
    return data.buffer.asUint8List();
  }

  if (runs.isNotEmpty) {
    final body = BytesBuilder()..add(_le32(runs.length));
    for (final run in runs) {
      final data = ByteData(32 + 2 * run.face.length)
        ..setInt32(0, run.start, Endian.little)
        ..setUint32(4, run.length, Endian.little)
        ..setUint32(8, 28 + 2 * run.face.length, Endian.little)
        ..setUint8(12, (run.bold ? 1 : 0) | (run.italic ? 2 : 0))
        ..setUint8(
          13,
          (run.colour == null ? 0 : 1) | (run.scale == null ? 0 : 2),
        )
        // What a run keeps here when its scale is not its own is not
        // read: something no scale would be.
        ..setFloat64(20, run.scale ?? 250, Endian.little)
        ..setUint16(28, run.face.length, Endian.little);
      if (run.colour case (final r, final g, final b)) {
        data
          ..setUint16(14, r * 257, Endian.little)
          ..setUint16(16, g * 257, Endian.little)
          ..setUint16(18, b * 257, Endian.little);
      }
      for (final (c, unit) in run.face.codeUnits.indexed) {
        data.setUint16(30 + 2 * c, unit, Endian.little);
      }
      body.add(data.buffer.asUint8List());
    }
    parameter(11, body.toBytes());
  }
  if (aligns.isNotEmpty) {
    parameter(12, flags(aligns));
  }
  if (spacings.isNotEmpty) {
    final data = ByteData(4 + 30 * spacings.length)
      ..setUint32(0, spacings.length, Endian.little);
    for (final (k, stretch) in spacings.indexed) {
      data
        ..setInt32(4 + 30 * k, stretch.start, Endian.little)
        ..setUint32(8 + 30 * k, stretch.length, Endian.little)
        ..setUint32(12 + 30 * k, 18, Endian.little)
        ..setFloat64(26 + 30 * k, stretch.spacing, Endian.little);
    }
    parameter(13, data.buffer.asUint8List());
  }
  if (underlines.isNotEmpty) {
    parameter(16, flags(underlines));
  }
  if (strikes.isNotEmpty) {
    parameter(20, flags(strikes));
  }
  parameter(
    26,
    (ByteData(32)..setFloat64(16, across, Endian.little)).buffer.asUint8List(),
  );
  if (face.isNotEmpty) {
    parameter(31, utf8.encode(face));
  }
  parameter(
    32,
    (ByteData(4)..setInt32(0, (points * 100).round(), Endian.little)).buffer
        .asUint8List(),
  );
  parameter(33, _le32(textFlags));
  final (r, g, b) = colour;
  parameter(
    34,
    Uint8List.fromList([
      // A channel is its top byte; the bytes under it are not the colour's.
      for (final channel in [r, g, b]) ..._le32(channel << 24 | 0x123456),
    ]),
  );
  if (textAlign != null) {
    parameter(35, _le32(textAlign));
  }
  if (pictureOffset case (final x, final y)) {
    parameter(
      72,
      (ByteData(8)
            ..setInt32(0, x, Endian.little)
            ..setInt32(4, y, Endian.little))
          .buffer
          .asUint8List(),
    );
  }
  if (box != null) {
    final data = ByteData(16);
    for (final (k, value) in [box.x0, box.y0, box.x1, box.y1].indexed) {
      data.setInt32(4 * k, value, Endian.little);
    }
    parameter(42, data.buffer.asUint8List());
    final size =
        boxSize ?? (width: box.x1 - box.x0, height: box.y1 - box.y0);
    parameter(
      63,
      (ByteData(8)
            ..setInt32(0, size.width, Endian.little)
            ..setInt32(4, size.height, Endian.little))
          .buffer
          .asUint8List(),
    );
    // Clockwise from the top-left, in hundredths of a pixel.
    final square = [
      for (final (x, y) in [
        (box.x0, box.y0),
        (box.x1, box.y0),
        (box.x1, box.y1),
        (box.x0, box.y1),
      ]) ...[x * 100, y * 100],
    ];
    final data64 = ByteData(32);
    for (final (k, value) in (corners ?? square).indexed) {
      data64.setInt32(4 * k, value, Endian.little);
    }
    if (withCorners) {
      parameter(64, data64.buffer.asUint8List());
    }
  }
  return out.toBytes();
}

/// [parts] as a text layer's `…Array` column keeps its second text on:
/// `u32 LE length · bytes`, again and again.
Uint8List clipTextArrayBytes(List<List<int>> parts) => (BytesBuilder()
      ..add([
        for (final part in parts) ...[..._le32(part.length), ...part],
      ]))
    .toBytes();
