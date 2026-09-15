import 'dart:typed_data';

import 'package:anicel/src/models/import/tvpp_parse.dart';
import 'package:anicel/src/services/import/tvpp_raster_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../models/import/tvpp_test_builder.dart';

/// Pixel decoding round-trips: the test builder encodes premultiplied
/// BGRA into real record layouts (both tile modes, both wrappers) and
/// the decoder must return the exact straight-RGBA image.
///
/// 130×70 is chosen for its grid: 3×2 tiles where the right column is
/// 2px wide and the bottom row 6px tall — the truncated-edge-tile rules
/// that broke three times during the format work.
void main() {
  const w = 130;
  const h = 70;

  /// A recognisable image: transparent canvas, one opaque red block in
  /// tile (1,0), a half-alpha green line crossing tiles, nothing in
  /// tile 0 (uniform mode cannot express content there).
  List<int> testPixels() {
    final px = List<int>.filled(w * h, 0);
    for (var y = 10; y < 30; y++) {
      for (var x = 70; x < 100; x++) {
        px[y * w + x] = premulBgra(255, 0, 0, 255);
      }
    }
    for (var x = 64; x < w; x++) {
      px[66 * w + x] = premulBgra(0, 200, 0, 128);
    }
    return px;
  }

  /// The straight-RGBA the decoder should produce for [premul] — the
  /// format's own floor-unpremultiply, computed independently here.
  Uint8List expectedRgba(List<int> premul) {
    final out = Uint8List(premul.length * 4);
    for (var i = 0; i < premul.length; i++) {
      final v = premul[i];
      final a = v & 0xff;
      if (a == 0) {
        continue;
      }
      out[i * 4] = ((v >> 8) & 0xff) * 255 ~/ a;
      out[i * 4 + 1] = ((v >> 16) & 0xff) * 255 ~/ a;
      out[i * 4 + 2] = ((v >> 24) & 0xff) * 255 ~/ a;
      out[i * 4 + 3] = a;
    }
    return out;
  }

  TvppSlot slotFor(Uint8List file, {required bool compressed}) {
    // The record was appended as the LAST chunk; find its payload.
    final parsed = parseTvppStructure(file);
    return parsed.clips.single.layers.single.slots.single;
  }

  Uint8List fileWith(Uint8List record, {bool raw = false, int blocks = 1}) {
    final b = TvppBuilder();
    b.clipProperties('t');
    b.clipHeader(width: w, height: h);
    b.layerHead('L', end: 0, count: 1);
    if (raw) {
      b.rawSlot(record);
    } else {
      b.zchkSlot(record, blocks: blocks);
    }
    b.clipConfig();
    return b.bytes;
  }

  void expectDecodes(
    Uint8List file,
    List<int> premul, {
    required bool compressed,
  }) {
    final rgba = decodeTvppSlotRgba(
      recordBytes: file,
      slot: slotFor(file, compressed: compressed),
      width: w,
      height: h,
    );
    expect(rgba, isNotNull);
    expect(rgba, equals(expectedRgba(premul)));
  }

  group('decodeTvppSlotRgba', () {
    test('DBOD whole-canvas record (v12 zlib wrapper)', () {
      final px = testPixels();
      expectDecodes(fileWith(dbodRecord(px, w, h)), px, compressed: true);
    });

    test('DBOD split across multiple zlib blocks', () {
      final px = testPixels();
      expectDecodes(
        fileWith(dbodRecord(px, w, h), blocks: 3),
        px,
        compressed: true,
      );
    });

    test('tiled SRAW, X > 0 mode: bare tile 0, copy markers, edges', () {
      final px = testPixels();
      expectDecodes(fileWith(srawRecord(px, w, h)), px, compressed: true);
    });

    test('tiled SRAW: a copy marker reproduces a CONTENT tile', () {
      // The same block at the same intra-tile offset in tiles (0,0) and
      // (1,0): the builder dedupes the second into a copy marker — the
      // path TVPaint uses for solid fills (measured on E_F).
      final px = List<int>.filled(w * h, 0);
      for (var y = 10; y < 30; y++) {
        for (var x = 10; x < 30; x++) {
          px[y * w + x] = premulBgra(20, 40, 200, 255);
          px[y * w + (x + 64)] = premulBgra(20, 40, 200, 255);
        }
      }
      expectDecodes(fileWith(srawRecord(px, w, h)), px, compressed: true);
    });

    test('🚨a tile whose DECLARED size is not the size it reads is refused '
        '— once the cursor drifts, everything after it is noise', () {
      final px = testPixels();

      expect(
        () => decodeTvppSlotRgba(
          recordBytes: fileWith(
            srawRecord(px, w, h, corruptFirstTileSize: true),
          ),
          slot: slotFor(
            fileWith(srawRecord(px, w, h, corruptFirstTileSize: true)),
            compressed: true,
          ),
          width: w,
          height: h,
        ),
        throwsA(
          isA<TvppRasterDecodeException>().having(
            (error) => error.message,
            'message',
            contains('size mismatch'),
          ),
        ),
      );
    });

    test('tiled SRAW, uniform mode: 12-byte records with data chains', () {
      final px = testPixels();
      expectDecodes(
        fileWith(srawRecord(px, w, h, uniformMode: true)),
        px,
        compressed: true,
      );
    });

    test('v10 bare records decode identically', () {
      final px = testPixels();
      expectDecodes(
        fileWith(dbodRecord(px, w, h), raw: true),
        px,
        compressed: false,
      );
      expectDecodes(
        fileWith(srawRecord(px, w, h), raw: true),
        px,
        compressed: false,
      );
    });

    test('a hold slot returns null', () {
      final file = fileWith(holdRecord(), raw: true);
      final rgba = decodeTvppSlotRgba(
        recordBytes: file,
        slot: slotFor(file, compressed: false),
        width: w,
        height: h,
      );
      expect(rgba, isNull);
    });

    test('a blank instance decodes to fully transparent pixels', () {
      final px = List<int>.filled(w * h, 0);
      final file = fileWith(srawRecord(px, w, h));
      final rgba = decodeTvppSlotRgba(
        recordBytes: file,
        slot: slotFor(file, compressed: true),
        width: w,
        height: h,
      )!;
      expect(rgba.every((b) => b == 0), isTrue);
    });

    test("12.0.6's type-5 blank record is the same blank cel, not a "
        'decode error', () {
      // 288 runs blank cels on 2s this way; reading it as a tiled image
      // walked off the record ("리터럴 레코드가 잘렸다" ×13 layers).
      final file = fileWith(blankInstanceRecord());
      final rgba = decodeTvppSlotRgba(
        recordBytes: file,
        slot: slotFor(file, compressed: true),
        width: w,
        height: h,
      )!;
      expect(rgba, hasLength(w * h * 4));
      expect(rgba.every((b) => b == 0), isTrue);
    });

    test('the tile path is the RGBA path cut into sparse 256px tiles', () {
      // 300px wide = two tile columns; ink only in the right half, so
      // tile (0,0) must be omitted, (1,0) must carry the pixels at the
      // right offsets, and the region past the 300×70 canvas must stay
      // zero-padded. This is the parity that lets the import skip the
      // full-canvas ui.Image detour.
      const tw = 300;
      const th = 70;
      final px = List<int>.filled(tw * th, 0);
      for (var y = 10; y < 20; y++) {
        for (var x = 280; x < 295; x++) {
          px[y * tw + x] = 0xff2080ff; // premultiplied BGRA word
        }
      }
      final file = fileWith(srawRecord(px, tw, th));
      final slot = slotFor(file, compressed: true);
      final rgba = decodeTvppSlotRgba(
        recordBytes: file,
        slot: slot,
        width: tw,
        height: th,
      )!;
      final tiles = decodeTvppSlotTiles(
        recordBytes: file,
        slot: slot,
        width: tw,
        height: th,
        // ⚠️STATED, not the default: this case is about the 256px grid it
        // names in its own title, and the arithmetic below counts in 256s.
        tileSize: 256,
      )!;
      expect(tiles, hasLength(1));
      final tile = tiles.single;
      expect((tile.x, tile.y), (1, 0));
      for (var y = 0; y < th; y++) {
        for (var x = 256; x < tw; x++) {
          final src = (y * tw + x) * 4;
          final dst = (y * 256 + (x - 256)) * 4;
          for (var c = 0; c < 4; c++) {
            expect(
              tile.pixels[dst + c],
              rgba[src + c],
              reason: 'pixel ($x, $y) channel $c',
            );
          }
        }
      }
      // 🚨A WINDOW decodes to the same pixels as the whole file, which is
      // what lets the import send one slot's bytes to a worker instead of
      // the entire .tvpp.
      //
      // `Isolate.run` copies what its closure captures, so a decode that
      // takes the WHOLE FILE hands every worker its own copy of it: a pool
      // of eight meant eight whole projects resident at once, on top of
      // the original and everything already built. That grows with the
      // file rather than with the work, and on a phone it is the
      // allocation that gets the app killed.
      //
      // ⚠️The parameter was called `fileBytes` while this paragraph stood
      // right here saying not to pass a file. It is `recordBytes` now: a
      // name that contradicts its own contract is not something a comment
      // can hold, because the next caller reads the signature.
      final window = Uint8List.fromList(
        Uint8List.sublistView(
          file,
          slot.chunkOffset,
          slot.chunkOffset + slot.chunkLength,
        ),
      );
      final windowed = decodeTvppSlotTiles(
        recordBytes: window,
        slot: TvppSlot(
          kind: slot.kind,
          chunkOffset: 0,
          chunkLength: slot.chunkLength,
          compressed: slot.compressed,
          v10WholeCanvas: slot.v10WholeCanvas,
        ),
        width: tw,
        height: th,
        tileSize: 256,
      )!;
      expect(windowed, hasLength(tiles.length));
      expect(
        windowed.single.pixels,
        tile.pixels,
        reason: 'the slot window is the same input by a different name',
      );

      // Padding beyond the canvas stays transparent.
      expect(tile.pixels[(69 * 256 + 200) * 4 + 3], 0);
      expect(tile.pixels[(0 * 256 + 45) * 4 + 3], 0);
    });
  });
}
