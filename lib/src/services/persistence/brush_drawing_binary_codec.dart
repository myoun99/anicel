/// Compact binary encoding for the .anicel container's cel payloads: one
/// entry per baked cel — key, canvas geometry, then raw straight-alpha
/// RGBA tile bytes. Little-endian throughout. (The v1 command-drawing
/// codec lived here until R20-E3 — deleted with the v1 reader; no
/// production v1 file was ever written.)
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'anicel_payload_codec.dart';
import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/cel_photo.dart';
import '../../models/cel_text.dart';
import '../../models/dirty_region.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/tile_coord.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/media_reference.dart';
import '../../models/project_id.dart';
import '../../models/track_id.dart';

/// One cel's BAKED raster — the persistence TRUTH from .anicel format v2 on
/// (R19 bake-only): what you saved is exactly what reopens, byte for
/// byte, with no re-materialization ever.
///
/// R19-Z: this is a PLAIN-BYTES snapshot ((coordX, coordY, rgba) records),
/// not a [BitmapSurface] — native-backed tiles are Finalizable and cannot
/// cross the save/open isolate boundary, so the boundary ships bytes and
/// each side converts with [AnicelCelEntry.fromSurface]/[toSurface].
class AnicelCelEntry {
  const AnicelCelEntry({
    required this.key,
    required this.canvasSize,
    required this.tileSize,
    required this.tiles,
    this.texts = const [],
    this.photos = const [],
    this.laidBounds,
  });

  factory AnicelCelEntry.fromSurface(BrushFrameKey key, BitmapSurface surface) {
    final parts = _partsOf(surface, (tile) => tile.pixels);
    return AnicelCelEntry(
      key: key,
      canvasSize: parts.canvasSize,
      tileSize: parts.tileSize,
      tiles: parts.tiles,
      texts: parts.texts,
      photos: parts.photos,
      laidBounds: parts.laidBounds,
    );
  }

  final BrushFrameKey key;
  final CanvasSize canvasSize;
  final int tileSize;
  final List<AnicelTileRecord> tiles;

  /// The texts the cel's picture carries, bottom → top: each one's id, what
  /// the person set (as JSON — plain data, like the tiles, so it crosses
  /// the isolate boundary) and its plate.
  final List<({int id, String content, List<AnicelTileRecord> plate})> texts;

  /// The photos the picture carries, bottom → top (I-97 — a sheet's ink).
  final List<AnicelPhotoRecord> photos;

  /// Where a file's picture lies on the cel, past the pasteboard where it
  /// is larger than the wall (`BitmapSurface.laidBounds`, F-374-Q8).
  final DirtyRegion? laidBounds;

  BitmapSurface toSurface() => _surfaceOf(
    (
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: tiles,
      texts: texts,
      photos: photos,
      laidBounds: laidBounds,
    ),
    (pixels) => BitmapTile(size: tileSize, pixels: pixels),
  );
}

/// One tile as it crosses the save/open isolate boundary: where it sits and
/// its raw straight-alpha RGBA bytes.
typedef AnicelTileRecord = ({int x, int y, Uint8List pixels});

/// One photo as it crosses the save/open isolate boundary: its id and its
/// reference as JSON — plain data, as a text's settings are.
typedef AnicelPhotoRecord = ({int id, String reference});

/// A cel's picture in plain parts — where each tile sits with its pixels as
/// [P], the texts with their plates, the photos, and where a file's picture
/// lies on it: the shape both sides of an isolate boundary make a surface
/// of ([_surfaceOf]).
typedef CelParts<P> = ({
  CanvasSize canvasSize,
  int tileSize,
  List<({int x, int y, P pixels})> tiles,
  List<({int id, String content, List<({int x, int y, P pixels})> plate})>
  texts,
  List<AnicelPhotoRecord> photos,
  DirtyRegion? laidBounds,
});

/// A cel laid on a worker ([layCelEntry]): each tile's `pixels` is the
/// ADDRESS of the native block holding them, which the main isolate adopts
/// ([laidCelSurface]).
typedef AnicelLaidCel = CelParts<int>;

/// [surface] in plain parts, each tile's pixels as [pixelsOf] gives them:
/// the copy [AnicelCelEntry.fromSurface] makes, or the blocks' addresses
/// ([celBlocksOf]) — the way back of [_surfaceOf], one for both.
CelParts<P> _partsOf<P>(
  BitmapSurface surface,
  P Function(BitmapTile tile) pixelsOf,
) {
  List<({int x, int y, P pixels})> records(Map<TileCoord, BitmapTile> tiles) =>
      [
        for (final MapEntry(key: coord, value: tile) in tiles.entries)
          (x: coord.x, y: coord.y, pixels: pixelsOf(tile)),
      ];
  return (
    canvasSize: surface.canvasSize,
    tileSize: surface.tileSize,
    tiles: records(surface.tiles),
    texts: [
      for (final text in surface.texts)
        (
          id: text.id,
          content: jsonEncode(text.content.toJson()),
          plate: records(text.plate),
        ),
    ],
    photos: _photoRecordsOf(surface.photos),
    laidBounds: surface.laidBounds,
  );
}

List<AnicelPhotoRecord> _photoRecordsOf(List<CelPhoto> photos) => [
  for (final photo in photos)
    (id: photo.id, reference: jsonEncode(photo.reference.toJson())),
];

/// [surface] with each tile's pixels named by the ADDRESS of its block, for
/// a worker to read them where they lie ([copiedCelSurface]) — the way
/// there of [laidCelSurface], with no pixel copied here.
///
/// 🚨The addresses are good only while [surface] is held: its tiles' blocks
/// go back to the pool with them (native-tile-pixel-lifetime). The caller
/// holds it until the worker is done.
AnicelLaidCel celBlocksOf(BitmapSurface surface) => _partsOf(
  surface,
  (tile) => tile.readPixels((pointer, _) => pointer.address),
);

/// [laid]'s blocks — another isolate's, read where they lie
/// ([celBlocksOf]) — copied into tiles of this one: a surface this isolate
/// owns, whose tiles it frees as its own, behind the wall the picture
/// [standsBehind] there — which its parts do not carry.
BitmapSurface copiedCelSurface(
  AnicelLaidCel laid, {
  required PasteboardReach standsBehind,
}) {
  final bytes = BitmapTile.bytesFor(laid.tileSize);
  return _surfaceOf(
    laid,
    (address) => BitmapTile(
      size: laid.tileSize,
      pixels: Pointer<Uint8>.fromAddress(address).asTypedList(bytes),
    ),
    standsBehind: standsBehind,
  );
}

/// [parts] made a surface, each tile's pixels made a tile by [tileOf]: the
/// copy [AnicelCelEntry.toSurface] makes, or the adoption a laid cel's
/// blocks take ([laidCelSurface]) — one assembly for both.
///
/// ⚠️Every tile is made BEFORE what can refuse a damaged record — a text's
/// or a photo's JSON, the surface's own checks: a laid block not adopted
/// yet is one nothing would ever free.
BitmapSurface _surfaceOf<P>(
  CelParts<P> parts,
  BitmapTile Function(P pixels) tileOf, {
  PasteboardReach standsBehind = PasteboardReach.whole,
}) {
  Map<TileCoord, BitmapTile> tilesOf(
    List<({int x, int y, P pixels})> records,
  ) => {
    for (final tile in records)
      // 🎯The coordinate has ALWAYS lived beside the pixels here —
      // Finalizable tiles cannot cross the save/open isolate boundary, so
      // the durable shape never had one on the tile. It used to build the
      // TileCoord twice per tile, once as the key and once for a field that
      // no longer exists.
      TileCoord(x: tile.x, y: tile.y): tileOf(tile.pixels),
  };
  final tiles = tilesOf(parts.tiles);
  final plates = [for (final text in parts.texts) tilesOf(text.plate)];
  return BitmapSurface(
    canvasSize: parts.canvasSize,
    pasteboardReach: standsBehind,
    tileSize: parts.tileSize,
    tiles: tiles,
    texts: [
      for (final (index, text) in parts.texts.indexed)
        CelText(
          id: text.id,
          content: CelTextContent.fromJson(
            jsonDecode(text.content) as Map<String, dynamic>,
          ),
          plate: plates[index],
        ),
    ],
    photos: [for (final photo in parts.photos) _photoOf(photo)],
    laidBounds: parts.laidBounds,
  );
}

/// [record] as the photo it is — the one parse of a photo's JSON, for a
/// picture made of a cel ([_surfaceOf]) and a blob's index of what its
/// photos name ([AnicelCelBlob.ofPayload]).
CelPhoto _photoOf(AnicelPhotoRecord record) => CelPhoto(
  id: record.id,
  reference: MediaReference.fromJson(
    jsonDecode(record.reference) as Map<String, dynamic>,
  ),
);

/// [entry] laid into native blocks from [blocks] — the copies
/// [AnicelCelEntry.toSurface] makes, made on the worker that decoded the
/// cel, so they cost the screen nothing (card
/// `cel-thaw-holds-the-ui-thread`: ~40 ms of a first playback's late frames
/// were these copies on the UI thread).
///
/// 🚨A block it could not get frees every block it got — nothing else knows
/// they exist. ⚠️The tile size is asked BEFORE the first block: the main
/// isolate's adoption asks it again, and must never be the first to refuse,
/// for it would refuse with blocks not adopted yet.
AnicelLaidCel layCelEntry(AnicelCelEntry entry, TileBlockHands blocks) {
  BitmapTile.checkSize(entry.tileSize);
  final got = <Pointer<Uint8>>[];
  int laid(Uint8List pixels) {
    final block = blocks.allocate(pixels.length);
    got.add(block);
    block.asTypedList(pixels.length).setAll(0, pixels);
    return block.address;
  }

  List<({int x, int y, int pixels})> lay(List<AnicelTileRecord> records) => [
    for (final tile in records)
      (x: tile.x, y: tile.y, pixels: laid(tile.pixels)),
  ];
  try {
    return (
      canvasSize: entry.canvasSize,
      tileSize: entry.tileSize,
      tiles: lay(entry.tiles),
      texts: [
        for (final text in entry.texts)
          (id: text.id, content: text.content, plate: lay(text.plate)),
      ],
      photos: entry.photos,
      laidBounds: entry.laidBounds,
    );
  } on Object {
    for (final block in got) {
      blocks.free(block);
    }
    rethrow;
  }
}

/// Gives back every block [laid] holds to [blocks] — for a worker whose work
/// failed after laying it, when nothing will adopt it ([layCelEntry]'s rule).
void freeLaidCel(AnicelLaidCel laid, TileBlockHands blocks) {
  for (final tile in [
    ...laid.tiles,
    for (final text in laid.texts) ...text.plate,
  ]) {
    blocks.free(Pointer<Uint8>.fromAddress(tile.pixels));
  }
}

/// [laid]'s blocks adopted as its tiles, on the isolate whose allocator they
/// came from ([BitmapTile.blocks]) — no pixel is copied here — behind the
/// wall the worker that laid them made the picture [standsBehind]: none,
/// for one laid as its bytes were.
BitmapSurface laidCelSurface(
  AnicelLaidCel laid, {
  PasteboardReach standsBehind = PasteboardReach.whole,
}) => _surfaceOf(
  laid,
  (address) => BitmapTile.adoptNative(
    size: laid.tileSize,
    pixels: Pointer<Uint8>.fromAddress(address),
  ),
  standsBehind: standsBehind,
);

/// v5 (2026-10-18, F-374-Q8 — 유저 「맞춘다 — 참조 그림은 벽 밖까지
/// 통째로」): after the texts comes WHERE A FILE'S PICTURE LIES on the cel
/// (`BitmapSurface.laidBounds`) — a byte that says whether it is there,
/// then its left, top, right and bottom as i32. Its tiles may lie past the
/// pasteboard, and a reader that did not know the rect would refuse them.
/// A cel no file was laid on writes a zero.
///
/// v4 (2026-10-15, a sheet's photos — I-97): the header ends with the
/// PHOTOS the picture carries — a count, then for each its id and its
/// reference (JSON: the pool file, where it stands, its own size) — and the
/// tiles' count follows, where v3's header ended. A cel with none writes a
/// zero. ⚠️In the header, not after the texts: a blob indexes what its
/// photos name off the stream's head ([AnicelCelBlob.ofPayload]), and a
/// head must not have to walk a cel's pixels to reach them.
///
/// v3 (2026-10-06, the text tool — R9-rest): after the tiles comes the
/// TEXTS the cel's picture carries — a count, then for each its id, what
/// the person set (JSON) and its plate's tiles, written as the drawing's
/// are. A cel with none writes a zero.
///
/// v2 (pasteboard): tile coords are SIGNED i32 — pasteboard tiles sit at
/// negative coords. v1 files (u32 coords) still decode.
const int anicelCelBinaryVersion = 5;

/// The same bytes [encodeCelEntry] writes, taken straight off the
/// SURFACE — without the defensive pixel copy per tile that building
/// an [AnicelCelEntry] first would make.
///
/// 🚨★★★**PARKING IS WHAT MEMORY PRESSURE DOES, SO IT MUST NOT ASK
/// FOR MEMORY.** The park path used to go surface → AnicelCelEntry
/// (a `tile.pixels` copy each) → isolate message (another copy of
/// all of it) → writer buffer (a third). 🧪Measured on a 4MB cel:
/// the message round trip alone is 4.64ms and, worse, every one of
/// those copies is live at the same moment — four times the cel,
/// asked for at the instant the budget says there is no room.
///
/// ⛔`readPixels`, never the `pixels` getter: that getter IS the
/// defensive copy this exists to avoid (see BitmapTile.readPixels for
/// why the tile must stay the receiver).
Uint8List encodeCelEntryFromSurface(BrushFrameKey key, BitmapSurface surface) {
  final writer = _ByteWriter();
  writer.celStreamHeader(
    key,
    surface.canvasSize,
    surface.tileSize,
    _photoRecordsOf(surface.photos),
  );
  writer.u32(surface.tiles.length);
  writer.tilesOf(surface.tiles);
  writer.u32(surface.texts.length);
  for (final text in surface.texts) {
    writer.celTextHeader(
      text.id,
      jsonEncode(text.content.toJson()),
      text.plate.length,
    );
    writer.tilesOf(text.plate);
  }
  writer.celLaid(surface.laidBounds);
  return writer.takeBytes();
}

/// Encodes a baked cel: key, canvas geometry, then each tile's coord and
/// RAW straight-alpha RGBA bytes — nothing is compressed in the stream: the
/// blob around it compresses it whole ([AnicelCelBlob.ofPayload]).
Uint8List encodeCelEntry(AnicelCelEntry entry) {
  final writer = _ByteWriter();
  writer.celStreamHeader(
    entry.key,
    entry.canvasSize,
    entry.tileSize,
    entry.photos,
  );
  writer.u32(entry.tiles.length);
  writer.tileRecords(entry.tiles);
  writer.u32(entry.texts.length);
  for (final text in entry.texts) {
    writer.celTextHeader(text.id, text.content, text.plate.length);
    writer.tileRecords(text.plate);
  }
  writer.celLaid(entry.laidBounds);
  return writer.takeBytes();
}

/// What a cel stream says it is, up to its tiles: its version, its key,
/// its canvas and its tile size, and the photos its picture carries — read
/// in ONE place, for the reason [_ByteWriter.celStreamHeader] is written in
/// one.
_CelHead<List<AnicelPhotoRecord>> _celStreamHeaderOf(_ByteReader reader) =>
    reader.celHead(
      anicelCelBinaryVersion,
      'Unsupported cel entry version.',
      // The version says whether the photos are there, as it says the
      // texts are below.
      (version) => version < 4 ? const [] : reader.celPhotos(),
    );

/// A cel head as [_ByteReader.celHead] reads it: the version, what the cel
/// is, and what that version says [follows].
typedef _CelHead<T> = ({
  int version,
  BrushFrameKey key,
  CanvasSize canvasSize,
  int tileSize,
  T follows,
});

AnicelCelEntry decodeCelEntry(Uint8List bytes) {
  final reader = _ByteReader(bytes);
  final (:version, :key, :canvasSize, :tileSize, follows: photos) =
      _celStreamHeaderOf(reader);
  final tileCount = reader.u32();
  final tileByteLength = tileSize * tileSize * BitmapTile.bytesPerPixel;
  List<AnicelTileRecord> tiles(int count) => [
    for (var i = 0; i < count; i += 1)
      (
        x: version >= 2 ? reader.i32() : reader.u32(),
        y: version >= 2 ? reader.i32() : reader.u32(),
        pixels: reader.bytes(tileByteLength),
      ),
  ];
  final drawing = tiles(tileCount);
  return AnicelCelEntry(
    key: key,
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: drawing,
    // The version says whether the texts are there — never the bytes left
    // over, which a stream cut short would also have none of.
    texts: version < 3
        ? const []
        : [
            for (var i = reader.u32(); i > 0; i -= 1)
              (
                id: reader.i32(),
                content: reader.longString(),
                plate: tiles(reader.u32()),
              ),
          ],
    photos: photos,
    // After the texts, so read after them: arguments are read in order.
    laidBounds: version < 5 ? null : reader.celLaid(),
  );
}

/// v2 (2026-08-29): the payload carries a CODEC byte — [anicelCodecDeflate]
/// or [anicelCodecZstd].
///
/// 🚨**Why a codec at all: the read is on the frame path.** A cel is
/// compressed once per save on a background isolate and DECOMPRESSED on
/// the main isolate, synchronously, the first time it is scrubbed onto
/// (`BrushFrameStore` promotion). So the axis that binds is decompression
/// speed at a good ratio, and that is exactly what zstd is for.
///
/// 🧪Measured end to end on a real 22.8MB project (104 cels), promotion =
/// decompress + parse:
///
///     deflate6 (v1)   22,616,728   0.92ms median   66.1ms worst
///     deflate9        21,829,624   1.07ms          67.3ms
///     zstd9           20,319,920   0.76ms          29.9ms
///     zstd19          16,985,138   0.74ms          34.5ms
///
/// zstd19 is a QUARTER smaller and reads faster than what it replaces.
/// The level is paid only on the save, and only on a background isolate.
///
/// 🪦A PNG-style「sub」filter shipped in the first draft of v2 and was
/// REMOVED before merge, by the same measurements. It helped deflate
/// (−7%) but with zstd it bought 5% for **+1ms on every promotion** —
/// `sub + deflate9` and `zstd9` land within 3KB of each other on the whole
/// project and zstd reads 2.3× faster. An entropy coder that models the
/// data already captures what the filter was hand-rolling. ⛔A planar
/// de-interleave was measured too: **122% worse**.
///
/// v1 blobs still read: they had no codec byte and were always deflate,
/// and the version is what says whether to look for one — never a sniff of
/// the payload, which would be a guess.
///
/// v3 (2026-10-15, a sheet's photos — I-97): the header ends with the
/// cel's PHOTO INDEX — the pool files its photos name, each once
/// ([celPhotoPaths]) — after its byte length, so a reader of the head alone
/// knows how much head there is ([AnicelCelBlob.headerLengthOf]).
///
/// 🚨★★★**THE INDEX IS NOT THE PHOTOS.** The stream holds them, and a
/// decode reads them there and nowhere else ([AnicelCelBlob.decode]). The
/// index is for the readers that read a head and nothing more — the open
/// path's refs (`AnicelCelFileRef.photoPaths`), what the media pool asks of
/// a cel it will not decode (I-97 E: 사용 중 · 제거 · 다시 연결). It is
/// written from the same picture as the stream it wraps, in the same call
/// ([AnicelCelBlob._assembled]), and nothing writes one without the other:
/// a cel whose photos change is a cel written again — a pool file moved is
/// a rewrite of every cel that names it, never a new head over an old
/// stream (저장 세션과 합의, 2026-10-15).
const int _anicelCelBlobVersion = 3;

/// A cel in its COLD form (R20-A1): a tiny plain header (key + canvas
/// geometry, readable WITHOUT inflating) followed by the deflated
/// [encodeCelEntry] stream.
///
/// This one byte layout is BOTH the in-RAM cold-cel form (the store's
/// tier-1 compression) and the .anicel v3 archive entry (STORE'd, since the
/// payload is already deflated) — so an untouched cel saves with zero
/// re-encode and a project opens without decoding a single pixel.
class AnicelCelBlob {
  AnicelCelBlob(this.bytes) {
    final reader = _ByteReader(bytes);
    final head = _headOf(reader);
    version = head.version;
    key = head.key;
    canvasSize = head.canvasSize;
    tileSize = head.tileSize;
    codec = head.follows;
    photoPaths = version >= 3 ? reader.celPhotoIndex() : const [];
    _deflatedOffset = reader.offset;
  }

  /// How many bytes the header of the blob that starts with [head] takes,
  /// its photo index and all — what a reader of heads alone (the open
  /// path) must have read before it parses one: a cel with many photos, or
  /// long paths, outgrows a first read of a few kilobytes.
  static int headerLengthOf(Uint8List head) {
    final reader = _ByteReader(head);
    if (_headOf(reader).version < 3) {
      return reader.offset;
    }
    final index = reader.u32();
    return reader.offset + index;
  }

  /// The header up to the photo index — read in ONE place, for a blob and
  /// for [headerLengthOf].
  static _CelHead<int> _headOf(_ByteReader reader) => reader.celHead(
    _anicelCelBlobVersion,
    'Unsupported cel blob version.',
    // v2 adds a CODEC byte. v1 had no such byte and was always deflate, so
    // the version is what says whether to read one — not a sniff of the
    // stream, which would guess.
    (version) => version >= 2 ? reader.u8() : anicelCodecDeflate,
  );

  /// Rewrites ONLY the header's key label, splicing the deflate stream
  /// through untouched — a rekeyed cel (cross-layer block move) has
  /// identical pixels, so re-encoding them would be pure waste (R22-C).
  factory AnicelCelBlob.reKeyed(AnicelCelBlob source, BrushFrameKey key) =>
      AnicelCelBlob._assembled(
        // 🚨The SOURCE's version and codec, never the current constants:
        // this SPLICES that payload through, so the header has to describe
        // the payload it is wrapping. Stamping a v1 stream as v2 would tell
        // the reader to un-filter bytes nobody filtered; writing a codec
        // byte a v1 header does not have would push it into the payload.
        // Both were caught by the tests here, one in each direction. And
        // the source's photo index, which the stream spliced through still
        // answers to.
        version: source.version,
        key: key,
        canvasSize: source.canvasSize,
        tileSize: source.tileSize,
        codec: source.codec,
        photoPaths: source.photoPaths,
        body: Uint8List.sublistView(source.bytes, source._deflatedOffset),
      );

  factory AnicelCelBlob.encode(AnicelCelEntry entry) =>
      AnicelCelBlob.ofPayload(encodeCelEntry(entry));

  /// The blob of a cel's uncompressed [payload] — the bytes [encodeCelEntry]
  /// writes, or [encodeCelEntryFromSurface] straight off a surface —
  /// compressed here. The save isolate's shape: a hot cel arrives there
  /// already serialised, because a surface cannot cross.
  ///
  /// ⛔The blob's own header is READ OFF the payload's, never handed in
  /// beside it: two copies of a cel's key and size would be two answers to
  /// what the cel is, and nothing would see them disagree. The photo index
  /// is read off the same head.
  factory AnicelCelBlob.ofPayload(Uint8List payload) {
    final (:key, :canvasSize, :tileSize, follows: photos, version: _) =
        _celStreamHeaderOf(_ByteReader(payload));
    final compressed = compressAnicelPayload(payload);
    return AnicelCelBlob.fromCompressedBody(
      key: key,
      canvasSize: canvasSize,
      tileSize: tileSize,
      photoPaths: celPhotoPaths([for (final photo in photos) _photoOf(photo)]),
      codec: compressed.codec,
      body: compressed.bytes,
    );
  }

  /// A blob assembled around a payload SOMEBODY ELSE compressed —
  /// the shape the park and cool paths need, because they compress in
  /// a worker isolate and hand the bytes back. [photoPaths] is what the
  /// picture the payload was written from names ([celPhotoPaths]).
  factory AnicelCelBlob.fromCompressedBody({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required int tileSize,
    required List<String> photoPaths,
    required int codec,
    required Uint8List body,
  }) => AnicelCelBlob._assembled(
    version: _anicelCelBlobVersion,
    key: key,
    canvasSize: canvasSize,
    tileSize: tileSize,
    codec: codec,
    photoPaths: photoPaths,
    body: body,
  );

  /// ⛔The header is written HERE and only here — a new blob's and a
  /// re-keyed one's ([reKeyed]), which keeps the version of the payload it
  /// splices; [encode] is [fromCompressedBody] with the compression done
  /// inline. Two spellings of this header is a file format that can drift
  /// from itself, and the re-key was the second until the photo index came
  /// (I-97).
  factory AnicelCelBlob._assembled({
    required int version,
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required int tileSize,
    required int codec,
    required List<String> photoPaths,
    required Uint8List body,
  }) {
    final writer = _ByteWriter()
      ..u8(version)
      ..celIdentity(key, canvasSize, tileSize);
    if (version >= 2) {
      writer.u8(codec);
    }
    if (version >= 3) {
      writer.celPhotoIndex(photoPaths);
    }
    writer.bytes(body);
    return AnicelCelBlob(writer.takeBytes());
  }

  /// The whole blob — header + deflate stream. Archive entries carry
  /// exactly these bytes (STORE'd).
  final Uint8List bytes;

  late final BrushFrameKey key;
  late final CanvasSize canvasSize;
  late final int tileSize;

  /// The blob's OWN version, kept because [reKeyed] splices this blob's
  /// deflate stream into a new header — labelling a v1 stream v2 would
  /// tell the reader to un-filter bytes that were never filtered.
  late final int version;

  /// Which compressor wrote the payload — [anicelCodecDeflate] or
  /// [anicelCodecZstd]. ⛔Read from the blob, never assumed from the build:
  /// an engine-less run must still open a zstd file it cannot decode with
  /// a clear failure rather than garbage.
  late final int codec;

  /// The pool files this cel's photos name (v3; none before) — the index
  /// its head carries for a reader that reads nothing else. ⛔Not the
  /// photos themselves, which [decode] reads off the stream.
  late final List<String> photoPaths;

  late final int _deflatedOffset;

  int get byteLength => bytes.length;

  AnicelCelEntry decode() => decodeCelEntry(
    decompressAnicelPayload(
      codec,
      Uint8List.sublistView(bytes, _deflatedOffset),
    ),
  );
}

class _ByteWriter {
  final BytesBuilder _builder = BytesBuilder(copy: true);
  final ByteData _scratch = ByteData(8);

  void u8(int value) => _builder.addByte(value);

  void u16(int value) {
    _scratch.setUint16(0, value, Endian.little);
    _builder.add(_scratch.buffer.asUint8List(0, 2));
  }

  void u32(int value) {
    _scratch.setUint32(0, value, Endian.little);
    _builder.add(_scratch.buffer.asUint8List(0, 4));
  }

  void i32(int value) {
    _scratch.setInt32(0, value, Endian.little);
    _builder.add(_scratch.buffer.asUint8List(0, 4));
  }

  void f32(double value) {
    _scratch.setFloat32(0, value, Endian.little);
    _builder.add(_scratch.buffer.asUint8List(0, 4));
  }

  void string(String value) {
    final encoded = utf8.encode(value);
    u16(encoded.length);
    _builder.add(encoded);
  }

  /// The cel stream's header, written in ONE place: what the cel is — its
  /// key, its canvas, its tile size and the photos its picture carries
  /// (v4). The tiles' count follows it.
  ///
  /// ⛔Two routes write this stream — one from an [AnicelCelEntry] and
  /// one straight off a [BitmapSurface] — and they must not each spell
  /// the header out. The clone ratchet caught exactly that when the
  /// second route arrived (88 → 89, 2026-09-10): a file format with two
  /// spellings of its own header is a format that can drift from itself.
  void celStreamHeader(
    BrushFrameKey key,
    CanvasSize canvasSize,
    int tileSize,
    List<AnicelPhotoRecord> photos,
  ) {
    u8(anicelCelBinaryVersion);
    celIdentity(key, canvasSize, tileSize);
    celPhotos(photos);
  }

  /// What a cel is — its key, its canvas and its tile size — as both its
  /// heads write it after their version: the stream's ([celStreamHeader])
  /// and the blob's (`AnicelCelBlob._assembled`). ONE spelling, so the two
  /// heads cannot drift apart over what the cel is.
  void celIdentity(BrushFrameKey key, CanvasSize canvasSize, int tileSize) {
    string(key.projectId.value);
    string(key.trackId.value);
    string(key.cutId.value);
    string(key.layerId.value);
    string(key.frameId.value);
    u32(canvasSize.width);
    u32(canvasSize.height);
    u16(tileSize);
  }

  /// One text of the cel stream (v3), up to its plate's tiles: its id, what
  /// the person set as JSON, and how many tiles follow. Written in ONE
  /// place for the header's reason above — two routes write this stream.
  void celTextHeader(int id, String contentJson, int plateTileCount) {
    i32(id);
    longString(contentJson);
    u32(plateTileCount);
  }

  /// Where a file's picture lies on the cel (v5), the end of its stream: a
  /// byte that says whether it is there, then its four edges. Written in
  /// ONE place for the header's reason above — two routes write this
  /// stream.
  void celLaid(DirtyRegion? laid) {
    if (laid == null) {
      u8(0);
      return;
    }
    u8(1);
    i32(laid.left);
    i32(laid.top);
    i32(laid.rightExclusive);
    i32(laid.bottomExclusive);
  }

  /// The photos of the cel stream (v4): how many, then each one's id and
  /// its reference as JSON — the end of its header.
  void celPhotos(List<AnicelPhotoRecord> photos) {
    u32(photos.length);
    for (final photo in photos) {
      i32(photo.id);
      longString(photo.reference);
    }
  }

  /// A blob's photo index (v3): its byte length, then how many paths, then
  /// each one — the length first, so a reader of heads knows where the
  /// head ends ([AnicelCelBlob.headerLengthOf]).
  void celPhotoIndex(List<String> paths) {
    final index = _ByteWriter()..u32(paths.length);
    for (final path in paths) {
      index.longString(path);
    }
    final written = index.takeBytes();
    u32(written.length);
    bytes(written);
  }

  /// A text's settings: a string that can outgrow [string]'s 16-bit length
  /// (a page of letters is tens of thousands of bytes as JSON).
  void longString(String value) {
    final encoded = utf8.encode(value);
    u32(encoded.length);
    _builder.add(encoded);
  }

  /// Tiles straight off a surface or a plate — each one's coordinate, then
  /// its bytes read in place ([BitmapTile.readPixels], never the copying
  /// `pixels` getter; see [encodeCelEntryFromSurface]).
  void tilesOf(Map<TileCoord, BitmapTile> tiles) {
    for (final entry in tiles.entries) {
      i32(entry.key.x);
      i32(entry.key.y);
      entry.value.readPixels((_, view) => bytes(view));
    }
  }

  /// The same tiles from their isolate-boundary records.
  void tileRecords(List<AnicelTileRecord> tiles) {
    for (final tile in tiles) {
      i32(tile.x);
      i32(tile.y);
      bytes(tile.pixels);
    }
  }

  void bytes(List<int> value) => _builder.add(value);

  Uint8List takeBytes() => _builder.takeBytes();
}

class _ByteReader {
  _ByteReader(Uint8List bytes)
    : _data = ByteData.sublistView(bytes),
      _bytes = bytes;

  final ByteData _data;
  final Uint8List _bytes;
  int _offset = 0;

  int get offset => _offset;

  int u8() => _data.getUint8(_offset++);

  int u16() {
    final value = _data.getUint16(_offset, Endian.little);
    _offset += 2;
    return value;
  }

  int u32() {
    final value = _data.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  int i32() {
    final value = _data.getInt32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  double f32() {
    final value = _data.getFloat32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  String string() {
    final length = u16();
    final value = utf8.decode(
      Uint8List.sublistView(_bytes, _offset, _offset + length),
    );
    _offset += length;
    return value;
  }

  /// A string written by `_ByteWriter.longString`.
  String longString() {
    final length = u32();
    final value = utf8.decode(
      Uint8List.sublistView(_bytes, _offset, _offset + length),
    );
    _offset += length;
    return value;
  }

  Uint8List bytes(int length) {
    final value = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return value;
  }

  /// A cel head — the stream's and the blob's alike: its version, refused
  /// with [refusal] when a later build wrote it (past [newest]); what the
  /// cel is, as `_ByteWriter.celIdentity` wrote it; and what that version
  /// says follows, read by [follows] — the stream's photos, the blob's
  /// codec.
  _CelHead<T> celHead<T>(
    int newest,
    String refusal,
    T Function(int version) follows,
  ) {
    final version = u8();
    if (version > newest) {
      throw FormatException(refusal);
    }
    return (
      version: version,
      key: BrushFrameKey(
        projectId: ProjectId(string()),
        trackId: TrackId(string()),
        cutId: CutId(string()),
        layerId: LayerId(string()),
        frameId: FrameId(string()),
      ),
      canvasSize: CanvasSize(width: u32(), height: u32()),
      tileSize: u16(),
      follows: follows(version),
    );
  }

  /// Where a file's picture lies, written by `_ByteWriter.celLaid`.
  DirtyRegion? celLaid() => u8() == 0
      ? null
      : DirtyRegion(
          left: i32(),
          top: i32(),
          rightExclusive: i32(),
          bottomExclusive: i32(),
        );

  /// Photos written by `_ByteWriter.celPhotos`.
  List<AnicelPhotoRecord> celPhotos() => [
    for (var i = u32(); i > 0; i -= 1) (id: i32(), reference: longString()),
  ];

  /// A photo index written by `_ByteWriter.celPhotoIndex` — its length is
  /// for a reader of heads ([AnicelCelBlob.headerLengthOf]), not this one.
  List<String> celPhotoIndex() {
    u32();
    return [for (var i = u32(); i > 0; i -= 1) longString()];
  }
}
