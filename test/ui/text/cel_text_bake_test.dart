import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/text/cel_text_bake.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_text_fixture.dart';

/// R9-rest (the text tool): THE ONE PLACE A TEXT'S PIXELS COME FROM.
/// `bakeCelTextPlate` turns a set text into the plate its cel keeps — and
/// that plate is what every route shows (`celSurfaceWithTextsLaid`), so
/// what it holds here is what the person sees, saves and exports.
///
/// ⚠️The test font sets every glyph as a filled box one letter-size wide
/// and tall, so at a line pitch of 1 and size 8 — the fixture's tile — a
/// letter on the grid IS a tile.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ink = [10, 20, 30, 255];

  CelTextContent said(
    List<CelTextSpan> spans, {
    double x = 8,
    double y = 8,
    double turn = 0,
    double? wrapWidth,
    int? background,
    double lineHeight = 1,
    bool vertical = false,
  }) => CelTextContent(
    spans: spans,
    anchor: CanvasPoint(x: x, y: y),
    rotationDegrees: turn,
    wrapWidth: wrapWidth,
    lineHeight: lineHeight,
    backgroundColor: background,
    vertical: vertical,
  );

  CelTextSpan run(
    String words, {
    double size = 8,
    int color = 0xFF0A141E,
    int? outline,
    double outlineWidth = 0,
  }) => CelTextSpan(
    text: words,
    style: TextLetterStyle(
      fontSize: size,
      color: color,
      outlineColor: outline,
      outlineWidth: outlineWidth,
    ),
  );

  Future<Map<TileCoord, BitmapTile>> baked(
    CelTextContent content, {
    Map<TileCoord, BitmapTile> previous = const {},
  }) async {
    final layout = layoutCelText(content);
    try {
      return await bakeCelTextPlate(
        layout,
        canvasSize: celTextTestCanvas,
        tileSize: celTextTestTileSize,
        previous: previous,
      );
    } finally {
      layout.dispose();
    }
  }

  /// What the engine draws for [content] over the whole pasteboard, cut
  /// into the fixture's tiles by hand — every tile, the empty ones too.
  Future<Map<TileCoord, Uint8List>> engineTilesOf(
    CelTextContent content,
  ) async {
    final wall = celTextTestCanvas.pasteboardRect;
    final layout = layoutCelText(content);
    final recorder = ui.PictureRecorder();
    layout.paint(ui.Canvas(recorder)..translate(-wall.left, -wall.top));
    final picture = recorder.endRecording();
    final width = wall.width.toInt();
    final height = wall.height.toInt();
    final image = await picture.toImage(width, height);
    picture.dispose();
    layout.dispose();
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    image.dispose();
    final bytes = data!.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    const size = celTextTestTileSize;
    final tiles = <TileCoord, Uint8List>{};
    for (var ty = 0; ty < height ~/ size; ty += 1) {
      for (var tx = 0; tx < width ~/ size; tx += 1) {
        final tile = Uint8List(BitmapTile.bytesFor(size));
        for (var row = 0; row < size; row += 1) {
          final from = ((ty * size + row) * width + tx * size) * 4;
          tile.setRange(row * size * 4, (row + 1) * size * 4, bytes, from);
        }
        tiles[TileCoord(
          x: tx + wall.left.toInt() ~/ size,
          y: ty + wall.top.toInt() ~/ size,
        )] = tile;
      }
    }
    return tiles;
  }

  bool hasInk(Uint8List tile) {
    for (var i = 3; i < tile.length; i += 4) {
      if (tile[i] != 0) {
        return true;
      }
    }
    return false;
  }

  /// A text that tries every setting at once, off the pixel grid.
  CelTextContent everything({double turn = 30}) => said(
    [
      run('a', size: 10),
      run('b', size: 14, outline: 0xFFFF0000, outlineWidth: 3),
      run('\nc', size: 9, color: 0x800000FF),
    ],
    x: 9.5,
    y: 6.25,
    turn: turn,
    background: 0x4000FF00,
    lineHeight: 1.25,
  );

  test('a letter set on the grid is the tile it covers, in its colour — '
      'and the plate holds no other', () async {
    final plate = await baked(said([run('ab')]));

    expect(plate.keys.toSet(), {TileCoord(x: 1, y: 1), TileCoord(x: 2, y: 1)});
    for (final tile in plate.values) {
      expect(tile.pixels, tileFilledWith(ink).pixels);
    }
  });

  // 세로쓰기 (유저 2026-10-06). 「123」 is three digits — too many for one
  // cell — so each stands in a cell of its own: a tile apiece at size 8.
  test('🚨a text in COLUMNS is drawn DOWN from its anchor and to its left: '
      'a letter a tile, one under the other', () async {
    final plate = await baked(said([run('123')], x: 16, vertical: true));

    expect(plate.keys.toSet(), {
      TileCoord(x: 1, y: 1),
      TileCoord(x: 1, y: 2),
      TileCoord(x: 1, y: 3),
    });
    for (final tile in plate.values) {
      expect(tile.pixels, tileFilledWith(ink).pixels);
    }

    // ⛔CONTROL: in lines the very text runs to the RIGHT of that anchor.
    final lines = await baked(said([run('123')], x: 16));
    expect(lines.keys.toSet(), {
      TileCoord(x: 2, y: 1),
      TileCoord(x: 3, y: 1),
      TileCoord(x: 4, y: 1),
    });
  });

  // Three digits, each a cell of its own, tracked by a whole tile.
  test('🚨a standing letter\'s TRACKING is room after it and no part of '
      'where it is drawn: its ink is at the HEAD of its room, across the '
      'whole of its column — a tile, and the tile after it empty', () async {
    final plate = await baked(
      said(
        [
          const CelTextSpan(
            text: '123',
            style: TextLetterStyle(
              fontSize: 8,
              color: 0xFF0A141E,
              letterSpacing: 8,
            ),
          ),
        ],
        x: 16,
        y: 0,
        vertical: true,
      ),
    );

    // 「1」 at the anchor's left, a tile of room, 「2」 — and nothing of
    // either in the tile between them, or in the columns beside them.
    final one = TileCoord(x: 1, y: 0);
    final two = TileCoord(x: 1, y: 2);
    expect(
      {
        for (final coord in plate.keys)
          if (coord.y <= 2) coord,
      },
      {one, two},
    );
    expect(plate[one]!.pixels, tileFilledWith(ink).pixels);
    expect(plate[two]!.pixels, tileFilledWith(ink).pixels);
  });

  test('a break typed into a text in columns opens the next one to the '
      'LEFT, and a word lying down runs down its column', () async {
    final plate = await baked(said([run('7\nab')], x: 24, vertical: true));

    // 「7」 at the anchor's left; 「ab」 lying down the column left of that.
    expect(plate.keys.toSet(), {
      TileCoord(x: 2, y: 1),
      TileCoord(x: 1, y: 1),
      TileCoord(x: 1, y: 2),
    });
    for (final tile in plate.values) {
      expect(tile.pixels, tileFilledWith(ink).pixels);
    }
  });

  test('🚨the plate IS what the engine draws for the text: every tile of '
      'the pasteboard, byte for byte, and no tile where it drew '
      'nothing', () async {
    for (final content in [everything(), everything(turn: 0)]) {
      final engine = await engineTilesOf(content);

      final plate = await baked(content);

      expect(
        plate.keys.toSet(),
        {
          for (final entry in engine.entries)
            if (hasInk(entry.value)) entry.key,
        },
        reason: 'a tile for every tile with a pixel in it, and only those',
      );
      expect(plate.length, greaterThan(4), reason: '⛔fixture: several tiles');
      for (final entry in plate.entries) {
        expect(
          entry.value.pixels,
          engine[entry.key],
          reason: 'the tile at ${entry.key}',
        );
      }
    }
  });

  test('a pixel the text does not reach carries no colour', () async {
    final plate = await baked(everything());

    var clear = 0;
    for (final tile in plate.values) {
      final pixels = tile.pixels;
      for (var i = 0; i < pixels.length; i += 4) {
        if (pixels[i + 3] == 0) {
          clear += 1;
          expect(pixels.sublist(i, i + 3), [0, 0, 0]);
        }
      }
    }
    expect(clear, greaterThan(0), reason: '⛔fixture: some pixels are clear');
  });

  test('a text with no letters has no plate', () async {
    expect(await baked(said(const [])), isEmpty);
  });

  group('the pasteboard wall', () {
    // The fixture's canvas is 32 wide and its pasteboard a canvas more on
    // every side: the wall stands at 64, the right edge of tile 7.
    test('a text set across it is cut there, as every picture is', () async {
      final plate = await baked(said([run('abc')], x: 60));

      expect(plate.keys.toSet(), {TileCoord(x: 7, y: 1)});
      final pixels = plate.values.single.pixels;
      for (var y = 0; y < 8; y += 1) {
        for (var x = 0; x < 8; x += 1) {
          expect(
            pixels.sublist((y * 8 + x) * 4, (y * 8 + x) * 4 + 4),
            x < 4 ? [0, 0, 0, 0] : ink,
            reason: 'the letter starts at 60 — pixel ($x, $y) of the tile',
          );
        }
      }
    });

    test('🚨the bake rasters what the pasteboard can keep and no more: a '
        'text set far larger than it is cut BEFORE the raster', () {
      final huge = layoutCelText(
        said([run('a', size: 4000)], x: -1000, y: -1000),
      );
      addTearDown(huge.dispose);
      expect(huge.inkBounds.width, greaterThan(4000), reason: '⛔fixture');

      expect(
        celTextBakeWindow(huge, celTextTestCanvas),
        celTextTestCanvas.pasteboardRect,
      );

      final small = layoutCelText(said([run('ab')]));
      addTearDown(small.dispose);
      expect(celTextBakeWindow(small, celTextTestCanvas), small.inkBounds);
    });

    test('a text set wholly beyond it has no plate', () async {
      expect(await baked(said([run('ab')], x: 500, y: 500)), isEmpty);
      expect(await baked(said([run('ab')], x: -500, y: -500)), isEmpty);
    });
  });

  group('the plate it had before', () {
    test('🚨a tile that came out the same IS the last plate\'s tile — the '
        'object, so what was laid and uploaded for it stands', () async {
      final before = await baked(said([run('ab')]));

      final after = await baked(said([run('abc')]), previous: before);

      expect(after.keys.toSet(), {
        TileCoord(x: 1, y: 1),
        TileCoord(x: 2, y: 1),
        TileCoord(x: 3, y: 1),
      });
      expect(after[TileCoord(x: 1, y: 1)], same(before[TileCoord(x: 1, y: 1)]));
      expect(after[TileCoord(x: 2, y: 1)], same(before[TileCoord(x: 2, y: 1)]));
    });

    test('a tile that changed is the new one', () async {
      final before = await baked(said([run('ab')]));

      final after = await baked(
        said([run('a'), run('b', color: 0xFFC80000)]),
        previous: before,
      );

      expect(after[TileCoord(x: 1, y: 1)], same(before[TileCoord(x: 1, y: 1)]));
      expect(
        after[TileCoord(x: 2, y: 1)]!.pixels,
        tileFilledWith([200, 0, 0, 255]).pixels,
      );
    });

    test('a tile the text left is gone from the plate', () async {
      final before = await baked(said([run('ab')]));

      final after = await baked(said([run('a')]), previous: before);

      expect(after.keys.toSet(), {TileCoord(x: 1, y: 1)});
    });
  });
}
