import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/persistence/anicel_payload_codec.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';

/// v2 cel blobs: a CODEC byte, so zstd can be written where the engine
/// exists and deflate everywhere else.
///
/// 🚨The two questions 유저 2026-08-29 asked about changing a stored
/// format — 「지금이랑 결과 달라지는거 없나? 안전해?」 — are the two things
/// format — 「지금이랑 결과 달라지는거 없나? 안전해?」 — are the two things
/// asserted here: the pixels come back IDENTICAL, and a v1 blob written
/// before this existed still reads.

const key = BrushFrameKey(
  projectId: ProjectId('p'),
  trackId: TrackId('t'),
  cutId: CutId('c'),
  layerId: LayerId('l'),
  frameId: FrameId('f'),
);

BitmapSurface surfaceWith(Uint8List pixels) => BitmapSurface(
  canvasSize: const CanvasSize(width: 16, height: 16),
  tileSize: 8,
  tiles: {
    TileCoord(x: 1, y: 0): BitmapTile(
      size: 8,
      pixels: pixels,
    ),
  },
);

Uint8List patterned(int seed) {
  final pixels = Uint8List(8 * 8 * 4);
  for (var i = 0; i < pixels.length; i += 1) {
    pixels[i] = (i * seed) & 0xFF;
  }
  return pixels;
}

void main() {
  test('🚨the pixels come back byte-identical', () {
    for (final seed in [1, 37, 91, 255]) {
      final pixels = patterned(seed);
      final blob = AnicelCelBlob.encode(
        AnicelCelEntry.fromSurface(key, surfaceWith(pixels)),
      );
      final back = blob.decode();
      expect(
        back.tiles.single.pixels,
        pixels,
        reason: 'seed $seed did not survive the round trip',
      );
    }
  });

  test('every byte value survives — 0x00 and 0xFF are '
      'where an off-by-one would show', () {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = i % 3 == 0 ? 0x00 : (i % 3 == 1 ? 0xFF : 0x80);
    }
    final blob = AnicelCelBlob.encode(
      AnicelCelEntry.fromSurface(key, surfaceWith(pixels)),
    );
    expect(blob.decode().tiles.single.pixels, pixels);
  });

  test('a REKEYED blob keeps the source version, not the current one — it '
      'splices that stream, it does not re-encode it', () {
    final blob = AnicelCelBlob.encode(
      AnicelCelEntry.fromSurface(key, surfaceWith(patterned(11))),
    );
    const other = BrushFrameKey(
      projectId: ProjectId('p'),
      trackId: TrackId('t'),
      cutId: CutId('c'),
      layerId: LayerId('other'),
      frameId: FrameId('f'),
    );
    final rekeyed = AnicelCelBlob.reKeyed(blob, other);
    expect(rekeyed.version, blob.version);
    expect(rekeyed.key.layerId, const LayerId('other'));
    expect(
      rekeyed.decode().tiles.single.pixels,
      patterned(11),
      reason: 'a mislabelled stream un-filters bytes that were never filtered',
    );
  });

  test('🚨a v1 blob — written before the filter existed — still reads', () {
    // Built by hand in the v1 layout: version byte 1, the key strings,
    // the geometry, then an UNFILTERED deflate. This is the shape every
    // already-saved project holds, and the version byte is the only thing
    // telling the reader not to un-filter it.
    final pixels = patterned(23);
    final body = encodeCelEntry(
      AnicelCelEntry.fromSurface(key, surfaceWith(pixels)),
    );
    final out = BytesBuilder();
    out.addByte(1);
    for (final part in ['p', 't', 'c', 'l', 'f']) {
      final encoded = utf8.encode(part);
      out
        ..addByte(encoded.length & 0xff)
        ..addByte((encoded.length >> 8) & 0xff)
        ..add(encoded);
    }
    void u32(int value) => out.add([
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ]);
    u32(16);
    u32(16);
    out
      ..addByte(8)
      ..addByte(0)
      ..add(ZLibEncoder().convert(body));

    final v1 = AnicelCelBlob(out.takeBytes());
    expect(v1.version, 1);
    expect(
      v1.decode().tiles.single.pixels,
      pixels,
      reason: 'an old project must open, filter or no filter',
    );

    // 🚨AND a v1 blob that gets REKEYED (a cross-layer block move on an
    // old project) keeps its v1 label. Labelling that spliced stream v2
    // would tell the reader to un-filter bytes nobody filtered — the one
    // way this change could corrupt real work.
    const moved = BrushFrameKey(
      projectId: ProjectId('p'),
      trackId: TrackId('t'),
      cutId: CutId('c'),
      layerId: LayerId('moved'),
      frameId: FrameId('f'),
    );
    final rekeyedV1 = AnicelCelBlob.reKeyed(v1, moved);
    expect(rekeyedV1.version, 1, reason: 'the SOURCE was v1');
    expect(rekeyedV1.decode().tiles.single.pixels, pixels);
  });

  test('🚨with NO engine it writes deflate, and that blob reads anywhere', () {
    // ⛔The absence is FORCED, not assumed. The first version of this test
    // asserted「flutter_tester loads no engine」— which is true of the
    // ordinary suite and false of the two CI jobs that run WITH the engine
    // on PATH, so it went red there and nowhere else. A test that asserts a
    // property of its RUNNER is not testing the code.
    // The seam, not the path: a bogus path falls THROUGH to the default
    // search by design, so it cannot say「no engine」on a machine that has
    // one — which is exactly the two CI jobs this test used to fail in.
    QaCelCompressor.debugInstanceOverride = () => null;

    addTearDown(() {
      QaCelCompressor.debugInstanceOverride = null;
    });

    final blob = AnicelCelBlob.encode(
      AnicelCelEntry.fromSurface(key, surfaceWith(patterned(7))),
    );
    expect(
      blob.codec,
      anicelCodecDeflate,
      reason: 'no engine means the floor, and the floor is dart:io zlib',
    );
    expect(blob.decode().tiles.single.pixels, patterned(7));
  });

  test('and whatever codec the ambient build picked, the blob round-trips '
      'and says which one it used', () {
    // The invariant that holds in BOTH worlds — the one the runner cannot
    // make false.
    final blob = AnicelCelBlob.encode(
      AnicelCelEntry.fromSurface(key, surfaceWith(patterned(13))),
    );
    expect(blob.codec, anyOf(anicelCodecDeflate, anicelCodecZstd));
    expect(blob.decode().tiles.single.pixels, patterned(13));
  });

  test('a v1 blob reports the deflate codec — it had no codec byte at all, '
      'and guessing from the stream would be a sniff', () {
    final pixels = patterned(5);
    final body = encodeCelEntry(
      AnicelCelEntry.fromSurface(key, surfaceWith(pixels)),
    );
    final out = BytesBuilder()..addByte(1);
    for (final part in ['p', 't', 'c', 'l', 'f']) {
      final encoded = utf8.encode(part);
      out
        ..addByte(encoded.length & 0xff)
        ..addByte((encoded.length >> 8) & 0xff)
        ..add(encoded);
    }
    void u32(int value) => out.add([
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ]);
    u32(16);
    u32(16);
    out
      ..addByte(8)
      ..addByte(0)
      ..add(ZLibEncoder().convert(body));

    final v1 = AnicelCelBlob(out.takeBytes());
    expect(v1.codec, anicelCodecDeflate);
    expect(v1.decode().tiles.single.pixels, pixels);
  });
}
