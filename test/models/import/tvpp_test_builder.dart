import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Builds synthetic .tvpp byte streams for the parser and raster-decoder
/// tests.
///
/// Real project files are megabytes of pixels, so the suite builds its
/// own from the measured spec instead (memory `tvpp-format-notes`; every
/// layout rule here was verified against TVPaint's own JSON/PNG export —
/// 376/376 images pixel-perfect). The builder is intentionally a SECOND
/// implementation of the format: encoder and decoder meeting in the
/// middle is the round-trip evidence, and any spec drift breaks both.
class TvppBuilder {
  final _out = BytesBuilder();

  Uint8List get bytes => _out.toBytes();

  void chunk(String fourCc, List<int> payload) {
    _out.add(ascii.encode(fourCc));
    _out.add(_u32(payload.length));
    _out.add(payload);
    if (payload.length.isOdd) {
      _out.addByte(0); // odd lengths pad by one — the 2.3% trap.
    }
  }

  void _prop(String key, String value) {
    _out.add(_u16(key.length));
    for (final c in key.codeUnits) {
      _out.add(_u16(c));
    }
    _out.add(_u16(value.length));
    for (final c in value.codeUnits) {
      _out.add(_u16(c));
    }
  }

  /// The file-head property block: the PROJECT's shooting frame lives
  /// here as `Camera.Width` / `Camera.Height`.
  void projectProperties({
    required int cameraWidth,
    required int cameraHeight,
  }) {
    _prop('Author', 'test');
    _prop('Camera.Height', '$cameraHeight');
    _prop('Camera.Width', '$cameraWidth');
  }

  /// The UTF-16BE property block that precedes a clip's chunk chain; the
  /// parser only reads `Name`, but a sibling key proves it picks the
  /// right pair.
  void clipProperties(String name) {
    _prop('Position', '0');
    _prop('Name', name);
    _prop('Note', '');
  }

  /// DLOC..TLNT — the fixed chain that runs straight into the first
  /// layer, byte-identical across every measured version (EMS=10, KLM=12.1).
  void clipHeader({
    required int width,
    required int height,
    double frameRate = 24,
    List<(int layer, int frame, int color)> imageMarks = const [],
  }) {
    chunk('DLOC', [..._u16(width), ..._u16(height), 0, 0, 0, 0]);
    chunk('BGMD', _u32(8));
    chunk('ARAT', [..._u32(1000000), ..._u32(1000000)]);
    chunk('CRLR', _u32(3));
    chunk('BGP1', [0xff, 0xff, 0xff, 0xff]);
    chunk('BGP2', [0xe9, 0xe9, 0xe9, 0xff]);
    chunk('ANNO', ascii.encode('test\x00'));
    chunk('FRAT', _u32((frameRate * 1000).round()));
    chunk('FILD', [..._u32(5), ..._u32(1)]);
    chunk('MARK', const []);
    if (imageMarks.isNotEmpty) {
      chunk('IMRK', [
        for (final (layer, frame, color) in imageMarks) ...[
          ..._u32(layer),
          ..._u32(frame),
          ..._u32(color),
        ],
      ]);
    }
    chunk('XSHT', [..._u32(0), ..._u32(0), ..._u32(5000)]);
    chunk('TLNT', List.filled(80, 0));
  }

  /// LNAM/LNAW + the 104-byte layer header. [headerChunk] picks the
  /// layer kind: LRHD raster, LRCA camera, LRFH folder, LRSH ctg.
  void layerHead(
    String name, {
    String headerChunk = 'LRHD',
    int start = 0,
    int end = 0,
    int count = 1,
    int opacity = 255,
    int pre = 0,
    int post = 0,
    int layerId = 0,
    int parentId = 0,
    bool visible = true,
    List<int>? ansiNameBytes,
  }) {
    final utf = [...utf8.encode(name), 0];
    // 12.0.6 writes the ANSI codepage into LNAM and the unicode name
    // into LNAW; [ansiNameBytes] simulates that split.
    chunk('LNAM', ansiNameBytes ?? utf);
    chunk('LNAW', utf);
    final header = Uint8List(104);
    final v = ByteData.sublistView(header);
    v.setUint32(0, 1);
    v.setUint32(1 * 4, start);
    v.setUint32(2 * 4, end);
    v.setUint32(3 * 4, count);
    v.setUint32(4 * 4, opacity);
    v.setUint32(11 * 4, (post << 16) | 1);
    v.setUint32(13 * 4, (pre << 16) | 1);
    v.setUint32(14 * 4, (visible ? 1 : 0) << 16);
    v.setUint32(17 * 4, parentId);
    v.setUint32(18 * 4, layerId);
    chunk(headerChunk, header);
  }

  void layerExt(Map<int, String> instanceNames) {
    final sb = StringBuffer('\u{FEFF}[images auid]\n');
    sb.write('\n[images name]\n');
    instanceNames.forEach((slot, name) {
      sb.write('$slot=$name\n');
    });
    chunk('LEXT', utf8.encode(sb.toString()));
    chunk('UDAT', List.filled(24, 0));
  }

  /// A v12 image slot: the record zlib-wrapped in a ZCHK. [blocks] > 1
  /// splits the record into that many separately-deflated streams laid
  /// back to back — how real files store anything past 64KB.
  void zchkSlot(Uint8List record, {int blocks = 1}) {
    final streams = <int>[];
    final per = (record.length / blocks).ceil();
    for (var i = 0; i < record.length; i += per) {
      final end = (i + per) > record.length ? record.length : i + per;
      streams.addAll(ZLibEncoder().convert(record.sublist(i, end)));
    }
    chunk('ZCHK', [
      ...record.sublist(0, 4), // the record's own magic heads the header
      ..._u32(record.length - 8),
      ...ascii.encode('czmp'),
      ..._u32(streams.length),
      ..._u32(blocks),
      ..._u32(100),
      ..._u32(per),
      ..._u32(streams.length),
      ...streams,
    ]);
  }

  /// A v12 hold slot (the 20-byte type-6 record; its block-raw field of
  /// 20 is what the parser classifies on).
  void zchkHold() => zchkSlot(holdRecord());

  /// A v10 image slot: the record body as a bare top-level chunk.
  void rawSlot(Uint8List record) {
    final magic = String.fromCharCodes(record, 0, 4);
    chunk(magic, record.sublist(8));
  }

  void clipConfig({
    String cameraData = '',
    List<(String path, double offset, double volume, bool mute)> audio =
        const [],
  }) {
    final sb = StringBuffer('\u{FEFF}[info]\ncreationos=TEST\n');
    if (audio.isNotEmpty) {
      sb.write('\n[audio]\ntrackcount=${audio.length}\nvolume=1.000000\n');
      for (final (i, (path, offset, volume, mute)) in audio.indexed) {
        sb
          ..write('\n[audio+$i]\n')
          ..write('filepath=$path\n')
          ..write('offset=${offset.toStringAsFixed(6)}\n')
          ..write('volume=${volume.toStringAsFixed(6)}\n')
          ..write('mute=${mute ? 1 : 0}\n');
      }
    }
    if (cameraData.isNotEmpty) {
      sb.write('\n[cameradata]\n$cameraData');
    }
    chunk('FCFG', utf8.encode(sb.toString()));
    chunk('TMST', List.filled(118, 0));
  }

  static List<int> _u16(int v) => [(v >> 8) & 0xff, v & 0xff];

  static List<int> _u32(int v) =>
      [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];
}

// ---------------------------------------------------------------------------
// Record encoders (PackBits + tiles), the mirror of the decoder.
// ---------------------------------------------------------------------------

Uint8List holdRecord() {
  final record = Uint8List(20);
  record.setAll(0, ascii.encode('SRAW'));
  final v = ByteData.sublistView(record);
  v.setUint32(4, 12);
  v.setUint32(8, 6);
  v.setUint32(12, 1);
  return record;
}

/// The 28-byte type-5 record 12.0.6 writes for a BLANK instance (zero
/// payload); 12.1 writes a contentless type-64 for the same thing.
Uint8List blankInstanceRecord() {
  final record = Uint8List(28);
  record.setAll(0, ascii.encode('SRAW'));
  final v = ByteData.sublistView(record);
  v.setUint32(4, 20);
  v.setUint32(8, 5);
  return record;
}

/// PackBits over premultiplied-BGRA words: runs are `257 - c` long
/// (encoder cap 124, matching TVPaint's own output), literals `c + 1`.
/// Each row is encoded independently — a run never crosses rows.
List<int> encodeRows(List<List<int>> rows) {
  final out = <int>[];
  for (final row in rows) {
    var i = 0;
    while (i < row.length) {
      var run = 1;
      while (i + run < row.length && row[i + run] == row[i] && run < 124) {
        run++;
      }
      if (run >= 2) {
        out.add(257 - run);
        out.add((row[i] >> 24) & 0xff);
        out.add((row[i] >> 16) & 0xff);
        out.add((row[i] >> 8) & 0xff);
        out.add(row[i] & 0xff);
        i += run;
      } else {
        var literal = 1;
        while (i + literal < row.length &&
            literal < 128 &&
            (i + literal + 1 >= row.length ||
                row[i + literal] != row[i + literal + 1])) {
          literal++;
        }
        out.add(literal - 1);
        for (var k = 0; k < literal; k++) {
          final v = row[i + k];
          out.add((v >> 24) & 0xff);
          out.add((v >> 16) & 0xff);
          out.add((v >> 8) & 0xff);
          out.add(v & 0xff);
        }
        i += literal;
      }
    }
  }
  return out;
}

/// A whole-canvas DBOD record for [pixels] (width*height premultiplied
/// BGRA words).
Uint8List dbodRecord(List<int> pixels, int width, int height) {
  final rows = [
    for (var y = 0; y < height; y++)
      pixels.sublist(y * width, (y + 1) * width),
  ];
  final body = encodeRows(rows);
  final record = Uint8List(8 + body.length);
  record.setAll(0, ascii.encode('DBOD'));
  ByteData.sublistView(record).setUint32(4, body.length);
  record.setAll(8, body);
  return record;
}

/// A tiled SRAW record for [pixels]. [uniformMode] selects the X == 0
/// tile encoding (12-byte records with data chains); otherwise the
/// X > 0 layout (bare first tile, copy markers, sized tiles) is used.
Uint8List srawRecord(
  List<int> pixels,
  int width,
  int height, {
  bool uniformMode = false,
}) {
  const tile = 64;
  final cols = (width + tile - 1) ~/ tile;
  final rows = (height + tile - 1) ~/ tile;
  final total = cols * rows;

  List<List<int>> tileRows(int t) {
    final tr = t ~/ cols, tc = t % cols;
    final tw = tc == cols - 1 ? width - tc * tile : tile;
    final th = tr == rows - 1 ? height - tr * tile : tile;
    return [
      for (var y = 0; y < th; y++)
        [
          for (var x = 0; x < tw; x++)
            pixels[(tr * tile + y) * width + (tc * tile + x)],
        ],
    ];
  }

  bool tileEmpty(int t) =>
      tileRows(t).every((row) => row.every((v) => v == 0));

  final body = <int>[];
  // Thumbnail: 96×67 of transparent — content correctness of the
  // thumbnail is TVPaint's problem, the decoder only skips it.
  body.addAll(encodeRows([
    for (var y = 0; y < 67; y++) List.filled(96, 0),
  ]));

  List<int> u32(int v) =>
      [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

  if (!uniformMode) {
    final tile0 = encodeRows(tileRows(0));
    // Table: (total, X) where X is tile 0's byte size.
    body.addAll([...u32(total), ...u32(tile0.length)]);
    body.addAll(tile0);
    for (var t = 1; t < total; t++) {
      // TVPaint dedupes identical tiles into copy markers — solid fills
      // arrive this way, so the encoder must produce them for the
      // decoder's copy path to be tested at all.
      var src = -1;
      final mine = tileRows(t);
      for (var s = 0; s < t && src < 0; s++) {
        final other = tileRows(s);
        if (other.length == mine.length &&
            List.generate(mine.length, (y) => y).every(
              (y) =>
                  other[y].length == mine[y].length &&
                  List.generate(mine[y].length, (x) => x)
                      .every((x) => other[y][x] == mine[y][x]),
            )) {
          src = s;
        }
      }
      if (src >= 0) {
        body.addAll([...u32(0), ...u32(0), ...u32(src)]);
      } else if (tileEmpty(t)) {
        body.addAll([...u32(0), ...u32(0), ...u32((t ~/ cols) * cols)]);
      } else {
        final data = encodeRows(tileRows(t));
        body.addAll(u32(data.length));
        body.addAll(data);
      }
    }
  } else {
    body.addAll([...u32(total), ...u32(0)]);
    var t = 0;
    while (t < total) {
      if (t + 1 < total && !tileEmpty(t + 1)) {
        // (a, anchor, size): tile t stays empty, the data belongs to
        // t+1; chain further non-empty neighbours with bare u32 sizes.
        final first = encodeRows(tileRows(t + 1));
        body.addAll([...u32(0), ...u32((t ~/ cols) * cols), ...u32(first.length)]);
        body.addAll(first);
        var ti = t + 2;
        while (ti < total && !tileEmpty(ti)) {
          final data = encodeRows(tileRows(ti));
          body.addAll(u32(data.length));
          body.addAll(data);
          ti++;
        }
        body.addAll(u32(0)); // chain terminator
        t = ti;
      } else {
        body.addAll([...u32(0), ...u32((t ~/ cols) * cols), ...u32(0)]);
        t += 1;
      }
    }
  }

  final record = Uint8List(24 + body.length);
  record.setAll(0, ascii.encode('SRAW'));
  final v = ByteData.sublistView(record);
  v.setUint32(4, 16 + body.length); // total-8, matching the ZCHK field
  v.setUint32(8, 64);
  v.setUint32(12, 0); // N — unused by the decoder
  v.setUint32(16, 96);
  v.setUint32(20, 67);
  record.setAll(24, body);
  return record;
}

/// The ceiling premultiply the format uses: straight RGBA → BGRA word.
int premulBgra(int r, int g, int b, int a) {
  int p(int v) => (v * a + 254) ~/ 255;
  return (p(b) << 24) | (p(g) << 16) | (p(r) << 8) | a;
}
