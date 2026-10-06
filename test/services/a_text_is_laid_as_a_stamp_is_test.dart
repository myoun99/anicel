import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart'
    show bitmapSurfaceRegionPixels;
import 'package:anicel/src/services/cel_text_laying.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cel_text_fixture.dart';

/// R9-rest (the text tool, 유저 2026-10-06: 「셀의 그림이랑 정확히 동일」): what
/// a cel SHOWS is its drawing with its texts laid over it — and 「laid」 is
/// not a rule of its own. It is the landing a picture stamped onto the cel
/// at full strength takes, so a text and the same pixels DRAWN there are
/// one set of bytes.
///
/// 🚨THE ORACLE IS THE REAL COMMIT (`compositeStrokePixelsOntoBitmapSurface`
/// — the road a stamp and a normal stroke land by), never a formula written
/// out again here: a second spelling of the blend would pass exactly when
/// it copies the first one's mistake.
void main() {
  final a = TileCoord(x: 0, y: 0);
  final b = TileCoord(x: 1, y: 0);
  final c = TileCoord(x: 0, y: 1);
  const size = celTextTestTileSize;

  /// What stamping [plate] onto [drawing] as a picture commits.
  BitmapSurface stamped(BitmapSurface drawing, Map<TileCoord, BitmapTile> plate) {
    var result = drawing;
    for (final entry in plate.entries) {
      final bounds = DirtyRegion(
        left: entry.key.x * size,
        top: entry.key.y * size,
        rightExclusive: (entry.key.x + 1) * size,
        bottomExclusive: (entry.key.y + 1) * size,
      );
      result = compositeStrokePixelsOntoBitmapSurface(
        surface: result,
        strokePixels: Uint8List.fromList(entry.value.pixels),
        bounds: bounds,
      ).surface;
    }
    return result;
  }

  /// Every pixel of [surface] over the tiles [coords] cover, as bytes.
  List<int> pixelsOver(BitmapSurface surface, Iterable<TileCoord> coords) => [
    for (final coord in coords)
      ...bitmapSurfaceRegionPixels(
        surface,
        DirtyRegion(
          left: coord.x * size,
          top: coord.y * size,
          rightExclusive: (coord.x + 1) * size,
          bottomExclusive: (coord.y + 1) * size,
        ),
      ),
  ];

  // Ink of every kind a blend treats differently: opaque, half, a hair,
  // none — over a destination of every kind too.
  final drawingTile = tileOf({
    (0, 0): [10, 20, 30, 255],
    (1, 0): [10, 20, 30, 128],
    (2, 0): [10, 20, 30, 1],
    (3, 0): [250, 240, 230, 255],
    (4, 0): [250, 240, 230, 77],
    (0, 1): [0, 0, 0, 255],
    (1, 1): [255, 255, 255, 200],
  });
  final plateTile = tileOf({
    (0, 0): [200, 100, 50, 255],
    (1, 0): [200, 100, 50, 128],
    (2, 0): [200, 100, 50, 255],
    (3, 0): [200, 100, 50, 64],
    (4, 0): [200, 100, 50, 191],
    (5, 0): [200, 100, 50, 255],
    (6, 0): [200, 100, 50, 3],
    (0, 1): [7, 8, 9, 1],
    (1, 1): [7, 8, 9, 254],
    (2, 1): [7, 8, 9, 127],
  });

  group('a text laid over a drawing is that plate stamped on it', () {
    test('over ink — opaque, half and hair-thin, under letters of each', () {
      final drawing = drawingOf({a: drawingTile});
      final plate = {a: plateTile};

      final laid = celSurfaceWithTextsLaid(
        drawing.withTexts([textOf(1, plate: plate)]),
      );

      expect(pixelsOver(laid, [a]), pixelsOver(stamped(drawing, plate), [a]));
      // Liveness: the plate DID land, and the drawing still shows through
      // the letters that are not opaque.
      expect(pixelOf(laid, a, 0, 0), [200, 100, 50, 255]);
      expect(pixelOf(laid, a, 5, 0), [200, 100, 50, 255]);
      expect(pixelOf(laid, a, 1, 0), isNot([10, 20, 30, 128]));
      expect(pixelOf(laid, a, 1, 0), isNot([200, 100, 50, 128]));
    });

    test('over nothing — a coordinate the drawing has no tile at', () {
      final drawing = drawingOf(const {});
      final plate = {a: plateTile};

      final laid = celSurfaceWithTextsLaid(
        drawing.withTexts([textOf(1, plate: plate)]),
      );

      expect(pixelsOver(laid, [a]), pixelsOver(stamped(drawing, plate), [a]));
      expect(pixelOf(laid, a, 1, 0), [200, 100, 50, 128]);
    });

    test('a plate holding colour behind alpha 0 lays as the stamp does — '
        'nothing there, not that colour', () {
      final drawing = drawingOf(const {});
      final ghost = tileOf({
        (0, 0): [200, 100, 50, 255],
        (1, 0): [99, 99, 99, 0],
      });

      final laid = celSurfaceWithTextsLaid(
        drawing.withTexts([
          textOf(1, plate: {a: ghost}),
        ]),
      );

      expect(
        pixelsOver(laid, [a]),
        pixelsOver(stamped(drawing, {a: ghost}), [a]),
      );
      expect(pixelOf(laid, a, 1, 0), [0, 0, 0, 0]);
    });

    test('two texts land in their order — the later one on top, over what '
        'the earlier one made', () {
      final drawing = drawingOf({a: drawingTile});
      final upper = tileOf({
        (0, 0): [1, 2, 3, 128],
        (1, 0): [1, 2, 3, 255],
        (2, 1): [1, 2, 3, 99],
      });

      final laid = celSurfaceWithTextsLaid(
        drawing.withTexts([
          textOf(1, plate: {a: plateTile}),
          textOf(2, plate: {a: upper}),
        ]),
      );
      final swapped = celSurfaceWithTextsLaid(
        drawing.withTexts([
          textOf(2, plate: {a: upper}),
          textOf(1, plate: {a: plateTile}),
        ]),
      );

      expect(
        pixelsOver(laid, [a]),
        pixelsOver(stamped(stamped(drawing, {a: plateTile}), {a: upper}), [a]),
      );
      expect(
        pixelsOver(swapped, [a]),
        pixelsOver(stamped(stamped(drawing, {a: upper}), {a: plateTile}), [a]),
      );
      expect(
        pixelsOver(laid, [a]),
        isNot(pixelsOver(swapped, [a])),
        reason: 'fixture: the order shows',
      );
    });

    test('a plate across several tiles lands on each — drawn or not', () {
      final drawing = drawingOf({a: drawingTile, c: drawingTile});
      final plate = {a: plateTile, b: plateTile};

      final laid = celSurfaceWithTextsLaid(
        drawing.withTexts([textOf(1, plate: plate)]),
      );

      expect(
        pixelsOver(laid, [a, b, c]),
        pixelsOver(stamped(drawing, plate), [a, b, c]),
      );
      expect(laid.tiles.keys.toSet(), {a, b, c});
    });
  });

  group('what the laying leaves alone', () {
    test('a cel with no text is not touched at all — the surface itself', () {
      final drawing = drawingOf({a: drawingTile});

      expect(identical(celSurfaceWithTextsLaid(drawing), drawing), isTrue);
    });

    test('the laid surface carries no texts — laid again it is itself', () {
      final laid = celSurfaceWithTextsLaid(
        drawingOf({a: drawingTile}).withTexts([
          textOf(1, plate: {a: plateTile}),
        ]),
      );

      expect(laid.texts, isEmpty);
      expect(identical(celSurfaceWithTextsLaid(laid), laid), isTrue);
    });

    test('a coordinate no text reaches keeps the drawing\'s own tile', () {
      final drawing = drawingOf({a: drawingTile, c: drawingTile});

      final laid = celSurfaceWithTextsLaid(
        drawing.withTexts([
          textOf(1, plate: {a: plateTile}),
        ]),
      );

      expect(laid.tileAt(c), same(drawing.tileAt(c)));
      expect(laid.tileAt(a), isNot(same(drawing.tileAt(a))));
    });

    test('a plate with no ink over a drawn coordinate changes nothing there '
        '— the drawing\'s own tile', () {
      final drawing = drawingOf({a: drawingTile});

      final laid = celSurfaceWithTextsLaid(
        drawing.withTexts([
          textOf(1, plate: {a: BitmapTile.blank(size: size)}),
        ]),
      );

      expect(laid.tileAt(a), same(drawing.tileAt(a)));
    });

    test('a plate with no ink over an empty coordinate makes no tile', () {
      final laid = celSurfaceWithTextsLaid(
        drawingOf(const {}).withTexts([
          textOf(1, plate: {a: BitmapTile.blank(size: size)}),
        ]),
      );

      expect(laid.tiles, isEmpty);
    });

    test('a clean plate over nothing is the plate itself — a text over bare '
        'paper keeps no second copy of its pixels', () {
      final laid = celSurfaceWithTextsLaid(
        drawingOf(const {}).withTexts([
          textOf(1, plate: {a: plateTile}),
        ]),
      );

      expect(laid.tileAt(a), same(plateTile));
    });

    test('the source picture is as it was', () {
      final source = drawingOf({a: drawingTile}).withTexts([
        textOf(1, plate: {a: plateTile}),
      ]);
      final before = List<int>.from(source.tileAt(a)!.pixels);

      celSurfaceWithTextsLaid(source);

      expect(source.tileAt(a)!.pixels, before);
      expect(source.texts, hasLength(1));
    });
  });

  group('the laying is remembered, tile by tile', () {
    test('the same picture laid twice is the same surface', () {
      final picture = drawingOf({a: drawingTile}).withTexts([
        textOf(1, plate: {a: plateTile}),
      ]);

      expect(
        identical(
          celSurfaceWithTextsLaid(picture),
          celSurfaceWithTextsLaid(picture),
        ),
        isTrue,
      );
    });

    test('🚨a stroke elsewhere on the cel lays nothing again: the tiles it '
        'did not touch come back as the very objects they were', () {
      final texts = [
        textOf(1, plate: {a: plateTile, b: plateTile}),
      ];
      final before = drawingOf({a: drawingTile}).withTexts(texts);
      final laidBefore = celSurfaceWithTextsLaid(before);

      // A commit: one new tile, at a coordinate under no text, and every
      // other tile the object it was.
      final after = before.putTiles([(coord: c, tile: drawingTile)]);
      final laidAfter = celSurfaceWithTextsLaid(after);

      expect(identical(laidAfter, laidBefore), isFalse, reason: 'fixture');
      expect(laidAfter.tileAt(a), same(laidBefore.tileAt(a)));
      expect(laidAfter.tileAt(b), same(laidBefore.tileAt(b)));
    });

    test('a stroke UNDER a text lays that one tile again — and only it', () {
      final texts = [
        textOf(1, plate: {a: plateTile, b: plateTile}),
      ];
      final before = drawingOf({
        a: drawingTile,
        b: drawingTile,
      }).withTexts(texts);
      final laidBefore = celSurfaceWithTextsLaid(before);

      final redrawn = tileOf({
        (0, 0): [1, 1, 1, 255],
      });
      final after = before.putTiles([(coord: a, tile: redrawn)]);
      final laidAfter = celSurfaceWithTextsLaid(after);

      expect(laidAfter.tileAt(a), isNot(same(laidBefore.tileAt(a))));
      expect(laidAfter.tileAt(b), same(laidBefore.tileAt(b)));
      expect(
        pixelsOver(laidAfter, [a]),
        pixelsOver(stamped(drawingOf({a: redrawn}), {a: plateTile}), [a]),
      );
    });

    test('one drawing tile under two texts in turn — a copied cel beside '
        'its source — keeps both answers', () {
      final other = tileOf({
        (3, 3): [0, 255, 0, 255],
      });
      CelText text(BitmapTile plate) => textOf(1, plate: {a: plate});
      final first = drawingOf({a: drawingTile}).withTexts([text(plateTile)]);
      final second = drawingOf({a: drawingTile}).withTexts([text(other)]);

      final laidFirst = celSurfaceWithTextsLaid(first).tileAt(a);
      final laidSecond = celSurfaceWithTextsLaid(second).tileAt(a);

      // New surfaces over the same tiles: only the per-tile memory can
      // answer, and it has to hold both.
      expect(
        celSurfaceWithTextsLaid(
          drawingOf({a: drawingTile}).withTexts([text(plateTile)]),
        ).tileAt(a),
        same(laidFirst),
      );
      expect(
        celSurfaceWithTextsLaid(
          drawingOf({a: drawingTile}).withTexts([text(other)]),
        ).tileAt(a),
        same(laidSecond),
      );
      expect(laidFirst, isNot(same(laidSecond)), reason: 'fixture');
    });
  });
}
