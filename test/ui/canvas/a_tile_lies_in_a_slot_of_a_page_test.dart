@Tags(['gpu'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/chained_picture.dart';
import 'package:anicel/src/ui/canvas/pictured_tiles.dart';
import 'package:anicel/src/ui/canvas/tile_pages.dart';
import 'package:anicel/src/ui/canvas/tile_picture_budget.dart';
import 'package:anicel/src/ui/canvas/tiled_surface_compose.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart' show noFlutterGpu;

/// 🚨★★★A COMMITTED TILE'S PICTURE IS A SLOT OF A PAGE, AND A PAINT LAYS A
/// PAGE'S SLOTS IN ONE DRAW — THE BYTES ITS OWN PICTURE LAYS
/// (frame-composite-draws-each-tile-on-its-own, 2026-10-28).
///
/// 🔬S5_BA cut 352: a film of 2381 tiles cost one draw a tile, 22 ms
/// rastered; out of one texture, a page's in one `drawAtlas`, 8.5 ms and
/// the same bytes. The door writes a tile's bytes straight into a slot
/// (`TilePages`), drawn the moment it is handed out — the GPU's one queue
/// takes the write first. These pins read the bytes on the engine that
/// writes pages: Impeller with Flutter GPU.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tileSize = 16;
  const canvasSize = CanvasSize(width: 64, height: 48);

  /// A tile of its own pattern, [seed]'s: every alpha from clear to opaque
  /// across it, straight, as a tile keeps its bytes.
  BitmapTile patterned(int seed) {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var i = 0; i < tileSize * tileSize; i += 1) {
      final at = i * 4;
      pixels[at] = (i * 13 + seed * 29) % 256;
      pixels[at + 1] = (i * 7 + seed * 53 + 90) % 256;
      pixels[at + 2] = (i * 3 + seed * 17 + 200) % 256;
      pixels[at + 3] = (i * 37 + seed * 11) % 256;
    }
    return BitmapTile(size: tileSize, pixels: pixels);
  }

  /// Every coordinate of the canvas but one, each a pattern of its own.
  BitmapSurface surfaceOf(int seed) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      for (var ty = 0; ty < canvasSize.height ~/ tileSize; ty += 1)
        for (var tx = 0; tx < canvasSize.width ~/ tileSize; tx += 1)
          if (tx != 1 || ty != 1)
            TileCoord(x: tx, y: ty): patterned(seed + ty * 8 + tx),
    },
  );

  ({BitmapTileImageCache cache, TilePictureBudget budget}) picturesIn(
    TilePages pages,
  ) {
    final pictured = PicturedTiles();
    final cache = BitmapTileImageCache(pictured: pictured, pages: pages);
    return (
      cache: cache,
      budget: TilePictureBudget(cache: cache, pictured: pictured),
    );
  }

  Future<Uint8List> rgba(ui.Image image) async =>
      (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
          .asUint8List();

  /// The canvas over a backdrop a translucent row blends with, [paint] on
  /// top of it, rastered 1:1.
  Future<Uint8List> laid(void Function(ui.Canvas canvas) paint) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..drawRect(
        ui.Rect.fromLTWH(0, 0, canvasSize.width * 1.0, canvasSize.height * 1.0),
        ui.Paint()..color = const ui.Color(0xFF3070B0),
      )
      ..drawRect(
        ui.Rect.fromLTWH(0, 0, canvasSize.width / 2, canvasSize.height * 1.0),
        ui.Paint()..color = const ui.Color(0xC0C0D040),
      );
    paint(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(canvasSize.width, canvasSize.height);
    picture.dispose();
    final bytes = await rgba(image);
    image.dispose();
    return bytes;
  }

  /// [surface]'s committed tiles as the painter lays them, its pictures out
  /// of [pictures], the layer riding the draws in [layerPaint].
  void paintThrough(
    ui.Canvas canvas,
    BitmapSurface surface,
    ({BitmapTileImageCache cache, TilePictureBudget budget}) pictures, {
    ui.Paint? layerPaint,
  }) {
    BitmapSurfacePainter(
      surface: surface,
      showTransparentBackground: false,
      lineage: 'slots',
      tileImageCache: pictures.cache,
      pictureBudget: pictures.budget,
    ).paintContentInto(canvas, layerPaint: layerPaint, pixelRatio: 1);
  }

  /// Every tile's OWN picture, through the door, drawn one by one in
  /// [paint] — what a slot has to lay.
  void ownPicturesOf(
    ui.Canvas canvas,
    BitmapSurface surface, {
    ui.Paint? paint,
  }) {
    for (final MapEntry(key: coord, value: tile) in surface.tiles.entries) {
      final image = BitmapTileImageCache.pictureOfTile(tile);
      canvas.drawImage(
        image,
        ui.Offset(coord.x * tileSize * 1.0, coord.y * tileSize * 1.0),
        (paint == null ? ui.Paint() : ui.Paint.from(paint))
          ..filterQuality = ui.FilterQuality.none
          ..isAntiAlias = false,
      );
      image.dispose();
    }
  }

  test('a committed tile\'s picture is a slot of a page, and a paint lays '
      'the bytes its own picture lays', () async {
    final pictures = picturesIn(TilePages());
    final surface = surfaceOf(1);
    final shown = await laid((canvas) => paintThrough(canvas, surface, pictures));
    for (final tile in surface.tiles.values) {
      expect(pictures.cache.heldFor(tile), isA<TileSlot>());
    }
    expect(shown, await laid((canvas) => ownPicturesOf(canvas, surface)));
  }, skip: noFlutterGpu);

  // 🔬A colour matrix with an alpha under 255 is 1 apart in an atlas on
  // Impeller, so each slot is laid by itself there (`SlotsByPage`).
  for (final (name, layerPaint) in [
    (
      'a ghost\'s tint at half alpha',
      ui.Paint()
        ..color = const ui.Color(0x80000000)
        ..colorFilter = const ui.ColorFilter.matrix(<double>[
          0, 0, 0, 0, 255, //
          0, 0, 0, 0, 64,
          0, 0, 0, 0, 32,
          0, 0, 0, 0.7529, 0,
        ]),
    ),
    (
      'a brighten, opaque',
      ui.Paint()
        ..colorFilter = const ui.ColorFilter.matrix(<double>[
          1.2, 0, 0, 0, 10, //
          0, 1.1, 0, 0, 5,
          0, 0, 0.9, 0, 0,
          0, 0, 0, 1, 0,
        ]),
    ),
    ('half alpha', ui.Paint()..color = const ui.Color(0x80000000)),
    (
      'an add at half alpha',
      ui.Paint()
        ..color = const ui.Color(0x80000000)
        ..blendMode = ui.BlendMode.plus,
    ),
  ]) {
    test('a row riding $name lays the bytes its own pictures lay', () async {
      final pictures = picturesIn(TilePages());
      final surface = surfaceOf(2);
      final shown = await laid(
        (canvas) =>
            paintThrough(canvas, surface, pictures, layerPaint: layerPaint),
      );
      expect(
        pictures.cache.heldFor(surface.tiles.values.first),
        isA<TileSlot>(),
        reason: '⛔premise: the tiles lie in slots',
      );
      expect(
        shown,
        await laid(
          (canvas) => ownPicturesOf(canvas, surface, paint: layerPaint),
        ),
      );
    }, skip: noFlutterGpu);
  }

  test('a paint lays a page\'s slots in ONE draw — and each by itself where '
      'a colour matrix rides', () {
    final pictures = picturesIn(TilePages());
    final surface = surfaceOf(7);
    final canvasRect = ui.Rect.fromLTWH(
      0,
      0,
      canvasSize.width * 1.0,
      canvasSize.height * 1.0,
    );
    int drawn(_RecordingCanvasThatShows canvas, Symbol draw) => canvas
        .invocations
        .where((call) => call.invocation.memberName == draw)
        .length;

    final plain = _RecordingCanvasThatShows(canvasRect);
    paintThrough(plain, surface, pictures);
    expect(drawn(plain, #drawAtlas), 1, reason: 'eleven slots, one page');
    expect(drawn(plain, #drawImage) + drawn(plain, #drawImageRect), 0);

    final tinted = _RecordingCanvasThatShows(canvasRect);
    paintThrough(
      tinted,
      surface,
      pictures,
      layerPaint: ui.Paint()
        ..color = const ui.Color(0x80000000)
        ..colorFilter = const ui.ColorFilter.mode(
          ui.Color(0xFFFF4020),
          ui.BlendMode.srcIn,
        ),
    );
    expect(drawn(tinted, #drawAtlas), 0);
    expect(drawn(tinted, #drawImageRect), surface.tiles.length);
  }, skip: noFlutterGpu);

  test('🚨a slot is written once: a picture recorded before its tile went '
      'lays the same bytes after its page has taken other tiles', () async {
    final pages = TilePages();
    final pictures = picturesIn(pages);
    final surface = surfaceOf(3);
    final recorder = ui.PictureRecorder();
    paintThrough(ui.Canvas(recorder), surface, pictures);
    final early = recorder.endRecording();
    final expected = await laid((canvas) => ownPicturesOf(canvas, surface));
    // The tiles let their pictures go — their slots are dead — and other
    // tiles take pictures through the same pages, past the first page.
    for (final tile in surface.tiles.values) {
      pictures.cache.releasePicture(tile);
    }
    for (var round = 0; round < 6; round += 1) {
      final others = surfaceOf(100 + round * 20);
      for (final tile in others.tiles.values) {
        pictures.cache.pictureFor(tile);
      }
    }
    expect(
      await laid((canvas) => canvas.drawPicture(early)),
      expected,
      reason: 'a slot written again would show the early picture another '
          'tile\'s bytes',
    );
    early.dispose();
  }, skip: noFlutterGpu);

  test('a page counts whole, and goes once it takes no more and every '
      'slot of it is dead', () async {
    final pages = TilePages();
    final pictures = picturesIn(pages);
    // The first page of 16 px tiles is four across: 16 slots, 64² texels.
    const firstPage = 64 * 64 * 4;
    final first = surfaceOf(4);
    final firstTiles = first.tiles.values.toList();
    expect(firstTiles, hasLength(11));
    // Read across no await, so no other test's tile can be let go between.
    final picturesBefore = BitmapTileImageCache.liveImageBytes;
    for (final tile in firstTiles) {
      pictures.cache.pictureFor(tile);
    }
    expect(pages.bytes, firstPage);
    expect(
      BitmapTileImageCache.liveImageBytes - picturesBefore,
      firstPage,
      reason: 'the tile pictures\' total adds the page whole — and no '
          'texture of a tile\'s own beside its slot',
    );
    for (final tile in firstTiles) {
      pictures.cache.releasePicture(tile);
    }
    expect(
      pages.bytes,
      firstPage,
      reason: 'the page still takes slots: it stays',
    );
    // Five more fill the first page (16), and a sixth opens the second,
    // 128²: the first takes no more, but five of its slots live.
    final more = surfaceOf(5).tiles.values.take(6).toList();
    for (final tile in more) {
      pictures.cache.pictureFor(tile);
    }
    expect(
      pages.bytes,
      firstPage + 128 * 128 * 4,
      reason: 'a page that takes no more stays while a slot of it lives',
    );
    for (final tile in more.take(5)) {
      pictures.cache.releasePicture(tile);
    }
    expect(pages.bytes, 128 * 128 * 4, reason: 'its last slot died');
  }, skip: noFlutterGpu);

  test('a surface composed from tiles in slots is the bytes of their own '
      'pictures — at once, and in turn from the slots held', () async {
    final pictures = picturesIn(TilePages());
    final surface = surfaceOf(8);
    final recorder = ui.PictureRecorder();
    ownPicturesOf(ui.Canvas(recorder), surface);
    final reference = recorder.endRecording();
    final referenceImage = await reference.toImage(
      canvasSize.width,
      canvasSize.height,
    );
    reference.dispose();
    final expected = await rgba(referenceImage);
    referenceImage.dispose();

    final now = composeTiledSurfaceImageNow(surface, reuse: pictures.cache);
    for (final tile in surface.tiles.values) {
      expect(pictures.cache.heldFor(tile), isA<TileSlot>());
    }
    expect(await rgba(now), expected, reason: 'at once');
    now.dispose();
    final inTurn = await composeTiledSurfaceImage(
      surface,
      reuse: pictures.cache,
    );
    expect(await rgba(inTurn!), expected, reason: 'in turn');
    inTurn.dispose();
  }, skip: noFlutterGpu);

  test('drawn reduced, a tile in a slot leaves it for a picture of its own '
      'carrying its chain — the slot\'s bytes', () async {
    final pictures = picturesIn(TilePages());
    final tile = patterned(6);
    final slot = pictures.cache.pictureFor(tile);
    expect(slot, isA<TileSlot>(), reason: '⛔premise');
    final chained = pictures.cache.chainedPictureFor(tile);
    expect(carriesChain(chained), isTrue);
    expect(pictures.cache.heldFor(tile)?.image, same(chained));
    final own = BitmapTileImageCache.pictureOfTile(tile);
    expect(await rgba(chained), await rgba(own));
    own.dispose();
  }, skip: noFlutterGpu);
}

/// A recording canvas that shows the whole of [bounds], untransformed — as
/// the painter asks a canvas what of it shows and where its grid lies.
class _RecordingCanvasThatShows extends TestRecordingCanvas {
  _RecordingCanvasThatShows(this.bounds);

  final ui.Rect bounds;

  @override
  ui.Rect getLocalClipBounds() => bounds;

  @override
  ui.Rect getDestinationClipBounds() => bounds;

  @override
  Float64List getTransform() => Float64List(16)
    ..[0] = 1
    ..[5] = 1
    ..[10] = 1
    ..[15] = 1;
}
