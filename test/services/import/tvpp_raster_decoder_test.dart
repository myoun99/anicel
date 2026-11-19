import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/import/tvpp_parse.dart';
import 'package:anicel/src/services/import/tvpp_raster_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../models/import/tvpp_test_builder.dart';
import 'tvpp_slot_rgba.dart';

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

  Uint8List fileWith(
    Uint8List record, {
    bool raw = false,
    int blocks = 1,
    int level = 6,
  }) {
    final b = TvppBuilder();
    b.clipProperties('t');
    b.clipHeader(width: w, height: h);
    b.layerHead('L', end: 0, count: 1);
    if (raw) {
      b.rawSlot(record);
    } else {
      b.zchkSlot(record, blocks: blocks, level: level);
    }
    b.clipConfig();
    return b.bytes;
  }

  void expectDecodes(
    Uint8List file,
    List<int> premul, {
    required bool compressed,
  }) {
    final rgba = tvppSlotRgba(
      recordBytes: file,
      slot: slotFor(file, compressed: compressed),
      width: w,
      height: h,
    );
    expect(rgba, isNotNull);
    expect(rgba, equals(expectedRgba(premul)));
  }

  group('a picture read on its own', () {
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

    test('🚨a block is inflated from its own bytes — a zlib stream lying '
        'inside the block before is not the next one', () {
      // A row whose pixels spell out a whole zlib stream, kept as it is by
      // STORED blocks: a reader that FOUND the next block by its zlib
      // header (till 2026-11-17) took this one for it.
      final hidden = ZLibEncoder().convert([for (var i = 0; i < 40; i++) i]);
      final px = List<int>.filled(w * h, 0);
      var x = 0;
      for (var at = 0; at < hidden.length; at += 4, x += 1) {
        var word = 0;
        for (var k = at; k < at + 4; k += 1) {
          word = (word << 8) | (k < hidden.length ? hidden[k] : 0);
        }
        px[5 * w + x] = word;
      }
      // Ink after it, so the stream's last word stays in the same literal.
      px[5 * w + x] = 0xFFFFFFFF;
      final record = dbodRecord(px, w, h);

      Uint8List? picture(Uint8List file) => tvppSlotRgba(
        recordBytes: file,
        slot: slotFor(file, compressed: false),
        width: w,
        height: h,
      );
      expect(
        picture(fileWith(record, blocks: 2, level: 0)),
        equals(picture(fileWith(record, raw: true))),
      );
    });

    test('🚨a ZCHK that does not hold together is a decode error, never a '
        'crash — a worker answers only that one', () {
      final file = fileWith(dbodRecord(testPixels(), w, h), blocks: 2);
      final payload = slotFor(file, compressed: true).chunkOffset;
      Uint8List broken(void Function(ByteData head, Uint8List bytes) how) {
        final copy = Uint8List.fromList(file);
        how(ByteData.sublistView(copy, payload), copy);
        return copy;
      }

      for (final (what, bytes) in [
        (
          'a block that is not a zlib stream',
          broken((_, b) => b.fillRange(payload + 34, payload + 40, 0xFF)),
        ),
        (
          'a block longer than what is left',
          broken((head, _) => head.setUint32(28, 0x7FFFFFFF)),
        ),
        (
          'blocks holding more than the head\'s total',
          broken((head, _) => head.setUint32(4, head.getUint32(4) - 16)),
        ),
      ]) {
        expect(
          () => tvppSlotRgba(
            recordBytes: bytes,
            slot: slotFor(bytes, compressed: true),
            width: w,
            height: h,
          ),
          throwsA(isA<TvppRasterDecodeException>()),
          reason: what,
        );
      }
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
        () => tvppSlotRgba(
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

    test('🚨a thumbnail is skipped by the size its head gives, whatever '
        'the canvas\'s shape — its tiles are read where it ends, in both '
        'tile modes (card F-608)', () {
      final px = testPixels();
      // 16:9 as the user's file gives it (96 × 54, every tiled record); a
      // 21:9 one and a tall one: no shape is assumed.
      for (final thumbnail in [(96, 54), (96, 41), (54, 96)]) {
        for (final uniformMode in [false, true]) {
          expectDecodes(
            fileWith(
              srawRecord(
                px,
                w,
                h,
                uniformMode: uniformMode,
                thumbnail: thumbnail,
              ),
            ),
            px,
            compressed: true,
          );
        }
      }
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

    test('a hold slot hands on no row', () {
      final file = fileWith(holdRecord(), raw: true);
      final handed = <int>[];
      TvppPicturesInOrder().read(
        recordBytes: file,
        slot: slotFor(file, compressed: false),
        size: const CanvasSize(width: w, height: h),
        row: (y, _) => handed.add(y),
      );
      expect(handed, isEmpty);
    });

    test('a blank instance decodes to fully transparent pixels', () {
      final px = List<int>.filled(w * h, 0);
      final file = fileWith(srawRecord(px, w, h));
      final rgba = tvppSlotRgba(
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
      final rgba = tvppSlotRgba(
        recordBytes: file,
        slot: slotFor(file, compressed: true),
        width: w,
        height: h,
      )!;
      expect(rgba, hasLength(w * h * 4));
      expect(rgba.every((b) => b == 0), isTrue);
    });

    test('only rows with ink are handed on, each where it lies', () {
      final px = List<int>.filled(w * h, 0);
      for (var y = 10; y < 20; y++) {
        px[y * w + 100] = premulBgra(255, 0, 0, 255);
      }
      for (final record in [
        dbodRecord(px, w, h),
        srawRecord(px, w, h),
        srawRecord(px, w, h, uniformMode: true),
      ]) {
        final file = fileWith(record);
        final handed = <int>[];
        TvppPicturesInOrder().read(
          recordBytes: file,
          slot: slotFor(file, compressed: true),
          size: const CanvasSize(width: w, height: h),
          row: (y, rgba) {
            handed.add(y);
            expect(rgba[100 * 4 + 3], 255, reason: 'row $y holds its ink');
          },
        );
        expect(handed, [for (var y = 10; y < 20; y++) y]);
      }
    });

    /// A [width] × [height] canvas's record — tiles of every size, rows of
    /// them past the first band — read through [tvppSlotRgba].
    Uint8List? decodedAt(Uint8List record, int width, int height) {
      final b = TvppBuilder()
        ..clipProperties('t')
        ..clipHeader(width: width, height: height)
        ..layerHead('L', end: 0, count: 1)
        ..zchkSlot(record)
        ..clipConfig();
      final file = b.bytes;
      return tvppSlotRgba(
        recordBytes: file,
        slot: slotFor(file, compressed: true),
        width: width,
        height: height,
      );
    }

    test('🚨a tile that copies one of a band already handed on shows its '
        'pixels — the band is read again from its bytes (card F-608 ③)', () {
      // 194 × 128: four columns of tiles (the last two pixels wide), two
      // rows. Tiles (1,0), (2,0) and (1,1) are one solid fill, so the
      // builder writes the last two as copies of (1,0) — (1,1) from the
      // band before its own. (2,1) holds a block of its own.
      const width = 194;
      const height = 128;
      final px = List<int>.filled(width * height, 0);
      final blue = premulBgra(20, 40, 200, 255);
      for (var y = 0; y < 64; y++) {
        for (var x = 64; x < 192; x++) {
          px[y * width + x] = blue;
        }
      }
      for (var y = 64; y < 128; y++) {
        for (var x = 64; x < 128; x++) {
          px[y * width + x] = blue;
        }
      }
      for (var y = 74; y < 94; y++) {
        for (var x = 138; x < 158; x++) {
          px[y * width + x] = premulBgra(255, 0, 0, 128);
        }
      }
      expect(
        decodedAt(srawRecord(px, width, height), width, height),
        expectedRgba(px),
      );
    });

    test('🚨a band is cleared where it was written before the next is read '
        '— a tile the next leaves empty is not the one above it', () {
      // Uniform mode writes nothing for an empty tile: (1,1) is left as the
      // band holds it, and the band held (1,0)'s solid fill.
      const width = 194;
      const height = 128;
      final px = List<int>.filled(width * height, 0);
      for (var y = 0; y < 64; y++) {
        for (var x = 64; x < 128; x++) {
          px[y * width + x] = premulBgra(20, 40, 200, 255);
        }
      }
      for (var y = 74; y < 94; y++) {
        for (var x = 138; x < 158; x++) {
          px[y * width + x] = premulBgra(255, 0, 0, 255);
        }
      }
      expect(
        decodedAt(
          srawRecord(px, width, height, uniformMode: true),
          width,
          height,
        ),
        expectedRgba(px),
      );
    });

    test('a copy between tiles of two sizes keeps what both of them cover, '
        'from the top-left, and nothing past it', () {
      // 130 × 70: three columns (the last 2 wide), two rows (the last 6
      // tall). Tile 2 — the narrow one — copies tile 1, and tile 4 — a
      // short one — copies tile 2: two columns of tile 1's first six rows.
      final px = List<int>.filled(w * h, 0);
      for (var y = 0; y < 64; y++) {
        for (var x = 64; x < 128; x++) {
          px[y * w + x] = premulBgra(x, y, 90, 255);
        }
      }
      final record = srawRecord(px, w, h, copies: {2: 1, 4: 2});
      final expected = [...px];
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 2; x++) {
          expected[y * w + 128 + x] = px[y * w + 64 + x];
        }
      }
      for (var y = 0; y < 6; y++) {
        for (var x = 0; x < 2; x++) {
          expected[(64 + y) * w + 64 + x] = px[y * w + 64 + x];
        }
      }
      expect(decodedAt(record, w, h), expectedRgba(expected));
    });

    test('a window of the file reads to the same rows as the file', () {
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
      final file = fileWith(srawRecord(testPixels(), w, h));
      final slot = slotFor(file, compressed: true);
      final window = Uint8List.fromList(
        Uint8List.sublistView(
          file,
          slot.chunkOffset,
          slot.chunkOffset + slot.chunkLength,
        ),
      );
      /// Each row handed on, its y first.
      List<List<int>> rowsOf(Uint8List bytes, TvppSlot slot) {
        final rows = <List<int>>[];
        TvppPicturesInOrder().read(
          recordBytes: bytes,
          slot: slot,
          size: const CanvasSize(width: w, height: h),
          row: (y, rgba) => rows.add([y, ...rgba]),
        );
        return rows;
      }

      final whole = rowsOf(file, slot);
      expect(whole, isNotEmpty);
      expect(
        rowsOf(
          window,
          TvppSlot(
            kind: slot.kind,
            chunkOffset: 0,
            chunkLength: slot.chunkLength,
            compressed: slot.compressed,
            v10WholeCanvas: slot.v10WholeCanvas,
          ),
        ),
        whole,
        reason: 'the slot window is the same input by a different name',
      );
    });
  });

  group('a tile of the picture before (card F-621 ②)', () {
    // The 130 × 70 grid: tiles 0 1 2 over 3 4 5, the right column 2 wide
    // and the bottom row 6 tall. The rows' first tiles stay empty — the
    // builder writes an empty tile as a copy of its row's first.
    int shade(int x, int y, int k) => premulBgra(
      (x * 3 + k * 40) & 0xff,
      (y * 5 + k * 70) & 0xff,
      60 + k * 40,
      255,
    );

    /// [px] with tile [t] showing picture [k] in its own corner, as far as
    /// the tile reaches and no further than [rows] down.
    void fill(List<int> px, int t, int k, {int rows = 64}) {
      final x0 = (t % 3) * 64;
      final y0 = (t ~/ 3) * 64;
      final tw = t % 3 == 2 ? 2 : 64;
      final th = t ~/ 3 == 1 ? 6 : 64;
      for (var y = 0; y < th && y < rows; y++) {
        for (var x = 0; x < tw; x++) {
          px[(y0 + y) * w + x0 + x] = shade(x, y, k);
        }
      }
    }

    List<int> picture(Map<int, int> tiles) {
      final px = List<int>.filled(w * h, 0);
      tiles.forEach((t, k) => fill(px, t, k));
      return px;
    }

    // The first stands alone. The second keeps tile 1, shows it again on
    // the narrow tile 2, draws tile 4 anew and shows the first's tile 4 on
    // tile 5 — all but tile 4 the picture before's. The third shows the
    // second's tiles 1 (the first's, shown again) and 4 (its own).
    final first = picture({1: 0, 2: 1, 4: 2});
    final second = picture({1: 0, 2: 0, 4: 3, 5: 2});
    final third = picture({1: 0, 2: 4, 4: 3});
    final records = [
      srawRecord(first, w, h),
      srawRecord(second, w, h, fromTheLast: {1: 1, 2: 1, 5: 4}),
      srawRecord(third, w, h, fromTheLast: {1: 1, 4: 4}),
    ];

    ({Uint8List file, List<TvppSlot> slots}) layerOf(List<Uint8List> laid) {
      final b = TvppBuilder()
        ..clipProperties('t')
        ..clipHeader(width: w, height: h)
        ..layerHead('L', end: laid.length - 1, count: laid.length);
      for (final record in laid) {
        b.zchkSlot(record);
      }
      b.clipConfig();
      final file = b.bytes;
      return (
        file: file,
        slots: parseTvppStructure(file).clips.single.layers.single.slots,
      );
    }

    Uint8List read(
      TvppPicturesInOrder pictures,
      Uint8List file,
      TvppSlot slot,
    ) {
      final rgba = Uint8List(w * h * 4);
      pictures.read(
        recordBytes: file,
        slot: slot,
        size: const CanvasSize(width: w, height: h),
        row: (y, row) => rgba.setRange(y * w * 4, (y + 1) * w * 4, row),
      );
      return rgba;
    }

    test('read after the picture before, a tile shows its tile — as much of '
        'it as the two cover', () {
      final (:file, :slots) = layerOf(records);
      final pictures = TvppPicturesInOrder();
      expect(read(pictures, file, slots[0]), expectedRgba(first));
      expect(read(pictures, file, slots[1]), expectedRgba(second));
      expect(read(pictures, file, slots[2]), expectedRgba(third));
    });

    test('🚨read on its own, it says that it needs the picture before', () {
      final (:file, :slots) = layerOf(records);
      expect(
        () => tvppSlotRgba(
          recordBytes: file,
          slot: slots[1],
          width: w,
          height: h,
        ),
        throwsA(isA<TvppNeedsThePictureBefore>()),
      );
    });

    test('🚨a reader that goes on from what another read reads the same — '
        'through a tile the picture before showed of the one before it', () {
      final (:file, :slots) = layerOf(records);
      final reading = TvppPicturesInOrder();
      read(reading, file, slots[0]);
      final second0 = TvppPicturesInOrder(before: reading.last);
      expect(read(second0, file, slots[1]), expectedRgba(second));
      final third0 = TvppPicturesInOrder(before: second0.last);
      expect(read(third0, file, slots[2]), expectedRgba(third));
    });

    test('a tile shows a shorter one of the picture before no further down '
        'than it reaches', () {
      // Tile 1 (64 tall) shows the first's tile 4 (6 tall).
      final shorter = List<int>.filled(w * h, 0);
      fill(shorter, 1, 2, rows: 6);
      final (:file, :slots) = layerOf([
        records[0],
        srawRecord(shorter, w, h, fromTheLast: {1: 4}),
      ]);
      final pictures = TvppPicturesInOrder();
      read(pictures, file, slots[0]);
      expect(read(pictures, file, slots[1]), expectedRgba(shorter));
    });

    test('🚨a whole-canvas picture is a picture before too — its tiles '
        'are the canvas cut on the grid', () {
      // 🔬Both layers of the user's file that read in order open on one.
      // The second here shows the first's tiles 1, 2 and 4 — tile 2 on the
      // narrow column as itself, tile 4 on the short row as itself.
      final (:file, :slots) = layerOf([
        dbodRecord(first, w, h),
        srawRecord(
          picture({1: 0, 2: 1, 4: 2}),
          w,
          h,
          fromTheLast: {1: 1, 2: 2, 4: 4},
        ),
      ]);
      final reading = TvppPicturesInOrder();
      expect(read(reading, file, slots[0]), expectedRgba(first));
      final after = TvppPicturesInOrder(before: reading.last);
      expect(read(after, file, slots[1]), expectedRgba(first));
    });

    test('a blank picture before shows nothing on a tile that points at it',
        () {
      final (:file, :slots) = layerOf([
        blankInstanceRecord(),
        srawRecord(picture({4: 3}), w, h, fromTheLast: {1: 1}),
      ]);
      final pictures = TvppPicturesInOrder();
      read(pictures, file, slots[0]);
      expect(read(pictures, file, slots[1]), expectedRgba(picture({4: 3})));
    });

    test('a slot names the picture before it in its stream — a hold none of '
        'its own', () {
      final b = TvppBuilder()
        ..clipProperties('t')
        ..clipHeader(width: w, height: h)
        ..layerHead('L', end: 3, count: 4)
        ..zchkSlot(records[0])
        ..zchkSlot(holdRecord())
        ..zchkSlot(records[1])
        ..zchkSlot(records[2])
        ..clipConfig();
      final slots =
          parseTvppStructure(b.bytes).clips.single.layers.single.slots;
      expect(slots[0].before, isNull);
      expect(slots[1].before, same(slots[0]), reason: 'a hold holds it');
      expect(slots[2].before, same(slots[0]), reason: 'past the hold');
      expect(slots[3].before, same(slots[2]));
    });
  });
}
