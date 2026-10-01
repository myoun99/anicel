import 'dart:io';
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
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';

import '../helpers/project_scratch_folder.dart';

/// 🚨★★★**A RENDER LOOKS AND LETS GO** (card `render-reads-thaw-into-hot`).
///
/// A storyboard picture or an export frame reads cels nobody is drawing
/// on. Read as a USE, each cold or file-backed one thawed into the hot
/// tier — measured 09-28: filling a 13-cut film's storyboard took the hot
/// tier from 149 to 529MB — and, newest in line, pushed the cels of the cut
/// being drawn toward cooling. The budget belongs to what feeds the screen
/// first. A LOOK gets the same pixels and leaves the store as it found it.
void main() {
  const canvasSize = CanvasSize(width: 16, height: 16);
  final origin = TileCoord(x: 0, y: 0);

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  BitmapSurface inkSurface({int seed = 1}) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * seed * 31 + seed) & 0xFF;
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 8,
      tiles: {origin: BitmapTile(size: 8, pixels: pixels)},
    );
  }

  AnicelCelBlob blobOf(BrushFrameKey k, BitmapSurface surface) =>
      AnicelCelBlob.encode(AnicelCelEntry.fromSurface(k, surface));

  test('🎯a LOOK at a cold cel gets its pixels and leaves every tier as it '
      'found it — nothing hot, the parked copy kept, no picture seeded', () {
    final store = BrushFrameStore();
    final k = key('f');
    final source = inkSurface(seed: 7);
    store.restoreBaked({k: blobOf(k, source)});
    final parked = store.coldBakedBytes;

    final looked = store.currentSurfaceWithoutReplay(
      k,
      canvasSize: canvasSize,
      read: CelRead.look,
    );

    expect(looked!.tiles[origin]!.pixels, source.tiles[origin]!.pixels);
    expect(store.hotBakedBytes, 0, reason: 'nothing thawed into the budget');
    expect(store.isCelCold(k), isTrue, reason: 'the parked copy stays');
    expect(store.coldBakedBytes, parked);
    expect(
      store.displayCacheOrNull(k),
      isNull,
      reason: 'no picture seeded for a screen that is not showing it',
    );

    // The same read as a USE keeps what it thaws — the one difference.
    store.currentSurfaceWithoutReplay(k, canvasSize: canvasSize);
    expect(store.isCelCold(k), isFalse);
    expect(store.hotBakedBytes, greaterThan(0));
  });

  test('the baked-truth door looks the same way — the sheet ink export '
      'reads through it', () {
    final store = BrushFrameStore();
    final k = key('ink');
    final source = inkSurface(seed: 9);
    store.restoreBaked({k: blobOf(k, source)});

    final looked = store.bakedSurfaceOrNull(k, read: CelRead.look);

    expect(looked!.tiles[origin]!.pixels, source.tiles[origin]!.pixels);
    expect(store.hotBakedBytes, 0);
    expect(store.isCelCold(k), isTrue);
    expect(store.displayCacheOrNull(k), isNull);
  });

  test('a LOOK at a FILE-BACKED cel reads the file and keeps nothing', () {
    final directory = Directory.systemTemp.createTempSync('qa-look');
    deleteAfterSessionEnds(directory);
    final store = BrushFrameStore();
    final k = key('saved');
    final source = inkSurface(seed: 11);
    final blob = blobOf(k, source);
    final path = '${directory.path}/cel.bin';
    File(path).writeAsBytesSync(blob.bytes);
    store.restoreFromFile({
      k: AnicelCelFileRef(
        filePath: path,
        dataOffset: 0,
        length: blob.bytes.length,
        canvasSize: canvasSize,
        tileSize: blob.tileSize,
      ),
    });

    final looked = store.currentSurfaceWithoutReplay(
      k,
      canvasSize: canvasSize,
      read: CelRead.look,
    );

    expect(looked!.tiles[origin]!.pixels, source.tiles[origin]!.pixels);
    expect(store.hotBakedBytes, 0);
    expect(store.isCelFileBacked(k), isTrue);
    expect(store.displayCacheOrNull(k), isNull);
  });

  test('a LOOK at a hot cel leaves its place in line — the cel the app used '
      'last is still the last to cool', () async {
    final store = BrushFrameStore();
    final older = key('older');
    final newer = key('newer');
    store.storeBakedSurface(older, inkSurface(seed: 3));
    store.storeBakedSurface(newer, inkSurface(seed: 5));
    // Room for exactly the two: one more cel cools ONE, the first in line.
    store.hotCelByteBudget = store.hotBakedBytes;

    store.currentSurfaceWithoutReplay(
      older,
      canvasSize: canvasSize,
      read: CelRead.look,
    );
    store.storeBakedSurface(key('drawn'), inkSurface(seed: 13));
    await store.drainCooling();

    expect(store.isCelCold(older), isTrue, reason: 'still first in line');
    expect(store.isCelCold(newer), isFalse);

    // A USE of the same cel moves it to the back of the line.
    final used = BrushFrameStore();
    used.storeBakedSurface(older, inkSurface(seed: 3));
    used.storeBakedSurface(newer, inkSurface(seed: 5));
    used.hotCelByteBudget = used.hotBakedBytes;
    used.currentSurfaceWithoutReplay(older, canvasSize: canvasSize);
    used.storeBakedSurface(key('drawn'), inkSurface(seed: 13));
    await used.drainCooling();
    expect(used.isCelCold(newer), isTrue, reason: 'premise: a use reorders');
    expect(used.isCelCold(older), isFalse);
  });
}
