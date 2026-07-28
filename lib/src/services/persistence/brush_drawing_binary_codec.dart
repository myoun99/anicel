/// Compact binary encoding for the .anicel container's cel payloads: one
/// entry per baked cel — key, canvas geometry, then raw straight-alpha
/// RGBA tile bytes. Little-endian throughout. (The v1 command-drawing
/// codec lived here until R20-E3 — deleted with the v1 reader; no
/// production v1 file was ever written.)
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/tile_coord.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
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
  });

  factory AnicelCelEntry.fromSurface(BrushFrameKey key, BitmapSurface surface) {
    return AnicelCelEntry(
      key: key,
      canvasSize: surface.canvasSize,
      tileSize: surface.tileSize,
      tiles: [
        for (final tile in surface.tiles.values)
          (x: tile.coord.x, y: tile.coord.y, pixels: tile.pixels),
      ],
    );
  }

  final BrushFrameKey key;
  final CanvasSize canvasSize;
  final int tileSize;
  final List<({int x, int y, Uint8List pixels})> tiles;

  BitmapSurface toSurface() {
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: {
        for (final tile in tiles)
          TileCoord(x: tile.x, y: tile.y): BitmapTile(
            coord: TileCoord(x: tile.x, y: tile.y),
            size: tileSize,
            pixels: tile.pixels,
          ),
      },
    );
  }
}

/// v2 (pasteboard): tile coords are SIGNED i32 — pasteboard tiles sit at
/// negative coords. v1 files (u32 coords) still decode.
const int anicelCelBinaryVersion = 2;

/// Encodes a baked cel: key, canvas geometry, then each tile's coord and
/// RAW straight-alpha RGBA bytes (the ZIP container's deflate compresses
/// line art extremely well — no inner compression layer).
Uint8List encodeCelEntry(AnicelCelEntry entry) {
  final writer = _ByteWriter()
    ..u8(anicelCelBinaryVersion)
    ..string(entry.key.projectId.value)
    ..string(entry.key.trackId.value)
    ..string(entry.key.cutId.value)
    ..string(entry.key.layerId.value)
    ..string(entry.key.frameId.value)
    ..u32(entry.canvasSize.width)
    ..u32(entry.canvasSize.height)
    ..u16(entry.tileSize)
    ..u32(entry.tiles.length);
  for (final tile in entry.tiles) {
    writer
      ..i32(tile.x)
      ..i32(tile.y)
      ..bytes(tile.pixels);
  }
  return writer.takeBytes();
}

AnicelCelEntry decodeCelEntry(Uint8List bytes) {
  final reader = _ByteReader(bytes);
  final version = reader.u8();
  if (version > anicelCelBinaryVersion) {
    throw const FormatException('Unsupported cel entry version.');
  }
  final key = BrushFrameKey(
    projectId: ProjectId(reader.string()),
    trackId: TrackId(reader.string()),
    cutId: CutId(reader.string()),
    layerId: LayerId(reader.string()),
    frameId: FrameId(reader.string()),
  );
  final width = reader.u32();
  final height = reader.u32();
  final tileSize = reader.u16();
  final tileCount = reader.u32();
  final tileByteLength = tileSize * tileSize * BitmapTile.bytesPerPixel;
  return AnicelCelEntry(
    key: key,
    canvasSize: CanvasSize(width: width, height: height),
    tileSize: tileSize,
    tiles: [
      for (var i = 0; i < tileCount; i += 1)
        (
          x: version >= 2 ? reader.i32() : reader.u32(),
          y: version >= 2 ? reader.i32() : reader.u32(),
          pixels: reader.bytes(tileByteLength),
        ),
    ],
  );
}

const int _anicelCelBlobVersion = 1;

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
    final version = reader.u8();
    if (version > _anicelCelBlobVersion) {
      throw const FormatException('Unsupported cel blob version.');
    }
    key = BrushFrameKey(
      projectId: ProjectId(reader.string()),
      trackId: TrackId(reader.string()),
      cutId: CutId(reader.string()),
      layerId: LayerId(reader.string()),
      frameId: FrameId(reader.string()),
    );
    canvasSize = CanvasSize(width: reader.u32(), height: reader.u32());
    tileSize = reader.u16();
    _deflatedOffset = reader.offset;
  }

  /// Rewrites ONLY the header's key label, splicing the deflate stream
  /// through untouched — a rekeyed cel (cross-layer block move) has
  /// identical pixels, so re-encoding them would be pure waste (R22-C).
  factory AnicelCelBlob.reKeyed(AnicelCelBlob source, BrushFrameKey key) {
    final writer = _ByteWriter()
      ..u8(_anicelCelBlobVersion)
      ..string(key.projectId.value)
      ..string(key.trackId.value)
      ..string(key.cutId.value)
      ..string(key.layerId.value)
      ..string(key.frameId.value)
      ..u32(source.canvasSize.width)
      ..u32(source.canvasSize.height)
      ..u16(source.tileSize)
      ..bytes(Uint8List.sublistView(source.bytes, source._deflatedOffset));
    return AnicelCelBlob(writer.takeBytes());
  }

  factory AnicelCelBlob.encode(AnicelCelEntry entry) {
    final body = encodeCelEntry(entry);
    final deflated = ZLibEncoder().convert(body);
    final writer = _ByteWriter()
      ..u8(_anicelCelBlobVersion)
      ..string(entry.key.projectId.value)
      ..string(entry.key.trackId.value)
      ..string(entry.key.cutId.value)
      ..string(entry.key.layerId.value)
      ..string(entry.key.frameId.value)
      ..u32(entry.canvasSize.width)
      ..u32(entry.canvasSize.height)
      ..u16(entry.tileSize)
      ..bytes(deflated);
    return AnicelCelBlob(writer.takeBytes());
  }

  /// The whole blob — header + deflate stream. Archive entries carry
  /// exactly these bytes (STORE'd).
  final Uint8List bytes;

  late final BrushFrameKey key;
  late final CanvasSize canvasSize;
  late final int tileSize;
  late final int _deflatedOffset;

  int get byteLength => bytes.length;

  AnicelCelEntry decode() {
    final inflated = ZLibDecoder().convert(
      Uint8List.sublistView(bytes, _deflatedOffset),
    );
    return decodeCelEntry(
      inflated is Uint8List ? inflated : Uint8List.fromList(inflated),
    );
  }
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

  Uint8List bytes(int length) {
    final value = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return value;
  }
}
