import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_fill_promotion.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart'
    show PromotedStrokeTile;
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/chained_picture.dart';
import 'package:anicel/src/ui/canvas/pictured_tiles.dart';
import 'package:anicel/src/ui/canvas/tile_picture_budget.dart';

/// 🚨★★★A TILE A SCREEN DRAWS REDUCED IS DRAWN FROM ITS OWN PICTURE'S MIP
/// CHAIN — made in the paint that shows it, every one it shows, in the
/// picture's place (one-picture-per-frame ②-5b-2, 유저 D7-2-Q2 「배율이
/// 어떻든 항상 원본 한장」).
///
/// A frame's one picture is a render and carries the engine's chain; a
/// door's upload carries none, so on Impeller a tile drawn reduced from it
/// samples `medium` as `low` does (🔬the real Windows app, 25%: 15295 of
/// 16384 pixels apart from the one picture — `chained_picture.dart`). The
/// test runner's Skia chains a door picture by itself, so what is pinned
/// here is the ROAD — which picture a reduced paint draws, and that it is
/// the tile's one picture — and the pixels of it on Impeller are pinned in
/// `a_surface_drawn_reduced_is_its_one_picture_test`.
///
/// ↩️Below 100% a block of tiles was drawn as one level tile — their box
/// mean, made in the paint — until this round.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tileSize = 16;
  // Ten by five: fifty tiles, past the 32 a paint once made of the level
  // tiles before a ration was dropped (`_CoordinatePicture`).
  const canvasSize = CanvasSize(width: 160, height: 80);

  /// A tile of an opaque black column every fourth pixel.
  BitmapTile columns() {
    final pixels = Uint8List(tileSize * tileSize * 4);
    for (var y = 0; y < tileSize; y += 1) {
      for (var x = 0; x < tileSize; x += 4) {
        pixels[(y * tileSize + x) * 4 + 3] = 255;
      }
    }
    return BitmapTile(size: tileSize, pixels: pixels);
  }

  BitmapSurface surfaceOfColumns() => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      for (var ty = 0; ty < canvasSize.height ~/ tileSize; ty += 1)
        for (var tx = 0; tx < canvasSize.width ~/ tileSize; tx += 1)
          TileCoord(x: tx, y: ty): columns(),
    },
  );

  Future<Uint8List> rgba(ui.Image image) async =>
      (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
          .asUint8List();

  /// [painter] drawn on its own at [zoom] over white, as raw RGBA.
  Future<Uint8List> shownAt(BitmapSurfacePainter painter, double zoom) async {
    final width = (canvasSize.width * zoom).ceil();
    final height = (canvasSize.height * zoom).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..drawRect(
        ui.Rect.fromLTWH(0, 0, width * 1.0, height * 1.0),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
    painter.paint(canvas, ui.Size(width * 1.0, height * 1.0));
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    final bytes = await rgba(image);
    image.dispose();
    return bytes;
  }

  ({BitmapTileImageCache cache, TilePictureBudget budget}) ownPictures() {
    final pictured = PicturedTiles();
    final cache = BitmapTileImageCache(pictured: pictured);
    return (
      cache: cache,
      budget: TilePictureBudget(cache: cache, pictured: pictured),
    );
  }

  test('a picture remade with its chain is the same picture at 100%, made '
      'once', () async {
    final tile = columns();
    final door = BitmapTileImageCache.pictureOfTile(tile);
    final chained = chainedPictureOf(door);
    expect(carriesChain(door), isFalse, reason: '⛔premise: a door picture');
    expect(carriesChain(chained), isTrue);
    expect(await rgba(chained), await rgba(door));
    expect(chainedPictureOf(chained), same(chained), reason: 'made once');
    expect(
      pictureBytesOf(chained),
      tileSize * tileSize * 4 + tileSize * tileSize * 4 ~/ 3,
      reason: 'the chain is a third more of the picture, and counted',
    );
  });

  test('a tile drawn reduced gains its chain IN ITS PICTURE\'S PLACE — one '
      'picture a tile, counted with its chain', () {
    final pictures = ownPictures();
    final tile = columns();
    final door = pictures.cache.pictureFor(tile);
    final before = BitmapTileImageCache.liveImageBytes;
    final chained = pictures.cache.chainedPictureFor(tile);
    expect(carriesChain(chained), isTrue);
    expect(
      pictures.cache.imageFor(tile),
      same(chained),
      reason: 'the tile\'s one picture is the chained one now',
    );
    expect(chained, isNot(same(door)));
    expect(
      BitmapTileImageCache.liveImageBytes - before,
      tileSize * tileSize * 4 ~/ 3,
      reason: 'the door picture went: only the chain is added',
    );
    expect(pictures.cache.chainedPictureFor(tile), same(chained));
    expect(pictures.cache.pictureFor(tile), same(chained));
    pictures.cache.releasePicture(tile);
  });

  test('a paint draws every tile it shows reduced from its chain, in that '
      'paint — and at 100% gives none a chain', () async {
    for (final (zoom, chains) in [(1.0, false), (0.25, true), (0.6, true)]) {
      final pictures = ownPictures();
      final surface = surfaceOfColumns();
      await shownAt(
        BitmapSurfacePainter(
          surface: surface,
          viewport: CanvasViewport(zoom: zoom),
          showTransparentBackground: false,
          lineage: 'chained-at-$zoom',
          tileImageCache: pictures.cache,
          pictureBudget: pictures.budget,
        ),
        zoom,
      );
      final tiles = surface.tiles.values.toList();
      expect(tiles, hasLength(50));
      for (final tile in tiles) {
        final picture = pictures.cache.imageFor(tile);
        expect(picture, isNotNull, reason: 'at $zoom every tile shown');
        expect(carriesChain(picture!), chains, reason: 'at $zoom');
        pictures.cache.releasePicture(tile);
      }
    }
  });

  test('zoomed out, the pictures a paint shows are the ones the screen needs '
      '— the budget does not let them go', () async {
    final pictures = ownPictures();
    final surface = surfaceOfColumns();
    final stranger = columns();
    pictures.cache.pictureFor(stranger);
    await shownAt(
      BitmapSurfacePainter(
        surface: surface,
        viewport: CanvasViewport(zoom: 0.25),
        showTransparentBackground: false,
        lineage: 'needed-zoomed-out',
        tileImageCache: pictures.cache,
        pictureBudget: pictures.budget,
      ),
      0.25,
    );
    pictures.budget.byteBudget = 0;
    expect(pictures.budget.letGo(), 1, reason: 'the one nobody shows');
    expect(pictures.cache.imageFor(stranger), isNull);
    for (final tile in surface.tiles.values) {
      expect(pictures.cache.imageFor(tile), isNotNull);
      pictures.cache.releasePicture(tile);
    }
  });

  test('the live stroke\'s picture drawn reduced gains its chain in place, '
      'and pen-up hands that very picture over', () async {
    final pictures = ownPictures();
    final surface = surfaceOfColumns();
    final coord = TileCoord(x: 2, y: 1);
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = surface;
    addTearDown(overlay.dispose);
    overlay.showResultTiles([
      PromotedStrokeTile(coord, columns(), fillPromotionRevision),
    ]);
    final door = overlay.tileImages[coord]!;
    await shownAt(
      BitmapSurfacePainter(
        surface: surface,
        viewport: CanvasViewport(zoom: 0.25),
        overlayModel: overlay,
        showTransparentBackground: false,
        lineage: 'a-stroke-zoomed-out',
        tileImageCache: pictures.cache,
        pictureBudget: pictures.budget,
      ),
      0.25,
    );
    final shown = overlay.tileImages[coord]!;
    expect(shown, isNot(same(door)));
    expect(carriesChain(shown), isTrue);
    expect(
      overlay.takeTileImageAt(coord, revision: fillPromotionRevision),
      same(shown),
      reason: 'the picture the screen showed is the one the tile adopts',
    );
    shown.dispose();
    for (final tile in surface.tiles.values) {
      pictures.cache.releasePicture(tile);
    }
  });

  test('reduced, a surface is drawn at the display\'s filter — at 25% a '
      'column every fourth pixel is a quarter grey, not nearest', () async {
    final pictures = ownPictures();
    final surface = surfaceOfColumns();
    final bytes = await shownAt(
      BitmapSurfacePainter(
        surface: surface,
        viewport: CanvasViewport(zoom: 0.25),
        showTransparentBackground: false,
        lineage: 'filtered-at-a-quarter',
        tileImageCache: pictures.cache,
        pictureBudget: pictures.budget,
      ),
      0.25,
    );
    // Inside the canvas, off its edge: every pixel a 4×4 block, one column
    // of ink — 255 × 3/4.
    for (var i = 0; i < 40 * 20; i += 1) {
      final x = i % 40;
      final y = i ~/ 40;
      if (x == 0 || y == 0 || x == 39 || y == 19) {
        continue;
      }
      expect(bytes[i * 4], closeTo(191, 1), reason: '($x, $y)');
    }
    for (final tile in surface.tiles.values) {
      pictures.cache.releasePicture(tile);
    }
  });
}
