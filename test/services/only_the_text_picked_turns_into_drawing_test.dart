import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/cel_text_laying.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cel_text_fixture.dart';

/// R9-rest, 「그림으로 굳히기」 (유저 2026-10-06: 「텍스트 그림으로 굳히기
/// 아이디어 좋네」): a text turned into DRAWING is no text of its cel any
/// more — its ink is the drawing's — and it is THE TEXT PICKED, AND NO
/// OTHER (유저 2026-10-07, `R9-rest-Q5`: 「고른 텍스트만 굳힌다」).
///
/// So the cel SHOWS, to the byte, what it showed — except where a text
/// under the one picked shared a pixel with it: that text stays a text, and
/// is over the ink from then on.
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

  /// The pixels of tile [a] that [picture] shows otherwise than [was].
  Set<(int, int)> shownOtherwise(BitmapSurface picture, BitmapSurface was) {
    final now = shown(picture)[a]!;
    final then = shown(was)[a]!;
    return {
      for (var at = 0; at < now.length; at += 4)
        if (now.sublist(at, at + 4).join(',') !=
            then.sublist(at, at + 4).join(','))
          ((at ~/ 4) % celTextTestTileSize, (at ~/ 4) ~/ celTextTestTileSize),
    };
  }

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
  // The two meet at (1, 0), half see-through both: there, which of them is
  // over the other shows.
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

  // 🗣️유저 2026-10-07 (`R9-rest-Q5`): 「고른 텍스트만 굳힌다」.
  group('beside the other texts of its cel, the one picked goes ALONE', () {
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

    test('🚨a text UNDER it that it covers STAYS A TEXT: the one picked is '
        'laid on the drawing as if it were alone on the cel, and the other '
        'is OVER its ink from then on — the picture changes where the two '
        'share a pixel, and nowhere else', () {
      final under = textOf(1, plate: {a: lower});
      final picked = textOf(2, plate: {a: upper});
      final drawing = drawingOf({a: ground});
      final before = drawing.withTexts([under, picked]);

      final after = celSurfaceWithTextAsDrawing(before, 2);

      expect(after.texts.single, same(under));
      // The drawing: what the cel would show carrying the picked one alone.
      expect(
        {
          for (final entry in after.tiles.entries)
            entry.key: entry.value.pixels,
        },
        shown(drawing.withTexts([picked])),
      );
      expect(pixelOf(after, a, 3, 0), [0, 0, 200, 255], reason: 'its ink');
      expect(pixelOf(after, a, 0, 0), [10, 20, 30, 255], reason: 'no other');
      // 유저 took this answer with its cost said: where they meet, the one
      // that was under is over.
      expect(shownOtherwise(after, before), {(1, 0)});
    });

    test('a text under it that shares NO pixel of ink with it: the cel '
        'shows what it showed — on the same tile, a pixel away', () {
      final beside = textOf(1, plate: {a: apart});
      final before = drawingOf({a: ground}).withTexts([
        beside,
        textOf(2, plate: {a: upper}),
      ]);

      final after = celSurfaceWithTextAsDrawing(before, 2);

      expect(after.texts.single, same(beside));
      expect(shown(after), shown(before));
    });

    test('however many it covers, down the pile, every one stays', () {
      // 1 under 2 under 4; 4 meets 2 at (3, 3) and 2 meets 1 at (0, 0).
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
      final before = drawingOf({a: ground}).withTexts([
        textOf(1, plate: {a: bottom}),
        textOf(2, plate: {a: middle}),
        textOf(3, plate: {a: apart}),
        textOf(4, plate: {a: top}),
      ]);

      final after = celSurfaceWithTextAsDrawing(before, 4);

      expect(idsOf(after), [1, 2, 3]);
      expect(shownOtherwise(after, before), {(3, 3)});
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
