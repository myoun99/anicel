import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/cel_text_laying.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cel_text_fixture.dart';

/// R9-rest, 「그림으로 굳히기」 (유저 2026-10-06: 「텍스트 그림으로 굳히기
/// 아이디어 좋네」): a text turned into DRAWING is no text of its cel any
/// more, and the cel SHOWS, to the byte, what it showed.
///
/// 🚨THE ORACLE IS WHAT THE CEL SHOWED BEFORE (`celSurfaceWithTextsLaid` of
/// the picture as it was), every tile of it — never a second spelling of
/// the laying written out here.
void main() {
  final a = TileCoord(x: 0, y: 0);
  final b = TileCoord(x: 1, y: 0);

  /// What [picture] SHOWS: every tile of it with its texts laid, as bytes.
  Map<TileCoord, List<int>> shown(BitmapSurface picture) => {
    for (final entry in celSurfaceWithTextsLaid(picture).tiles.entries)
      entry.key: entry.value.pixels,
  };

  List<int> idsOf(BitmapSurface picture) => [
    for (final text in picture.texts) text.id,
  ];

  // Ink of every kind a blend treats differently, under and over.
  final ground = tileOf({
    (0, 0): [10, 20, 30, 255],
    (1, 0): [10, 20, 30, 128],
    (2, 0): [250, 240, 230, 77],
    (5, 5): [1, 2, 3, 200],
  });
  // ⚠️NO RED in either of the two that meet at (1, 0): a share of ink is a
  // share of ALPHA, and read off any other byte it would not be found here.
  final lower = tileOf({
    (0, 0): [0, 200, 0, 255],
    (1, 0): [0, 200, 0, 128],
    (2, 0): [0, 200, 0, 64],
  });
  final upper = tileOf({
    (1, 0): [0, 0, 200, 128],
    (3, 0): [0, 0, 200, 255],
  });
  // On the same tile as both, and a pixel away from either.
  final apart = tileOf({
    (6, 6): [200, 0, 0, 255],
    (2, 1): [200, 0, 0, 90],
  });

  group('a text turned into drawing', () {
    test('🚨shows as it did, over ink of every kind — and is no text of the '
        'cel any more', () {
      final before = drawingOf({a: ground}).withTexts([
        textOf(1, plate: {a: lower}),
      ]);

      final after = celSurfaceWithTextAsDrawing(before, 1);

      expect(after.texts, isEmpty);
      expect(shown(after), shown(before));
      // Liveness: its ink IS the drawing's now.
      expect(pixelOf(after, a, 0, 0), [0, 200, 0, 255]);
      expect(after.tileAt(a), isNot(same(before.tileAt(a))));
      expect(pixelOf(before, a, 0, 0), [10, 20, 30, 255], reason: '⛔fixture');
    });

    test('the drawing takes THE VERY TILE that was on screen: no pixel is '
        'laid a second time, and the picture made of it stays in use', () {
      final before = drawingOf({a: ground}).withTexts([
        textOf(1, plate: {a: lower}),
      ]);
      final onScreen = celSurfaceWithTextsLaid(before).tileAt(a);

      final after = celSurfaceWithTextAsDrawing(before, 1);

      expect(after.tileAt(a), same(onScreen));
    });

    test('over bare paper it leaves a tile where there was none', () {
      final before = drawingOf(const {}).withTexts([
        textOf(1, plate: {a: lower, b: upper}),
      ]);

      final after = celSurfaceWithTextAsDrawing(before, 1);

      expect(after.texts, isEmpty);
      expect(after.tiles.keys.toSet(), {a, b});
      expect(shown(after), shown(before));
    });

    test('no text of that id: the picture itself', () {
      final before = drawingOf({a: ground}).withTexts([
        textOf(1, plate: {a: lower}),
      ]);

      expect(celSurfaceWithTextAsDrawing(before, 2), same(before));
      expect(
        celSurfaceWithTextAsDrawing(drawingOf({a: ground}), 1).texts,
        isEmpty,
      );
    });

    test('the picture it was turned from is as it was', () {
      final text = textOf(1, plate: {a: lower});
      final before = drawingOf({a: ground}).withTexts([text]);
      final drawn = before.tileAt(a);

      celSurfaceWithTextAsDrawing(before, 1);

      expect(before.texts.single, same(text));
      expect(before.tileAt(a), same(drawn));
    });
  });

  group('beside the other texts of its cel', () {
    test('a text OVER it stays a text — and shows over the drawing as it '
        'showed over the text', () {
      final over = textOf(2, plate: {a: upper});
      final before = drawingOf({a: ground}).withTexts([
        textOf(1, plate: {a: lower}),
        over,
      ]);

      final after = celSurfaceWithTextAsDrawing(before, 1);

      expect(after.texts.single, same(over));
      expect(shown(after), shown(before));
      expect(pixelOf(after, a, 0, 0), [0, 200, 0, 255], reason: 'liveness');
    });

    test('🚨a text UNDER it that it covers goes with it: turned alone, the '
        'one named would be under that one from then on', () {
      final under = textOf(1, plate: {a: lower});
      final named = textOf(2, plate: {a: upper});
      final drawing = drawingOf({a: ground});
      final before = drawing.withTexts([under, named]);

      final after = celSurfaceWithTextAsDrawing(before, 2);

      expect(after.texts, isEmpty);
      expect(shown(after), shown(before));
      // ⛔CONTROL: what the named one turned ALONE would show — its ink in
      // the drawing, and the text it covered over it — is another picture.
      final alone = celSurfaceWithTextsLaid(
        drawing.withTexts([named]),
      ).withTexts([under]);
      expect(
        shown(alone),
        isNot(shown(before)),
        reason: '⛔fixture: where the two meet, their order shows',
      );
    });

    test('a text under it that shares NO pixel of ink stays a text — on the '
        'same tile, a pixel away', () {
      final beside = textOf(1, plate: {a: apart});
      final before = drawingOf({a: ground}).withTexts([
        beside,
        textOf(2, plate: {a: upper}),
      ]);

      final after = celSurfaceWithTextAsDrawing(before, 2);

      expect(after.texts.single, same(beside));
      expect(shown(after), shown(before));
    });

    test('a colour behind alpha 0 is no ink: the text under it stays', () {
      // The stamp lays nothing of such a pixel, so nothing there can come
      // out in another order.
      final ghost = tileOf({
        (0, 0): [99, 99, 99, 0],
        (7, 7): [99, 99, 99, 255],
      });
      final dot = tileOf({
        (0, 0): [50, 60, 70, 255],
      });
      final before = drawingOf(const {}).withTexts([
        textOf(1, plate: {a: dot}),
        textOf(2, plate: {a: ghost}),
      ]);

      final after = celSurfaceWithTextAsDrawing(before, 2);

      expect(idsOf(after), [1]);
      expect(shown(after), shown(before));
    });

    test('texts on different tiles share nothing', () {
      final before = drawingOf(const {}).withTexts([
        textOf(1, plate: {a: lower}),
        textOf(2, plate: {b: lower}),
      ]);

      final after = celSurfaceWithTextAsDrawing(before, 2);

      expect(idsOf(after), [1]);
      expect(shown(after), shown(before));
    });

    test('🚨the reach runs DOWN THE PILE: a text under one that goes with it '
        'goes too, though the one named never touches it', () {
      // 1 under 2 under 4; 4 meets 2 at (3, 3), 2 meets 1 at (0, 0), and 4
      // has nothing at (0, 0). 3 lies between them and meets none.
      final bottom = tileOf({
        (0, 0): [0, 200, 0, 128],
      });
      final middle = tileOf({
        (0, 0): [0, 0, 200, 128],
        (3, 3): [0, 0, 200, 128],
      });
      final top = tileOf({
        (3, 3): [200, 0, 0, 128],
      });
      final between = textOf(3, plate: {a: apart});
      final before = drawingOf({a: ground}).withTexts([
        textOf(1, plate: {a: bottom}),
        textOf(2, plate: {a: middle}),
        between,
        textOf(4, plate: {a: top}),
      ]);

      final after = celSurfaceWithTextAsDrawing(before, 4);

      expect(after.texts.single, same(between));
      expect(shown(after), shown(before));
    });

    test('a text over it that covers one under it takes nothing with it: '
        'only what is turned reaches down', () {
      // 3 covers 1 at (0, 0); 2 — the one named — meets neither.
      final dot = tileOf({
        (0, 0): [0, 200, 0, 128],
      });
      final cover = tileOf({
        (0, 0): [0, 0, 200, 128],
      });
      final before = drawingOf({a: ground}).withTexts([
        textOf(1, plate: {a: dot}),
        textOf(2, plate: {a: apart}),
        textOf(3, plate: {a: cover}),
      ]);

      final after = celSurfaceWithTextAsDrawing(before, 2);

      expect(idsOf(after), [1, 3]);
      expect(shown(after), shown(before));
    });

    test('the texts left keep their order, and are the very texts', () {
      final first = textOf(1, plate: {a: apart});
      final last = textOf(5, plate: {b: lower});
      final before = drawingOf(const {}).withTexts([
        first,
        textOf(3, plate: {a: upper}),
        last,
      ]);

      final left = celSurfaceWithTextAsDrawing(before, 3).texts;

      expect(left, hasLength(2));
      expect(left.first, same(first));
      expect(left.last, same(last));
    });
  });
}
