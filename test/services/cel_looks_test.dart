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

  BitmapSurface? look(String frame) =>
      looks.surfaceOf(key(frame), canvasSize: canvasSize);

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
}
