import 'dart:ui' show Rect;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cel_photo_fixture.dart';
import '../helpers/cel_text_fixture.dart';

/// R9-rest (the text tool, 유저 2026-10-06: 「셀의 그림이랑 정확히 동일.
/// 복사/링크도 같이감」): a cel's texts live in the picture's own value, so
/// every surface DERIVED from one — a stroke's commit, an erase, a rebuild —
/// has to hand them on. A derivation that let them fall would make one
/// stroke delete every letter on the cel. A sheet's photos live there too
/// (I-97 — 「사진으로 남게(셀의 텍스트처럼)」), and are asked the same, and so
/// is where a file's picture lies (F-374-Q8).
void main() {
  final here = TileCoord(x: 0, y: 0);
  final there = TileCoord(x: 1, y: 0);
  final ink = tileOf({
    (1, 1): [9, 9, 9, 255],
  });
  final texts = [
    textOf(
      1,
      plate: {
        there: tileOf({
          (0, 0): [200, 0, 0, 255],
        }),
      },
    ),
    textOf(2, words: 'second'),
  ];
  BitmapSurface picture() => drawingOf({here: ink}).withTexts(texts);

  group('every surface made FROM a picture keeps its texts', () {
    test('tiles put', () {
      final next = picture().putTiles([(coord: there, tile: ink)]);

      expect(next.texts, texts);
      expect(next.tileAt(there), same(ink));
    });

    test('a pass that materialized its tiles — a commit, with a tile it '
        'emptied dropped', () {
      final next = picture().putMaterializedTiles([
        (coord: here, tile: BitmapTile.blank(size: celTextTestTileSize)),
        (coord: there, tile: ink),
      ]);

      expect(next.texts, texts);
      expect(next.tileAt(here), isNull, reason: 'fixture: the drop happened');
    });

    test('a copy-on-write pass that rebuilt some tiles', () {
      final next = picture().withRebuiltTiles({there: ink});

      expect(next.texts, texts);
    });

    test('a copy with another canvas', () {
      final next = picture().copyWith(
        canvasSize: const CanvasSize(width: 64, height: 64),
      );

      expect(next.texts, texts);
      expect(next.canvasSize.width, 64);
    });
  });

  group('the texts of a picture', () {
    test('a picture has none until it is given some', () {
      expect(drawingOf({here: ink}).texts, isEmpty);
    });

    test('given others, it is the same drawing — the very tile map — under '
        'them', () {
      final drawing = drawingOf({here: ink});

      final withTexts = drawing.withTexts(texts);

      expect(withTexts.texts, texts);
      expect(identical(withTexts.tiles, drawing.tiles), isTrue);
      expect(drawing.texts, isEmpty, reason: 'the source is not written');
    });

    test('given the list it already holds, it is itself', () {
      final withTexts = picture();

      expect(identical(withTexts.withTexts(withTexts.texts), withTexts), isTrue);
    });

    test('cannot be written through the surface', () {
      expect(() => picture().texts.add(textOf(3)), throwsUnsupportedError);
    });

    test('taken off again leaves the drawing', () {
      final bare = picture().withTexts(const []);

      expect(bare.texts, isEmpty);
      expect(bare.tileAt(here), same(ink));
    });
  });

  group('a plate answers to the surface it is laid on', () {
    final wrongSize = textOf(
      5,
      plate: {here: BitmapTile.blank(size: celTextTestTileSize * 2)},
    );
    final offThePasteboard = textOf(
      5,
      plate: {TileCoord(x: 99, y: 0): BitmapTile.blank(size: celTextTestTileSize)},
    );

    test('a plate of another tile size is refused — given to a surface and '
        'built into one', () {
      expect(() => drawingOf(const {}).withTexts([wrongSize]), throwsArgumentError);
      expect(
        () => BitmapSurface(
          canvasSize: celTextTestCanvas,
          tileSize: celTextTestTileSize,
          texts: [wrongSize],
        ),
        throwsArgumentError,
      );
    });

    test('a plate with a tile off the pasteboard is refused', () {
      expect(
        () => drawingOf(const {}).withTexts([offThePasteboard]),
        throwsArgumentError,
      );
      expect(
        () => BitmapSurface(
          canvasSize: celTextTestCanvas,
          tileSize: celTextTestTileSize,
          texts: [offThePasteboard],
        ),
        throwsArgumentError,
      );
    });
  });

  group('what a picture holds', () {
    test('nothing: no tile and no text', () {
      expect(drawingOf(const {}).holdsNothing, isTrue);
      expect(drawingOf({here: ink}).holdsNothing, isFalse);
    });

    test('a text alone is something — a cel that is only letters is a '
        'picture', () {
      expect(drawingOf(const {}).withTexts([textOf(1)]).holdsNothing, isFalse);
    });

    test('it keeps the drawing\'s tiles and every plate\'s', () {
      expect(drawingOf({here: ink}).keptTileCount, 1);
      expect(picture().keptTileCount, 2);
    });
  });

  group('two pictures', () {
    test('with the same drawing and the same texts are equal', () {
      expect(picture(), picture());
      expect(picture().hashCode, picture().hashCode);
    });

    test('with the same drawing and other texts are not', () {
      expect(picture(), isNot(drawingOf({here: ink})));
      expect(
        picture(),
        isNot(drawingOf({here: ink}).withTexts(texts.reversed.toList())),
        reason: 'the order is which text is on top',
      );
    });

    test('a picture reads back from JSON with its texts', () {
      final read = BitmapSurface.fromJson(throughJson(picture().toJson()));

      expect(read, picture());
      expect(read.texts.map((text) => text.id), [1, 2]);
    });

    test('a picture with no text writes no texts — the JSON it wrote before '
        'texts existed', () {
      expect(drawingOf({here: ink}).toJson().containsKey('texts'), isFalse);
    });
  });

  group('a sheet\'s photos (I-97)', () {
    final photos = [
      photoOf(1),
      photoOf(2, path: 'C:/pool/other.jpg', center: CanvasPoint(x: 3, y: 4)),
    ];
    BitmapSurface sheet() => picture().withPhotos(photos);

    test('ride every surface made from the picture', () {
      final derived = {
        'tiles put': sheet().putTiles([(coord: there, tile: ink)]),
        'a commit\'s materialized tiles': sheet().putMaterializedTiles([
          (coord: here, tile: BitmapTile.blank(size: celTextTestTileSize)),
        ]),
        'a copy-on-write rebuild': sheet().withRebuiltTiles({there: ink}),
        'a copy with another canvas': sheet().copyWith(
          canvasSize: const CanvasSize(width: 64, height: 64),
        ),
        'other texts': sheet().withTexts(const []),
      };

      for (final MapEntry(key: road, value: next) in derived.entries) {
        expect(next.photos, photos, reason: road);
      }
    });

    test('given others, it is the same drawing — the very tile map — and '
        'the same texts', () {
      final drawn = picture();

      final withPhotos = drawn.withPhotos(photos);

      expect(withPhotos.photos, photos);
      expect(identical(withPhotos.tiles, drawn.tiles), isTrue);
      expect(withPhotos.texts, same(drawn.texts));
      expect(drawn.photos, isEmpty, reason: 'the source is not written');
    });

    test('given the list it already holds, it is itself', () {
      final withPhotos = sheet();

      expect(
        identical(withPhotos.withPhotos(withPhotos.photos), withPhotos),
        isTrue,
      );
    });

    test('cannot be written through the surface', () {
      expect(() => sheet().photos.add(photoOf(3)), throwsUnsupportedError);
    });

    test('a photo alone is something — a sheet that holds only a photo '
        'holds a picture', () {
      final onlyPhoto = drawingOf(const {}).withPhotos([photoOf(1)]);

      expect(onlyPhoto.holdsNothing, isFalse);
    });

    test('two pictures with other photos, or the same in another order, are '
        'not equal', () {
      expect(sheet(), picture().withPhotos([...photos]));
      expect(sheet().hashCode, picture().withPhotos([...photos]).hashCode);
      expect(sheet(), isNot(picture()));
      expect(
        sheet(),
        isNot(picture().withPhotos(photos.reversed.toList())),
        reason: 'the order is which photo is on top',
      );
    });

    test('a picture reads back from JSON with its photos, and one with none '
        'writes none', () {
      final read = BitmapSurface.fromJson(throughJson(sheet().toJson()));

      expect(read, sheet());
      expect(read.photos.map((photo) => photo.id), [1, 2]);
      expect(picture().toJson().containsKey('photos'), isFalse);
    });
  });

  group('where a file\'s picture lies (F-374-Q8)', () {
    // Twelve pixels past the wall on the left: on the test grid the
    // pasteboard's first tile is -4, so the file's reaches two beyond it.
    final laid = DirtyRegion(
      left: -44,
      top: 0,
      rightExclusive: 4,
      bottomExclusive: 8,
    );
    final beyond = TileCoord(x: -6, y: 0);
    BitmapSurface laidPicture() => BitmapSurface(
      canvasSize: celTextTestCanvas,
      tileSize: celTextTestTileSize,
      tiles: {beyond: ink, here: ink},
      laidBounds: laid,
    );

    test('🚨keeps the tiles past the wall it covers — and no other past the '
        'wall', () {
      expect(laidPicture().tileAt(beyond), same(ink));
      expect(
        () => drawingOf({beyond: ink}),
        throwsArgumentError,
        reason: 'no file laid there: the wall',
      );
      expect(
        () => laidPicture().putTiles([
          (coord: TileCoord(x: -6, y: 1), tile: ink),
        ]),
        throwsArgumentError,
        reason: 'past the wall, beside the file',
      );
    });

    test('keeps its pixels in the pasteboard grown to take it in', () {
      expect(laidPicture().storableRect, const Rect.fromLTRB(-44, -32, 64, 64));
      expect(
        drawingOf({here: ink}).storableRect,
        celTextTestCanvas.pasteboardAt(PasteboardReach.whole).rect,
      );
    });

    test('rides every surface made from the picture', () {
      final derived = {
        'tiles put': laidPicture().putTiles([(coord: there, tile: ink)]),
        'a commit\'s materialized tiles': laidPicture().putMaterializedTiles([
          (coord: here, tile: BitmapTile.blank(size: celTextTestTileSize)),
        ]),
        'a copy-on-write rebuild': laidPicture().withRebuiltTiles({there: ink}),
        'a copy with another canvas': laidPicture().copyWith(
          canvasSize: const CanvasSize(width: 64, height: 64),
        ),
        'other texts': laidPicture().withTexts(texts),
        'other photos': laidPicture().withPhotos([photoOf(1)]),
      };

      for (final MapEntry(key: road, value: next) in derived.entries) {
        expect(next.laidBounds, laid, reason: road);
      }
    });

    test('two pictures with a file laid at another place, or none, are not '
        'equal', () {
      final elsewhere = DirtyRegion(
        left: -44,
        top: 0,
        rightExclusive: 5,
        bottomExclusive: 8,
      );

      expect(laidPicture(), laidPicture());
      expect(laidPicture().hashCode, laidPicture().hashCode);
      expect(
        laidPicture(),
        isNot(laidPicture().copyWith(laidBounds: elsewhere)),
      );
      expect(
        drawingOf({here: ink}),
        isNot(drawingOf({here: ink}).copyWith(laidBounds: laid)),
      );
    });

    test('a picture reads back from JSON where its file lies, and one with '
        'none writes none', () {
      final read = BitmapSurface.fromJson(throughJson(laidPicture().toJson()));

      expect(read, laidPicture());
      expect(read.laidBounds, laid);
      expect(picture().toJson().containsKey('laid'), isFalse);
    });
  });
}
