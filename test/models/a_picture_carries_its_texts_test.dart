import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cel_text_fixture.dart';

/// R9-rest (the text tool, 유저 2026-10-06: 「셀의 그림이랑 정확히 동일.
/// 복사/링크도 같이감」): a cel's texts live in the picture's own value, so
/// every surface DERIVED from one — a stroke's commit, an erase, a rebuild —
/// has to hand them on. A derivation that let them fall would make one
/// stroke delete every letter on the cel.
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
}
