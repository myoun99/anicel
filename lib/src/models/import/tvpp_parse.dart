import 'tvpp_camera_data_values.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'tvp_import_model.dart';

/// TVPaint's own project file (.tvpp), read directly — structure only.
///
/// This parser covers everything the import needs EXCEPT pixels: clips,
/// layers (with folder tree), per-frame slots, instance names, image
/// marks, and the camera's authored keys. Pixel decoding needs zlib and
/// lives in `tvpp_raster_decoder.dart` (services); this file stays pure
/// so the whole interpretation is testable from bytes alone.
///
/// ## Format (measured 2026-08-15/26, spec in memory `tvpp-format-notes`)
///
/// The file is an IFF-style chunk stream: `FourCC` + u32BE length +
/// payload, ODD lengths padded by one byte. Before the first clip sits
/// project-level data (UTF-16BE key/value properties, a preview bitmap);
/// each clip contributes:
///
///   [UTF-16BE property block: ... "Name" <clip name> ...]
///   DLOC(u16 W, u16 H) BGMD ARAT(aspect ×1e6 ×2) CRLR BGP1 BGP2 ANNO
///   FRAT(fps ×1000) FILD MARK [IMRK] XSHT TLNT
///   [LNAM/LNAW/LR??/LEXT/UDAT + images] × layers
///   FCFG (clip config INI — `[cameradata]` lives here) STCK XSRC TMST
///
/// Everything was verified against TVPaint's own JSON/PNG export of the
/// same clip (376/376 images pixel-perfect, 30/30 layer behaviours).
///
/// ## v10 vs v11+ (verified: EMS 2017 = 10.0.16, KG = 11.0.9, 288 = 12.0.6,
/// KLM/SKH/SKK = 12.1.0)
///
/// v11 and later wrap every image in a zlib'd `ZCHK`; v10 stores the same `SRAW` /
/// `DBOD` records uncompressed as top-level chunks. Structure chunks are
/// identical, so this parser only branches on which image chunk it meets.
class TvppParseException implements Exception {
  const TvppParseException(this.message);

  final String message;

  @override
  String toString() => 'TvppParseException: $message';
}

/// What one timeline slot holds. One slot = one frame (verified: LRHD's
/// start/end/count always satisfy count == end - start + 1, including
/// CON's offset start and SKK's varied layers).
enum TvppSlotKind {
  /// A 20-byte type-6 record: no image here — the previous instance's
  /// exposure continues. (NOT a blank cel; blanks are [image] slots whose
  /// raster decodes to zero pixels — seen live in KLM C_KAKI slots 10/28.)
  hold,

  /// A raster record: a new instance starts on this frame. Whether it has
  /// pixels is only known after decoding.
  image,
}

/// Where a slot's image bytes live, so the raster decoder can find them
/// without re-walking the file.
class TvppSlot {
  const TvppSlot({
    required this.kind,
    required this.chunkOffset,
    required this.chunkLength,
    required this.compressed,
    this.v10WholeCanvas = false,
  });

  final TvppSlotKind kind;

  /// Offset of the image chunk's PAYLOAD (past FourCC + length) in the
  /// file, and that payload's length. For v12 this is the ZCHK payload
  /// (zlib chain inside); for v10 the raw SRAW/DBOD record body.
  final int chunkOffset;
  final int chunkLength;

  /// True for v12's ZCHK wrapping (zlib chain), false for v10's raw
  /// records.
  final bool compressed;

  /// v10 only: whether the bare record came from a `DBOD` chunk (whole
  /// canvas) rather than `SRAW`. v12 records carry their own magic, so
  /// the decoder ignores this when [compressed].
  final bool v10WholeCanvas;
}

/// The layer kinds the format distinguishes (by header chunk name).
enum TvppLayerKind {
  /// `LRHD` — an ordinary raster animation layer.
  raster,

  /// `LRCA` — the clip's camera layer (each clip's first layer). The JSON
  /// export omits it from the layer list; the converter does the same.
  camera,

  /// `LRFH` — a folder. Carries no images; children point at it via
  /// [TvppLayer.parentId].
  folder,

  /// `LRSH` — a CTG layer. Its images come as TWO streams split by a
  /// zero-length `LRSR` marker (line and colour sources).
  ctg,
}

class TvppLayer {
  const TvppLayer({
    required this.kind,
    required this.name,
    required this.layerId,
    required this.parentId,
    required this.start,
    required this.end,
    required this.opacity,
    required this.preBehavior,
    required this.postBehavior,
    required this.slots,
    required this.ctgSecondStream,
    required this.instanceNames,
    this.visible = true,
  });

  /// LRHD[7] bit 0 says HIDDEN (bit 4 is the layer lock). Pinned 19/19
  /// against 288's own timeline screenshot and KLM's JSON (TAP·CON
  /// hidden, F_n visible). ⚠️The first reading — LRHD[14] hi16 bit 0 —
  /// was the COLOUR-GROUP index's parity: KLM's three probes matched by
  /// luck (TAP=1, F_n=5, CON=0), and 288 imported half its stack wrong.
  /// [14] hi16 is the guigroup index; the import does not read it (the
  /// user's call: 색라벨 안 읽어도 된다).
  final bool visible;

  final TvppLayerKind kind;
  final String name;

  /// LRHD[18] / LRHD[17]: this layer's id and its folder's id (0 = root).
  /// v10 files carry 0/0 — no folders there.
  final int layerId;
  final int parentId;

  /// LRHD[1] / LRHD[2]: the frame range `start..end` inclusive. Slot k of
  /// [slots] is frame `start + k`.
  final int start;
  final int end;

  /// LRHD[4]: 0..255.
  final int opacity;

  /// LRHD[13] hi16 (pre) / LRHD[11] hi16 (post) — same wire values as the
  /// JSON export's pre/post-behavior, confirmed 30/30 on KLM. SKK pinned
  /// the previously-unseen value: 2 IS ping-pong.
  final TvpEdgeBehavior preBehavior;
  final TvpEdgeBehavior postBehavior;

  final List<TvppSlot> slots;

  /// CTG only: the second image stream (after the `LRSR` separator);
  /// empty for every other kind.
  final List<TvppSlot> ctgSecondStream;

  /// LEXT `[images name]`: slot index → instance name. Slots without an
  /// entry are unnamed (TVPaint's 「빈 인스턴스」 axis).
  final Map<int, String> instanceNames;

  int get frameCount => end - start + 1;
}

/// One `IMRK` record: an image mark ("중간나누기" in the user's workflow)
/// on [frame] of layer index [layerIndex] (0 = the camera layer).
class TvppImageMark {
  const TvppImageMark({
    required this.layerIndex,
    required this.frame,
    required this.colorIndex,
  });

  final int layerIndex;
  final int frame;
  final int colorIndex;
}

/// One authored camera key from `[cameradata]`. Unlike the JSON export
/// there are NO baked per-frame positions in the file — evaluating the
/// path (bezier + position profile) is the importer's job.
class TvppCameraPoint {
  const TvppCameraPoint({
    required this.x,
    required this.y,
    required this.rotationDegrees,
    required this.zoomFactor,
    required this.sizeX,
    required this.sizeY,
    required this.instant,
    this.flags = 15,
    required this.bezierBeforeX,
    required this.bezierBeforeY,
    required this.bezierAfterX,
    required this.bezierAfterY,
  });

  final double x;
  final double y;
  final double rotationDegrees;
  final double zoomFactor;
  final double sizeX;
  final double sizeY;

  /// The key's time position (frames; 0-based).
  final int instant;

  /// Which channels this key authors (bits: 1=position, 2=rotation,
  /// 4=zoom, 8=size; observed values 1 and 15). Absent = 15 — a fully
  /// authored key, which is what every first key is.
  final int flags;

  final double bezierBeforeX;
  final double bezierBeforeY;
  final double bezierAfterX;
  final double bezierAfterY;
}

/// One `[audio+N]` sound track of a clip: a REFERENCE (the file is not
/// embedded), plus where and how loud.
class TvppAudioTrack {
  const TvppAudioTrack({
    required this.filePath,
    required this.offsetSeconds,
    required this.volume,
    required this.muted,
  });

  final String filePath;

  /// The track's slide on the timeline, in seconds.
  final double offsetSeconds;

  /// 0..1-ish gain (TVPaint allows over 1).
  final double volume;

  final bool muted;
}

class TvppClip {
  const TvppClip({
    required this.name,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.pixelAspectRatio,
    required this.layers,
    required this.imageMarks,
    required this.cameraPoints,
    required this.cameraDataText,
    this.audioTracks = const [],
  });

  final String name;
  final int width;
  final int height;
  final double frameRate;
  final double pixelAspectRatio;

  /// In file (= stack) order, camera layer included — the converter
  /// filters. IMRK layer indexes count into THIS list.
  final List<TvppLayer> layers;

  final List<TvppImageMark> imageMarks;

  /// Authored keys, sorted by [TvppCameraPoint.instant]. Empty = no
  /// camera work (matches the JSON path's "points empty ⇒ no camera").
  final List<TvppCameraPoint> cameraPoints;

  /// The raw `[cameradata]` INI text, kept for the parts the point model
  /// does not carry yet (position profiles for eased moves).
  final String cameraDataText;

  /// The clip's sound tracks (`[audio+N]` in the clip config) — measured
  /// live on KLM, where every cut references its rushes as an .mp4.
  final List<TvppAudioTrack> audioTracks;

  /// The clip's length: the furthest layer extent, the CAMERA layer
  /// included — its span is how a clip longer than its drawings records
  /// that length (PROFILE_CAL: a 49-frame clip whose one drawing spans a
  /// single frame carries end=48 on the camera layer; KLM's cameras sit
  /// at end=0 and its rasters carry the length instead).
  int get frameCount {
    var end = -1;
    for (final layer in layers) {
      if (layer.end > end) {
        end = layer.end;
      }
    }
    return end + 1;
  }
}

class TvppParseResult {
  const TvppParseResult({
    required this.clips,
    required this.warnings,
    this.projectCameraWidth,
    this.projectCameraHeight,
  });

  final List<TvppClip> clips;
  final List<String> warnings;

  /// The PROJECT's shooting frame (`Camera.Width` / `Camera.Height` in
  /// the file-head property block — 288 shoots 960×430 while its canvas
  /// is 2339×1653). Null when the block does not carry them.
  final int? projectCameraWidth;
  final int? projectCameraHeight;
}

// ---------------------------------------------------------------------------
// Chunk-level readers
// ---------------------------------------------------------------------------

bool _isFourCc(Uint8List bytes, int at) {
  if (at + 4 > bytes.length) {
    return false;
  }
  for (var k = 0; k < 4; k++) {
    final c = bytes[at + k];
    final ok =
        (c >= 0x41 && c <= 0x5a) ||
        (c >= 0x61 && c <= 0x7a) ||
        (c >= 0x30 && c <= 0x39);
    if (!ok) {
      return false;
    }
  }
  return true;
}

int _u32(Uint8List bytes, int at) =>
    ByteData.sublistView(bytes, at, at + 4).getUint32(0);

int _find(Uint8List bytes, String needle, int from, [int? until]) {
  final t = needle.codeUnits;
  final end = (until ?? bytes.length) - t.length;
  for (var i = from; i <= end; i++) {
    var ok = true;
    for (var k = 0; k < t.length; k++) {
      if (bytes[i + k] != t[k]) {
        ok = false;
        break;
      }
    }
    if (ok) {
      return i;
    }
  }
  return -1;
}

/// UTF-8, stopping at the first NUL: LNAM/LNAW carry the name twice in
/// the same encoding (measured — the "wide" chunk is not UTF-16), padded
/// to the chunk length.
String _nameFrom(Uint8List bytes, int at, int length) {
  var end = at;
  final limit = at + length;
  while (end < limit && bytes[end] != 0) {
    end++;
  }
  return utf8.decode(bytes.sublist(at, end), allowMalformed: true);
}

TvpEdgeBehavior _edgeBehavior(int wire) => switch (wire) {
  1 => TvpEdgeBehavior.repeat,
  2 => TvpEdgeBehavior.pingPong,
  3 => TvpEdgeBehavior.hold,
  _ => TvpEdgeBehavior.none,
};

// ---------------------------------------------------------------------------
// Parse
// ---------------------------------------------------------------------------

/// Parses the whole file's structure. Throws [TvppParseException] when the
/// bytes are not a TVPaint project this reader understands.
TvppParseResult parseTvppStructure(Uint8List bytes) {
  final warnings = <String>[];

  // Clip regions begin at their DLOC chunk (the fixed header chain
  // DLOC..TLNT runs straight into the first LNAM — byte-identical layout
  // across every measured version). Everything between the previous clip's end and DLOC
  // is project/preview data plus the clip's UTF-16 property block.
  final clipStarts = <int>[];
  var scan = 0;
  while (true) {
    final at = _find(bytes, 'DLOC', scan);
    if (at < 0) {
      break;
    }
    // A real DLOC is 8 bytes: u16 W, u16 H, u32 0 — cheap validation that
    // also skips the string appearing inside pixel data.
    if (_u32(bytes, at + 4) == 8 && _u32(bytes, at + 12) == 0) {
      clipStarts.add(at);
      scan = at + 8;
    } else {
      scan = at + 4;
    }
  }
  if (clipStarts.isEmpty) {
    throw const TvppParseException('DLOC 청크가 없다 — TVPaint 프로젝트가 아니다.');
  }

  final clips = <TvppClip>[];
  for (var c = 0; c < clipStarts.length; c++) {
    final start = clipStarts[c];
    final end = c + 1 < clipStarts.length ? clipStarts[c + 1] : bytes.length;
    final nameFrom = c == 0 ? 0 : clipStarts[c - 1];
    clips.add(_parseClip(bytes, start, end, nameFrom, c, warnings));
  }
  return TvppParseResult(
    clips: clips,
    warnings: warnings,
    projectCameraWidth: _projectProperty(bytes, 'Camera.Width'),
    projectCameraHeight: _projectProperty(bytes, 'Camera.Height'),
  );
}

/// Reads an integer project property from the file-head UTF-16BE block:
/// `[u16 keyLen][key as u16 chars][u16 valLen][value as u16 chars]`.
/// Scans the region before the first clip only.
int? _projectProperty(Uint8List bytes, String key) {
  final needle = Uint8List(2 + key.length * 2);
  ByteData.sublistView(needle).setUint16(0, key.length);
  for (var i = 0; i < key.length; i++) {
    ByteData.sublistView(needle).setUint16(2 + i * 2, key.codeUnitAt(i));
  }
  final limit = bytes.length < 1 << 20 ? bytes.length : 1 << 20;
  outer:
  for (var i = 0; i + needle.length + 2 < limit; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) {
        continue outer;
      }
    }
    final at = i + needle.length;
    final valLen = ByteData.sublistView(bytes).getUint16(at);
    if (valLen == 0 || valLen > 16 || at + 2 + valLen * 2 > bytes.length) {
      return null;
    }
    final chars = <int>[];
    for (var k = 0; k < valLen; k++) {
      chars.add(ByteData.sublistView(bytes).getUint16(at + 2 + k * 2));
    }
    return int.tryParse(String.fromCharCodes(chars));
  }
  return null;
}

/// The clip name lives in a UTF-16BE property list BEFORE the clip's
/// DLOC: `... [u16 4]"Name" [u16 n]<value> ...`. The LAST such pair
/// before DLOC belongs to this clip.
String _clipName(Uint8List bytes, int from, int until, int clipIndex) {
  const key = <int>[0x00, 0x04, 0x00, 0x4e, 0x00, 0x61, 0x00, 0x6d, 0x00, 0x65];
  var best = -1;
  var scan = from;
  while (true) {
    var at = -1;
    for (var i = scan; i + key.length <= until; i++) {
      var ok = true;
      for (var k = 0; k < key.length; k++) {
        if (bytes[i + k] != key[k]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        at = i;
        break;
      }
    }
    if (at < 0) {
      break;
    }
    best = at;
    scan = at + key.length;
  }
  if (best < 0) {
    return 'Clip ${clipIndex + 1}';
  }
  final valueAt = best + key.length;
  if (valueAt + 2 > until) {
    return 'Clip ${clipIndex + 1}';
  }
  final n = ByteData.sublistView(bytes, valueAt, valueAt + 2).getUint16(0);
  final chars = <int>[];
  for (var i = 0; i < n && valueAt + 2 + i * 2 + 2 <= until; i++) {
    chars.add(
      ByteData.sublistView(
        bytes,
        valueAt + 2 + i * 2,
        valueAt + 4 + i * 2,
      ).getUint16(0),
    );
  }
  final name = String.fromCharCodes(chars);
  return name.isEmpty ? 'Clip ${clipIndex + 1}' : name;
}

TvppClip _parseClip(
  Uint8List bytes,
  int start,
  int end,
  int nameFrom,
  int clipIndex,
  List<String> warnings,
) {
  var width = 0;
  var height = 0;
  var frameRate = 24.0;
  var pixelAspectRatio = 1.0;
  final marks = <TvppImageMark>[];
  final layers = <TvppLayer>[];
  var cameraDataText = '';
  var audioTracks = const <TvppAudioTrack>[];

  // Per-layer accumulation state.
  String? name;
  var kind = TvppLayerKind.raster;
  Uint8List? header;
  var slots = <TvppSlot>[];
  var secondStream = <TvppSlot>[];
  var inSecondStream = false;
  var instanceNames = <int, String>{};

  void flushLayer() {
    final n = name;
    if (n == null) {
      return;
    }
    final v = header != null ? ByteData.sublistView(header!) : null;
    int field(int index) => v != null && header!.length >= (index + 1) * 4
        ? v.getUint32(index * 4)
        : 0;
    layers.add(
      TvppLayer(
        kind: kind,
        name: n,
        layerId: field(18),
        parentId: field(17),
        start: field(1),
        end: field(2),
        opacity: header != null ? field(4) : 255,
        preBehavior: _edgeBehavior(field(13) >> 16),
        postBehavior: _edgeBehavior(field(11) >> 16),
        visible: header == null || field(7) & 1 == 0,
        slots: List.unmodifiable(slots),
        ctgSecondStream: List.unmodifiable(secondStream),
        instanceNames: Map.unmodifiable(instanceNames),
      ),
    );
    name = null;
    kind = TvppLayerKind.raster;
    header = null;
    slots = <TvppSlot>[];
    secondStream = <TvppSlot>[];
    inSecondStream = false;
    instanceNames = <int, String>{};
  }

  void addSlot(TvppSlot slot) {
    (inSecondStream ? secondStream : slots).add(slot);
  }

  var p = start;
  var closed = false;
  while (p + 8 <= end && !closed) {
    if (!_isFourCc(bytes, p)) {
      warnings.add('클립 ${clipIndex + 1}: @$p 에서 청크 열이 끊겼다 — 이후 데이터는 버린다.');
      break;
    }
    final chunk = String.fromCharCodes(bytes, p, p + 4);
    final length = _u32(bytes, p + 4);
    final payload = p + 8;
    if (payload + length > end) {
      break;
    }

    switch (chunk) {
      case 'DLOC':
        final v = ByteData.sublistView(bytes, payload, payload + 8);
        width = v.getUint16(0);
        height = v.getUint16(2);
      case 'ARAT':
        if (length >= 8) {
          final v = ByteData.sublistView(bytes, payload, payload + 8);
          final a = v.getUint32(0);
          final b = v.getUint32(4);
          if (a > 0 && b > 0) {
            pixelAspectRatio = a / b;
          }
        }
      case 'FRAT':
        if (length >= 4) {
          frameRate = _u32(bytes, payload) / 1000.0;
        }
      case 'IMRK':
        for (var i = 0; i + 12 <= length; i += 12) {
          final v = ByteData.sublistView(bytes, payload + i, payload + i + 12);
          marks.add(
            TvppImageMark(
              layerIndex: v.getUint32(0),
              frame: v.getUint32(4),
              colorIndex: v.getUint32(8),
            ),
          );
        }
      case 'LNAM':
        flushLayer();
        name = _nameFrom(bytes, payload, length);
      case 'LNAW':
        // The unicode name. 12.1 writes UTF-8 into both chunks, but
        // 12.0.6 puts the ANSI codepage (Shift-JIS on the user's
        // machine) into LNAM — 288's カメラレイヤー arrives as mojibake
        // unless the wide chunk wins.
        final wide = _nameFrom(bytes, payload, length);
        if (wide.isNotEmpty) {
          name = wide;
        }
      case 'LRHD':
        kind = TvppLayerKind.raster;
        header = Uint8List.sublistView(bytes, payload, payload + length);
      case 'LRCA':
        kind = TvppLayerKind.camera;
        header = Uint8List.sublistView(bytes, payload, payload + length);
      case 'LRFH':
        kind = TvppLayerKind.folder;
        header = Uint8List.sublistView(bytes, payload, payload + length);
      case 'LRSH':
        kind = TvppLayerKind.ctg;
        header = Uint8List.sublistView(bytes, payload, payload + length);
      case 'LRSR':
        // Zero-length separator between a CTG layer's two image streams.
        inSecondStream = true;
      case 'LEXT':
        final text = _printable(bytes, payload, length);
        instanceNames = _imagesNameTable(text);
      case 'ZCHK':
        // v12: [SRAW u32 rawLen-8]['czmp' u32][blocks][100][blockRaw]
        // [blockComp][zlib...]. The block-raw field (offset 24) is 20
        // exactly for the type-6 "no image" record — classification
        // without touching zlib.
        final blockRaw = length >= 28 ? _u32(bytes, payload + 24) : 0;
        addSlot(
          TvppSlot(
            kind: blockRaw == 20 ? TvppSlotKind.hold : TvppSlotKind.image,
            chunkOffset: payload,
            chunkLength: length,
            compressed: true,
          ),
        );
      case 'SRAW':
        // v10: the bare record body — the chunk header IS the record's
        // magic+length, so the body starts at the type word: 6 = hold.
        final type = length >= 4 ? _u32(bytes, payload) : 0;
        addSlot(
          TvppSlot(
            kind: type == 6 ? TvppSlotKind.hold : TvppSlotKind.image,
            chunkOffset: payload,
            chunkLength: length,
            compressed: false,
          ),
        );
      case 'DBOD':
        // v10 keyframe (whole-canvas record), uncompressed.
        addSlot(
          TvppSlot(
            kind: TvppSlotKind.image,
            chunkOffset: payload,
            chunkLength: length,
            compressed: false,
            v10WholeCanvas: true,
          ),
        );
      case 'FCFG':
        // UTF-8, not the printable filter: `[audio+N]` carries file PATHS
        // and a mangled non-ASCII character breaks the reference.
        final text = utf8.decode(
          Uint8List.sublistView(bytes, payload, payload + length),
          allowMalformed: true,
        );
        final at = text.indexOf('[cameradata]');
        if (at >= 0) {
          cameraDataText = text.substring(at);
        }
        audioTracks = _audioTracks(text);
      case 'TMST':
        // Every clip ends on its timestamp chunk (measured on all
        // samples); what follows is the NEXT clip's property block and
        // preview data, which are not chunks.
        closed = true;
    }
    p = payload + length + (length & 1);
  }
  flushLayer();

  return TvppClip(
    name: _clipName(bytes, nameFrom, start, clipIndex),
    width: width,
    height: height,
    frameRate: frameRate,
    pixelAspectRatio: pixelAspectRatio,
    layers: List.unmodifiable(layers),
    imageMarks: List.unmodifiable(marks),
    cameraPoints: _cameraPoints(cameraDataText),
    cameraDataText: cameraDataText,
    audioTracks: audioTracks,
  );
}

/// `[audio+N]` sections of the clip config: one per sound track.
List<TvppAudioTrack> _audioTracks(String fcfgText) {
  final tracks = <TvppAudioTrack>[];
  for (var n = 0; ; n++) {
    final at = fcfgText.indexOf('[audio+$n]');
    if (at < 0) {
      break;
    }
    var end = fcfgText.indexOf('\n[', at + 1);
    if (end < 0) {
      end = fcfgText.length;
    }
    final values = <String, String>{};
    for (final line in fcfgText.substring(at, end).split('\n').skip(1)) {
      final eq = line.indexOf('=');
      if (eq > 0) {
        values[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
      }
    }
    final filePath = values['filepath'] ?? '';
    if (filePath.isEmpty) {
      continue;
    }
    tracks.add(
      TvppAudioTrack(
        filePath: filePath,
        offsetSeconds: double.tryParse(values['offset'] ?? '') ?? 0,
        volume: double.tryParse(values['volume'] ?? '') ?? 1,
        muted: values['mute'] == '1',
      ),
    );
  }
  return List.unmodifiable(tracks);
}

String _printable(Uint8List bytes, int at, int length) {
  final sb = StringBuffer();
  for (var i = at; i < at + length; i++) {
    final c = bytes[i];
    if ((c >= 0x20 && c < 0x7f) || c == 0x0a) {
      sb.writeCharCode(c);
    } else {
      sb.write(' ');
    }
  }
  return sb.toString();
}

/// LEXT carries INI text (`[images auid]`, `[images name]`). Only the
/// name table matters to the import; auids are per-slot-unique and carry
/// no linkage (measured — re-exposed drawings get fresh auids).
Map<int, String> _imagesNameTable(String text) {
  final at = text.indexOf('[images name]');
  if (at < 0) {
    return const {};
  }
  final names = <int, String>{};
  for (final line in text.substring(at).split('\n').skip(1)) {
    final t = line.trim();
    if (t.isEmpty) {
      continue;
    }
    if (t.startsWith('[')) {
      break;
    }
    final eq = t.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    final slot = int.tryParse(t.substring(0, eq));
    if (slot == null) {
      continue;
    }
    names[slot] = t.substring(eq + 1);
  }
  return names;
}

List<TvppCameraPoint> _cameraPoints(String cameraDataText) {
  if (cameraDataText.isEmpty) {
    return const [];
  }
  final values = tvppCameraDataValues(cameraDataText);
  double num(int i, String key, [double orElse = 0]) =>
      double.tryParse(values['mpoints-$i-$key'] ?? '') ?? orElse;
  final points = <TvppCameraPoint>[];
  for (var i = 0; values.containsKey('mpoints-$i-x'); i++) {
    points.add(
      TvppCameraPoint(
        x: num(i, 'x'),
        y: num(i, 'y'),
        rotationDegrees: num(i, 'rotation'),
        zoomFactor: num(i, 'zoomfactor', 1),
        sizeX: num(i, 'camerasizex'),
        sizeY: num(i, 'camerasizey'),
        instant: num(i, 'instant').round(),
        flags: num(i, 'flags', 15).round(),
        bezierBeforeX: num(i, 'bezierbeforex'),
        bezierBeforeY: num(i, 'bezierbeforey'),
        bezierAfterX: num(i, 'bezierafterx'),
        bezierAfterY: num(i, 'bezieraftery'),
      ),
    );
  }
  points.sort((a, b) => a.instant.compareTo(b.instant));
  return points;
}
