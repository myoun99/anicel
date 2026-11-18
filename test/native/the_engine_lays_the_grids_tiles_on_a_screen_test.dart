import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_ops.dart';

import '../helpers/a_shown_surface.dart';

/// The frame grid's tiles reach a view's screen through the package's Dart
/// (grid-on-the-engine ④): a tile a batch draws ([GpuGridBatch.draw]) —
/// its letters read where the batch put them on its atlas
/// ([GpuGridBatch.lettersAt]) — is laid ([GpuGridLay.lay]) from the part
/// of it each lay names onto the part of the screen it names,
/// premultiplied, the rest of the rect clear; and what the batch is asked
/// is drawn on one flush, the first time one of its tiles is laid or read.
/// How a lay lands on pixels between whole ones is the crate's to pin
/// (rust/src/kernels/timeline/grid/lay_tests.rs) — here, what Dart hands
/// it.
void main() {
  late GpuGridBatch batch;
  late GpuGridLay lay;
  const red = [255, 0, 0, 255];
  final white = timelineGridPackRgba(const Color(0xFFFFFFFF));

  setUpAll(() {
    batch = GpuGridBatch(appGpuEngine);
    lay = GpuGridLay(appGpuEngine);
  });
  tearDownAll(() {
    lay.free();
    batch.free();
  });

  /// A tile [width] × [height] of [fills] — (x, y, w, h, colour) each.
  GpuGridPicture aTile(
    int width,
    int height,
    List<(int, int, int, int, Color)> fills,
  ) {
    final picture = batch.picture(width, height)!;
    addTearDown(picture.free);
    final ops = TimelineGridTileOpWriter();
    for (final (x, y, w, h, colour) in fills) {
      ops.fillRect(x, y, w, h, timelineGridPackRgba(colour));
    }
    batch.draw(picture, ops.build());
    return picture;
  }

  /// A tile [width] × [height] whose one letter, [width] × [height], is
  /// read at [at] on the atlas.
  GpuGridPicture lettered(({int x, int y}) at, int width, int height) {
    final picture = batch.picture(width, height)!;
    addTearDown(picture.free);
    batch.draw(
      picture,
      (TimelineGridTileOpWriter()
            ..glyph(0, 0, at.x, at.y, width, height, white))
          .build(),
    );
    return picture;
  }

  test('each lay takes its part of its tile onto its part of the screen', () {
    // (200, 100, 50) at 128 over the left two columns, red over the right.
    final tile = aTile(3, 2, [
      (0, 0, 2, 2, const Color(0x80C86432)),
      (2, 0, 1, 2, const Color(0xFFFF0000)),
    ]);
    final green = aTile(1, 1, [(0, 0, 1, 1, const Color(0xFF00FF00))]);
    final surface = shownSurfaceOf(5, 4);
    addTearDown(surface.free);
    final want = Uint8List(5 * 4 * 4);
    void put(int x, int y, List<int> rgba) {
      final [r, g, b, a] = rgba;
      want.setAll(
        (y * 5 + x) * 4,
        surface.bgra ? [b, g, r, a] : [r, g, b, a],
      );
    }

    // (200, 100, 50) at 128, premultiplied as premultiply.wgsl rounds.
    for (final (x, y) in [(1, 1), (2, 1), (1, 2), (2, 2)]) {
      put(x, y, [100, 50, 25, 128]);
    }
    put(3, 1, red);
    put(3, 2, red);
    put(0, 3, [0, 255, 0, 255]);

    lay.lay(surface, (0, 0, 5, 4), [
      (picture: tile, from: (0, 0, 3, 2), onto: (1, 1, 4, 3)),
      (picture: green, from: (0, 0, 1, 1), onto: (0, 3, 1, 4)),
    ]);

    expect(surface.fingerprint(), fingerprintBytes(want));
  });

  test('a frame\'s tiles are drawn on one flush, as the first is laid', () {
    final flushed = batch.debugFlushes;
    final tiles = [
      for (final colour in const [
        Color(0xFFFF0000),
        Color(0xFF00FF00),
        Color(0xFF0000FF),
      ])
        aTile(1, 1, [(0, 0, 1, 1, colour)]),
    ];
    expect(batch.debugFlushes, flushed, reason: 'none is drawn as asked');
    final surface = shownSurfaceOf(3, 1);
    addTearDown(surface.free);

    lay.lay(surface, (0, 0, 3, 1), [
      for (final (x, tile) in tiles.indexed)
        (picture: tile, from: (0, 0, 1, 1), onto: (x + 0.0, 0, x + 1.0, 1)),
    ]);

    expect(batch.debugFlushes, flushed + 1);
    final [r, g, b] = [
      [255, 0, 0, 255],
      [0, 255, 0, 255],
      [0, 0, 255, 255],
    ];
    List<int> shown(List<int> rgba) => surface.bgra
        ? [rgba[2], rgba[1], rgba[0], rgba[3]]
        : rgba;
    expect(
      surface.fingerprint(),
      fingerprintBytes(
        Uint8List.fromList([...shown(r), ...shown(g), ...shown(b)]),
      ),
    );
  });

  test('a tile reads its letters where the batch puts them, once', () {
    // A word put before it, so the word's place is not the atlas's corner.
    final at = batch.lettersAt({
      'before': (alpha: Uint8List.fromList([9, 9]), width: 2, height: 1),
      'word': (alpha: Uint8List.fromList([255, 128]), width: 1, height: 2),
    })!;
    final tile = lettered(at['word']!, 1, 2);

    // White at 255 and at 128, as the tile keeps it: straight.
    expect(tile.read(), [255, 255, 255, 255, 255, 255, 255, 128]);
    expect(
      batch.lettersAt({
        'word': (alpha: Uint8List.fromList([1, 1]), width: 1, height: 2),
      }),
      {'word': at['word']},
      reason: 'a word on the atlas is where it was put',
    );
    expect(
      lettered(at['word']!, 1, 2).read(),
      [255, 255, 255, 255, 255, 255, 255, 128],
      reason: 'and is not put again',
    );
    final surface = shownSurfaceOf(1, 2);
    addTearDown(surface.free);

    lay.lay(surface, (0, 0, 1, 2), [
      (picture: tile, from: (0, 0, 1, 2), onto: (0, 0, 1, 2)),
    ]);

    // White at 255 and at 128, premultiplied.
    expect(
      surface.fingerprint(),
      fingerprintBytes(
        Uint8List.fromList([255, 255, 255, 255, 128, 128, 128, 128]),
      ),
    );
  });

  test('letters their bytes do not match are refused as they are asked', () {
    for (final length in [5, 7]) {
      expect(
        () => batch.lettersAt({
          'odd': (alpha: Uint8List(length), width: 3, height: 2),
        }),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            'letters 3 × 2 of $length bytes',
          ),
        ),
      );
    }
  });

  // Two words over half the atlas tall stand on no shelf together.
  test('an atlas with no room draws what it holds and starts over', () {
    batch.letGoKept();
    final side = gpuGridAtlasSide;
    final tall = side ~/ 2 + 1;
    GpuGridLetters word(int corner) => (
      alpha: Uint8List(side * tall)..[0] = corner,
      width: side,
      height: tall,
    );
    final first = batch.lettersAt({'first': word(255)})!;
    final before = lettered(first['first']!, 1, 1);
    final flushed = batch.debugFlushes;

    final second = batch.lettersAt({'second': word(128)})!;

    expect(batch.debugFlushes, flushed + 1, reason: 'what it held is drawn');
    expect(second['second'], (x: 0, y: 0), reason: 'over the first');
    expect(before.read(), [255, 255, 255, 255]);
    expect(lettered(second['second']!, 1, 1).read(), [255, 255, 255, 128]);
    final again = batch.lettersAt({'first': word(64)})!;
    expect(
      lettered(again['first']!, 1, 1).read(),
      [255, 255, 255, 64],
      reason: 'the first is put again, as one it never held',
    );
  });

  test('what a batch keeps is counted, and let go of when it is told', () {
    batch.lettersAt({
      'kept': (alpha: Uint8List.fromList([255]), width: 1, height: 1),
    });
    batch.flush();
    expect(
      batch.keptBytes,
      greaterThanOrEqualTo(gpuGridAtlasSide * gpuGridAtlasSide),
      reason: 'the atlas, and its plane',
    );

    batch.letGoKept();

    expect(batch.keptBytes, 0);
  });

  // A word put on an earlier flush is read by a tile still held: memory
  // running short lets go of the atlas only once that tile is drawn.
  test('what a batch holds is drawn before it lets go of its atlas', () {
    final at = batch.lettersAt({
      'early': (alpha: Uint8List.fromList([200]), width: 1, height: 1),
    })!;
    batch.flush();
    final tile = lettered(at['early']!, 1, 1);

    batch.letGoKept();

    expect(tile.read(), [255, 255, 255, 200]);
  });

  test('a tile let go of before its batch is flushed is never made', () {
    final tile = batch.picture(1, 1)!;
    batch.draw(tile, Int32List(0));
    tile.free();
    final flushed = batch.debugFlushes;

    batch.flush();

    expect(batch.debugFlushes, flushed, reason: 'nothing was left to make');
  });

  test('a stream the pass refuses refuses its batch as it is flushed', () {
    final tile = aTile(1, 1, [(0, 0, 1, 1, const Color(0xFFFF0000))]);
    final refused = batch.picture(1, 1)!;
    addTearDown(refused.free);
    batch.draw(refused, Int32List.fromList([99]));

    expect(
      tile.read,
      throwsA(
        isA<GpuRefused>().having(
          (refused) => refused.message,
          'why',
          contains('tile 1: op 99 at word 0 is no grid op'),
        ),
      ),
    );
    expect(tile.read(), [0, 0, 0, 0], reason: 'none of the batch is drawn');
  });

  // What data can reach is answered where it is asked, a tile at a time:
  // the batch holds nothing of it, so no flush refuses a frame for it.
  test('a tile past the device\'s side is answered with none', () {
    final most = batch.mostSide;
    final held = aTile(1, 1, [(0, 0, 1, 1, const Color(0xFFFF0000))]);

    expect(batch.picture(most + 1, 1), isNull);
    expect(batch.picture(1, most + 1), isNull);

    expect(held.read(), red, reason: 'what the batch held is drawn');
    final largest = batch.picture(most, most)!;
    addTearDown(largest.free);
    expect((largest.width, largest.height), (most, most));
  });

  test('words past the atlas are answered with none', () {
    final side = gpuGridAtlasSide;
    final held = aTile(1, 1, [(0, 0, 1, 1, const Color(0xFFFF0000))]);
    final flushed = batch.debugFlushes;

    for (final (width, height) in [(side + 1, 1), (1, side + 1)]) {
      expect(
        batch.lettersAt({
          'past': (
            alpha: Uint8List(width * height),
            width: width,
            height: height,
          ),
        }),
        isNull,
        reason: '$width × $height',
      );
    }

    expect(batch.debugFlushes, flushed, reason: 'nothing is flushed for them');
    expect(held.read(), red);
    expect(
      batch.lettersAt({
        'whole': (alpha: Uint8List(side), width: side, height: 1),
      }),
      isNotNull,
      reason: 'a word as wide as the atlas is on it',
    );
  });

  test('a lay past its screen is refused with why', () {
    final surface = shownSurfaceOf(5, 4);
    addTearDown(surface.free);

    expect(
      () => lay.lay(surface, (0, 0, 6, 4), const []),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('is no rectangle of a 5 × 4 screen'),
        ),
      ),
    );
  });
}
