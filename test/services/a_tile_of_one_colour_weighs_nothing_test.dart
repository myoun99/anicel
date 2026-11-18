import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/undo_surface_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cel_text_fixture.dart';

/// A tile of one colour holds no block of its own (`BitmapTile.ownBytes`),
/// and whoever weighs tiles asks the tile — the hot cels, an undo entry, a
/// picture's own sum (card `a-file-keeps-all-clear-tiles-in-its-cels`: a
/// cut whose cels kept 27,912 emptied tiles weighed 4.2 GiB hot against a
/// ceiling of 4.3, 1.7 GiB of it a white with no alpha).
///
/// The emptied tiles stay where they are: the undo of the verb that emptied
/// them walks a cel's tiles place by place
/// (`BitmapSurface.putMaterializedTiles`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final a = TileCoord(x: 0, y: 0);
  final b = TileCoord(x: 1, y: 0);
  final c = TileCoord(x: 2, y: 0);
  final tileBytes = BitmapTile.bytesFor(celTextTestTileSize);

  /// What a destructive verb leaves of a picture's paper: a white with no
  /// alpha, over the whole tile.
  BitmapTile emptied() => tileFilledWith(const [255, 255, 255, 0]);

  /// One pixel of ink on nothing: a tile of two colours.
  BitmapTile inked(int shade) => tileOf({
    (0, 0): [shade, shade, shade, 255],
  });

  group('a picture', () {
    test('🚨weighs its tiles of two colours alone — the emptied ones stay, '
        'each in its place, and weigh nothing', () {
      final picture = drawingOf({a: emptied(), b: inked(1), c: emptied()});

      expect(picture.tiles.keys, [a, b, c]);
      expect(picture.keptTileCount, 3);
      expect(picture.keptTileBytes, tileBytes);
      expect(picture.bytesNotSharedWith(null), tileBytes);
    });

    test('a tile of one OPAQUE colour weighs nothing either: what is asked '
        'is its colour, not its ink', () {
      final picture = drawingOf({
        a: tileFilledWith(const [255, 255, 255, 255]),
        b: inked(1),
      });

      expect(picture.tiles[a]!.hasInk, isTrue, reason: 'fixture');
      expect(picture.keptTileBytes, tileBytes);
    });

    test('a text\'s plate is weighed as the drawing is', () {
      final picture = drawingOf({a: inked(1)}).withTexts([
        textOf(1, plate: {a: emptied(), b: inked(2)}),
      ]);

      expect(picture.keptTileCount, 3);
      expect(picture.keptTileBytes, 2 * tileBytes);
      expect(picture.bytesNotSharedWith(null), 2 * tileBytes);
    });
  });

  test('🚨the hot cels weigh what their tiles hold', () {
    final store = BrushFrameStore();

    store.storeBakedSurface(
      celTextTestKey,
      drawingOf({a: emptied(), b: inked(1), c: emptied()}),
    );

    expect(store.hotBakedBytes, tileBytes);
  });

  test('🚨an undo entry weighs nothing for the emptied tiles it alone '
      'holds', () {
    final ink = inked(1);
    final pair = UndoSurfacePair(
      key: celTextTestKey,
      before: drawingOf({a: ink, b: emptied()}),
      after: drawingOf({a: ink, b: inked(2), c: inked(3)}),
    );

    expect(pair.residentBytes(undone: false), 0);
    expect(pair.residentBytes(undone: true), 2 * tileBytes);
  });
}
