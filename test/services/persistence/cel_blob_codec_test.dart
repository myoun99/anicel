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

import '../../helpers/cel_photo_fixture.dart';
import '../../helpers/cel_text_fixture.dart';

/// v2 cel blobs: a CODEC byte, so zstd can be written where the engine
/// exists and deflate everywhere else.
///
/// 🚨The two questions 유저 2026-08-29 asked about changing a stored
/// format — 「지금이랑 결과 달라지는거 없나? 안전해?」 — were the two things
/// asserted here: the pixels come back IDENTICAL, and a v1 blob written
/// before this existed still reads. ↩️The second went with format 29's
/// floor (the save law, 2026-10-06): a blob older than this build writes is
/// refused, and the file that holds one is refused by its number first.

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
      final blob = AnicelCelBlob.ofSurface(key, surfaceWith(pixels));
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
    final blob = AnicelCelBlob.ofSurface(key, surfaceWith(pixels));
    expect(blob.decode().tiles.single.pixels, pixels);
  });

  group('🚨the head says whether the picture shows anything — read back '
      'without the stream', () {
    final ink = tileOf({
      (2, 3): [9, 9, 9, 255],
    });
    // Colour in every pixel and no alpha in any: kept, and nothing seen.
    final clear = tileFilledWith([9, 9, 9, 0]);
    for (final (name, picture, shows) in [
      ('ink in a tile', drawingOf({TileCoord(x: 0, y: 0): ink}), true),
      ('a text alone', drawingOf(const {}).withTexts([textOf(1)]), true),
      ('a photo alone', drawingOf(const {}).withPhotos([photoOf(1)]), true),
      ('tiles with no ink', drawingOf({TileCoord(x: 0, y: 0): clear}), false),
      ('nothing at all', drawingOf(const {}), false),
    ]) {
      test(name, () {
        final written = AnicelCelBlob.ofSurface(celTextTestKey, picture);

        expect(written.showsSomething, shows);
        expect(AnicelCelBlob(written.bytes).showsSomething, shows);
      });
    }
  });

  test('a REKEYED blob splices its source — its codec, what it shows and '
      'its stream, with a new name', () {
    const other = BrushFrameKey(
      projectId: ProjectId('p'),
      trackId: TrackId('t'),
      cutId: CutId('c'),
      layerId: LayerId('other'),
      frameId: FrameId('f'),
    );
    for (final picture in [
      surfaceWith(patterned(11)),
      surfaceWith(Uint8List(8 * 8 * 4)),
    ]) {
      final blob = AnicelCelBlob.ofSurface(key, picture);
      final rekeyed = AnicelCelBlob(AnicelCelBlob.reKeyed(blob, other).bytes);
      expect(rekeyed.key.layerId, const LayerId('other'));
      expect(rekeyed.codec, blob.codec);
      expect(rekeyed.showsSomething, picture.showsSomething);
      expect(
        rekeyed.decode().tiles.single.pixels,
        picture.tiles.values.single.pixels,
      );
    }
  });

  test('🚨a blob of any other version is refused at its first byte — one '
      'older does not say whether it shows anything', () {
    final today = AnicelCelBlob.ofSurface(key, surfaceWith(patterned(3)));
    for (final version in [today.bytes.first - 1, today.bytes.first + 1]) {
      final other = Uint8List.fromList(today.bytes)..[0] = version;
      expect(
        () => AnicelCelBlob(other),
        throwsFormatException,
        reason: 'v$version',
      );
      expect(
        () => AnicelCelBlob.headerLengthOf(other),
        throwsFormatException,
        reason: 'v$version: the open path reads heads through this',
      );
    }
  });

  test('🚨a cel stream of any other version is refused — one older than '
      'v$anicelCelBinaryVersion reads as a v$anicelCelBinaryVersion one '
      'nowhere', () {
    final today = encodeCelEntryFromSurface(key, surfaceWith(patterned(5)));
    expect(today.first, anicelCelBinaryVersion, reason: '⛔premise');
    for (final version in [
      anicelCelBinaryVersion - 1,
      anicelCelBinaryVersion + 1,
    ]) {
      final other = Uint8List.fromList(today)..[0] = version;
      expect(
        () => decodeCelEntry(other),
        throwsFormatException,
        reason: 'v$version',
      );
    }
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

    final blob = AnicelCelBlob.ofSurface(key, surfaceWith(patterned(7)));
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
    final blob = AnicelCelBlob.ofSurface(key, surfaceWith(patterned(13)));
    expect(blob.codec, anyOf(anicelCodecDeflate, anicelCodecZstd));
    expect(blob.decode().tiles.single.pixels, patterned(13));
  });
}
