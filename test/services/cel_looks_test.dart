import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/cel_looks.dart';

import '../helpers/cels_parked_cold.dart';

/// The cels a render looks at, each held for ONE frame after the last
/// frame that looked at it (`gpu-canonical-store-Q10`, 유저 2026-11-10
/// 「추천대로 법 지키도록」): what reads a drawing held across a run of frames
/// once, and leaves the store as it stood.
void main() {
  const canvasSize = CanvasSize(
    width: defaultCelTileSize,
    height: defaultCelTileSize,
  );
  final origin = TileCoord(x: 0, y: 0);

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  BitmapSurface ink(int seed) {
    final pixels = Uint8List(defaultCelTileSize * defaultCelTileSize * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = seed * 40;
      pixels[i + 3] = 255;
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: defaultCelTileSize,
      tiles: {origin: BitmapTile(size: defaultCelTileSize, pixels: pixels)},
    );
  }

  late BrushFrameStore store;
  late CelLooks looks;

  setUp(() {
    store = BrushFrameStore();
    parkCold(store, {key('a'): ink(1), key('b'): ink(2)});
    looks = CelLooks(store);
  });

  BitmapSurface? look(String frame, {LooksAhead? ahead}) =>
      looks.surfaceOf(key(frame), canvasSize: canvasSize, ahead: ahead);

  Future<LooksAhead> readAhead(List<String> frames) => looks.ahead([
    for (final frame in frames) key(frame),
  ], canvasSize: canvasSize);

  test('🎯a look gets a cold cel\'s pixels and the store keeps it as it '
      'was — cold, nothing hot, no picture seeded', () {
    final surface = look('a');

    expect(surface!.tiles[origin]!.pixels, ink(1).tiles[origin]!.pixels);
    expect(store.isCelCold(key('a')), isTrue);
    expect(store.hotBakedBytes, 0);
    expect(store.displayCacheOrNull(key('a')), isNull);
  });

  test('🚨looked at again by this frame or the next, it is the surface it '
      'was — read once', () {
    final first = look('a');
    expect(identical(look('a'), first), isTrue);

    looks.nextFrame();
    expect(identical(look('a'), first), isTrue);
    looks.nextFrame();
    expect(identical(look('a'), first), isTrue);
    expect(looks.reads, 1);
  });

  test('🚨a cel stays for ONE frame that does not look at it, and is read '
      'again the frame after that', () {
    look('a');
    looks.nextFrame();
    look('b');
    looks.nextFrame();
    look('a');

    expect(looks.reads, 3);
  });

  test('🎯carried, a cel stays held through the frames of a picture handed '
      'again — however many', () {
    look('a');
    for (var frame = 0; frame < 5; frame += 1) {
      looks.nextFrame();
      looks.carry([key('a')], canvasSize: canvasSize);
    }
    looks.nextFrame();
    look('a');

    expect(looks.reads, 1);
  });

  test('a carry keeps what was looked at, and reads nothing', () {
    looks.carry([key('a')], canvasSize: canvasSize);
    expect(looks.reads, 0);
  });

  test('a cel that moved on is looked at anew — its new pixels', () {
    look('a');
    // An edit, as the app makes one: its revision, then its pixels.
    store
      ..markCelEdited(key('a'))
      ..storeBakedSurface(key('a'), ink(3));

    expect(look('a')!.tiles[origin]!.pixels, ink(3).tiles[origin]!.pixels);
    expect(looks.reads, 2);
  });

  test('letting go holds nothing — the next look reads', () {
    look('a');
    looks.letGo();
    look('a');

    expect(looks.reads, 2);
  });

  group('read ahead of a frame\'s drawing (card '
      'one-cut-of-fnk02-holds-nine-gigabytes, Q1)', () {
    test('🎯a cold cel read ahead is in hand for the drawing — read once, '
        'its pixels, and the store as it was', () async {
      await readAhead(['a']);
      expect(looks.reads, 1);

      final surface = look('a');

      expect(surface!.tiles[origin]!.pixels, ink(1).tiles[origin]!.pixels);
      expect(looks.reads, 1, reason: 'the drawing read nothing');
      expect(looks.holds(key('a'), canvasSize: canvasSize), isTrue);
      expect(store.isCelCold(key('a')), isTrue);
      expect(store.hotBakedBytes, 0);
      expect(store.displayCacheOrNull(key('a')), isNull);
    });

    test('🚨two frames that read one cel ahead at once read it once', () async {
      final both = await Future.wait([
        readAhead(['a']),
        readAhead(['a', 'b']),
      ]);

      expect(looks.reads, 2, reason: 'a once, b once');
      expect(
        identical(both[0].surfaces.single, look('a', ahead: both[1])),
        isTrue,
      );
    });

    test('🚨what a frame read ahead is its own until it draws — the looks '
        'two frames on, its drawing reads nothing', () async {
      final mine = await readAhead(['a']);
      looks
        ..nextFrame()
        ..nextFrame();
      expect(
        looks.holds(key('a'), canvasSize: canvasSize),
        isFalse,
        reason: '⛔premise: the looks themselves let it go',
      );

      final surface = look('a', ahead: mine);

      expect(surface!.tiles[origin]!.pixels, ink(1).tiles[origin]!.pixels);
      expect(looks.reads, 1);
    });

    test('a frame that did not read it reads it, the looks two frames '
        'on', () async {
      await readAhead(['a']);
      looks
        ..nextFrame()
        ..nextFrame();

      look('a');

      expect(looks.reads, 2);
    });

    test('🚨a cel edited while it is read ahead is not held by what was '
        'read — the drawing reads its new pixels', () async {
      final reading = readAhead(['a']);
      // An edit, as the app makes one: its revision, then its pixels.
      store
        ..markCelEdited(key('a'))
        ..storeBakedSurface(key('a'), ink(3));
      final mine = await reading;

      expect(mine.surfaces, isEmpty, reason: 'what was read is of neither');
      expect(
        look('a', ahead: mine)!.tiles[origin]!.pixels,
        ink(3).tiles[origin]!.pixels,
      );
    });

    test('🚨what is held beside the store is weighed a surface once, and '
        'none the store holds hot', () async {
      // A tile of more than one colour.
      BitmapSurface shaded(int seed) {
        final pixels = Uint8List(defaultCelTileSize * defaultCelTileSize * 4);
        for (var i = 0; i < pixels.length; i += 1) {
          pixels[i] = (i * 7 + seed) & 0xFF;
        }
        return BitmapSurface(
          canvasSize: canvasSize,
          tileSize: defaultCelTileSize,
          tiles: {origin: BitmapTile(size: defaultCelTileSize, pixels: pixels)},
        );
      }

      parkCold(store, {key('p'): shaded(1), key('q'): shaded(2)});
      store.storeBakedSurface(key('h'), shaded(3));
      final each = store.hotBakedBytes;
      expect(each, greaterThan(0), reason: '⛔premise');

      final mine = await readAhead(['p', 'q', 'h']);

      expect(
        looks.bytesBesideTheStore([mine]),
        2 * each,
        reason: 'p and q, each held by the looks and by the frame',
      );
      looks.letGo();
      expect(looks.bytesBesideTheStore(const []), 0);
      expect(looks.bytesBesideTheStore([mine]), 2 * each);
    });

    test('🚨a frame that made its hold before the read holds each cel from '
        'the moment it is read', () async {
      final mine = LooksAhead();
      expect(mine.surfaces, isEmpty);

      final read = await looks.ahead(
        [key('a')],
        canvasSize: canvasSize,
        into: mine,
      );

      expect(read, same(mine));
      expect(mine.surfaces, hasLength(1));
    });

    test('what the looks hold is theirs to tell, for whoever weighs '
        'it', () async {
      final mine = await readAhead(['a', 'b']);

      expect(looks.surfaces, unorderedEquals(mine.surfaces));
      expect(mine.surfaces, hasLength(2));

      looks.letGo();
      expect(looks.surfaces, isEmpty);
      expect(mine.surfaces, hasLength(2), reason: 'the frame still holds it');
    });
  });
}
