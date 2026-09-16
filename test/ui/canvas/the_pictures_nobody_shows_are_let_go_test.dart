import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/placed_tile.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/pictured_tiles.dart';
import 'package:anicel/src/ui/canvas/tile_picture_budget.dart';

/// 🚨THE PICTURES NOBODY SHOWS ARE LET GO WHEN THEY ADD UP TO MORE THAN THE
/// DEVICE ALLOWS (render round, 2026-09-16): the never-shown first, then
/// the least recently shown — and never what a canvas showed in its latest
/// paint, however far over budget the rest is.
///
/// Pinned at the roll and the budget, not on a canvas: what the walk
/// decides is visible here to the byte, and the canvas's own stamping is
/// pinned where the canvas paints.
void main() {
  const oneImage = 4 * 4 * 4;

  ui.Image picture() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 4, 4),
      ui.Paint()..color = const ui.Color(0xFF3366CC),
    );
    final recorded = recorder.endRecording();
    final image = recorded.toImageSync(4, 4);
    recorded.dispose();
    return image;
  }

  PlacedTile tileAt(int x) => (
    coord: TileCoord(x: x, y: 0),
    tile: BitmapTile.blank(size: 4),
  );

  late BitmapTileImageCache cache;
  late PicturedTiles pictured;
  late TilePictureBudget budget;

  /// What the static count read before this test held anything: earlier
  /// tests' protected pictures are still on the books, and the budget is
  /// written relative to them.
  late int baseline;

  setUp(() {
    pictured = PicturedTiles();
    cache = BitmapTileImageCache(pictured: pictured);
    budget = TilePictureBudget(cache: cache, pictured: pictured);
    baseline = BitmapTileImageCache.liveImageBytes;
  });

  /// [placed]'s truth lands, filed under [scope] — nowhere by default.
  void land(PlacedTile placed, {Object? scope}) => cache.adoptDecoded(
    placed,
    picture(),
    staleScope: scope ?? BitmapTileImageCache.unfiled,
  );

  test('over budget, the never-shown go first, then the least recently '
      'shown — and the latest paint\'s stay', () {
    final never = tileAt(0);
    final old = tileAt(1);
    final recent = tileAt(2);
    final onScreen = tileAt(3);
    for (final placed in [onScreen, recent, old, never]) {
      land(placed);
    }
    budget.paintBegan('cel');
    budget.shown('cel', old.tile);
    budget.paintBegan('cel');
    budget.shown('cel', recent.tile);
    budget.paintBegan('cel');
    budget.shown('cel', onScreen.tile);
    expect(BitmapTileImageCache.liveImageBytes - baseline, 4 * oneImage);

    // Room for two of the four: two must go, and which two is the law.
    budget.byteBudget = baseline + 2 * oneImage;
    expect(budget.letGo(), 2);
    expect(
      cache.displayImageFor(never.tile),
      isNull,
      reason: 'a picture no paint ever showed goes first',
    );
    expect(
      cache.displayImageFor(old.tile),
      isNull,
      reason: 'then the least recently shown',
    );
    expect(cache.displayImageFor(recent.tile), isNotNull);
    expect(
      cache.displayImageFor(onScreen.tile),
      isNotNull,
      reason: 'the latest paint\'s tile is on screen',
    );
    expect(BitmapTileImageCache.liveImageBytes - baseline, 2 * oneImage);
  });

  test('what the latest paint showed is never let go, however far over '
      'budget the pictures are', () {
    final a = tileAt(0);
    final b = tileAt(1);
    land(a);
    land(b);
    budget.paintBegan('cel');
    budget.shown('cel', a.tile);
    budget.shown('cel', b.tile);
    budget.byteBudget = baseline;
    expect(budget.letGo(), 0);
    expect(cache.displayImageFor(a.tile), isNotNull);
    expect(cache.displayImageFor(b.tile), isNotNull);
  });

  test('an idle canvas keeps its visible pictures through recentPaints '
      'paints of another, and may lose them after', () {
    final idle = tileAt(0);
    land(idle);
    budget.paintBegan('idle-cel');
    budget.shown('idle-cel', idle.tile);
    for (var i = 0; i < TilePictureBudget.recentPaints - 1; i += 1) {
      budget.paintBegan('busy-cel');
    }
    budget.byteBudget = baseline;
    expect(budget.letGo(), 0, reason: 'its latest paint is still recent');
    budget.paintBegan('busy-cel');
    expect(budget.letGo(), 1, reason: 'and now it is not');
    expect(cache.displayImageFor(idle.tile), isNull);
  });

  test('a tile shown by an EARLIER paint of its own canvas is not current: '
      'the view moved off it', () {
    final left = tileAt(0);
    final right = tileAt(1);
    land(left);
    land(right);
    budget.paintBegan('cel');
    budget.shown('cel', left.tile);
    // The view pans: the next paint shows the other tile only.
    budget.paintBegan('cel');
    budget.shown('cel', right.tile);
    budget.byteBudget = baseline;
    expect(budget.letGo(), 1);
    expect(cache.displayImageFor(left.tile), isNull);
    expect(cache.displayImageFor(right.tile), isNotNull);
  });

  test('a picture the coordinate fallback filed is struck from the filing '
      'as it goes — the cache would refuse to let a filed one go', () {
    final filed = tileAt(0);
    land(filed, scope: 'cel');
    expect(cache.latestImageForCoord(filed.coord, scope: 'cel'), isNotNull);
    budget.byteBudget = baseline;
    expect(budget.letGo(), 1);
    expect(cache.displayImageFor(filed.tile), isNull);
    expect(cache.latestImageForCoord(filed.coord, scope: 'cel'), isNull);
  });

  test('a stand-in is on the roll like a truth, and goes the same way', () {
    final standIn = tileAt(0);
    cache.putProvisional(standIn, picture());
    expect(cache.hasProvisional(standIn.tile), isTrue);
    budget.byteBudget = baseline;
    expect(budget.letGo(), 1);
    expect(cache.hasProvisional(standIn.tile), isFalse);
  });

  test('under budget nothing goes, shown or not', () {
    final a = tileAt(0);
    land(a);
    budget.byteBudget = baseline + oneImage;
    expect(budget.letGo(), 0);
    expect(cache.displayImageFor(a.tile), isNotNull);
  });

  test('a tile joins the roll once, and is asked for at its latest '
      'coordinate', () {
    final placed = tileAt(0);
    land(placed);
    pictured.hold((coord: TileCoord(x: 7, y: 7), tile: placed.tile));
    expect(pictured.length, 1);
    expect(pictured.alive().single.coord, TileCoord(x: 7, y: 7));
  });
}
