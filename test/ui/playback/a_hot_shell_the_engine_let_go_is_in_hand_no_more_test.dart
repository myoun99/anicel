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
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/shells_with_no_bytes.dart';

/// 🚨Card `cel-originals-are-held-twice-in-ram-and-on-the-gpu` ②: a cel the
/// saved file holds is used as the shell a look left of it, hot with no
/// bytes here (`BrushFrameStore.bakedSurfaceOrNull`) — and a full pool lets
/// a shell's slots go as freely as any. Drawn then, a tile of it would read
/// its cel's kept bytes again on the thread that draws: the whole cel
/// decoded there, which the card `cel-thaw-holds-the-ui-thread` took off it
/// (13 to 32 ms a cel).
///
/// A screen asks whether a cel is in hand before it draws the frame as it
/// stands (`FramePictures.allInHand`), and reads in what is not, on
/// workers. A cel made hot was in hand for good, so nothing read it in
/// again: here it is in hand no more once the engine holds it no more
/// whole.
void main() {
  const canvasSize = CanvasSize(
    width: defaultCelTileSize,
    height: defaultCelTileSize,
  );
  final origin = TileCoord(x: 0, y: 0);
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );

  /// A cel of one tile, drawn on.
  BitmapSurface ink() {
    final pixels = Uint8List(defaultCelTileSize * defaultCelTileSize * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = (80 + i ~/ 4) % 251;
      pixels[i + 3] = 255;
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: defaultCelTileSize,
      tiles: {origin: BitmapTile(size: defaultCelTileSize, pixels: pixels)},
    );
  }

  late ShellsWithNoBytes engine;
  late BrushFrameStore store;
  late LayerFrameImageCache images;

  /// The cel kept in a file, looked at, let go as a look lets go of it, and
  /// read in by a screen that stands on it: hot as its shell.
  Future<BitmapSurface> stoodOnAsItsShell() async {
    engine = ShellsWithNoBytes();
    store = BrushFrameStore(shells: engine);
    keepInAFile(store, {key: ink()});
    images = LayerFrameImageCache(frameStore: store);
    final looked = (await store.lookAhead(key, canvasSize: canvasSize))!;
    store.keepShellOf(
      key,
      looked,
      canvasSize: canvasSize,
      revision: store.sourceRevisionOf(key),
    );
    await images.readIn(key, canvasSize: canvasSize);
    final shell = engine.made.last;
    expect(
      images.storedSurfaceOrNull(key, canvasSize: canvasSize),
      same(shell),
      reason: '⛔premise: the screen draws the shell',
    );
    return shell;
  }

  test('a cel hot as its shell is in hand while the engine holds it whole',
      () async {
    await stoodOnAsItsShell();

    expect(images.storedSurfaceIsInHand(key, canvasSize: canvasSize), isTrue);
    expect(engine.reads, 0);
  });

  test('🚨once the engine let a slot of it go it is in hand no more — and '
      'read in, it is thawed: its bytes here, no tile of the shell read',
      () async {
    final shell = await stoodOnAsItsShell();
    engine
      ..whole = false
      ..slots = false;

    expect(images.storedSurfaceIsInHand(key, canvasSize: canvasSize), isFalse);
    expect(store.hotBakedSurfaceOrNull(key), isNull);

    await images.readIn(key, canvasSize: canvasSize);

    expect(images.storedSurfaceIsInHand(key, canvasSize: canvasSize), isTrue);
    final drawn = images.storedSurfaceOrNull(key, canvasSize: canvasSize)!;
    expect(drawn, isNot(same(shell)));
    expect(drawn.tiles[origin]!.hasItsBytesHere, isTrue);
    expect(drawn.tiles[origin]!.pixels, ink().tiles[origin]!.pixels);
    expect(engine.reads, 0, reason: 'no tile of the shell was read');
  });
}
