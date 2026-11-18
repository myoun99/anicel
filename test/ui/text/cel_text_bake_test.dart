import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/ui/text/cel_text_bake.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_text_fixture.dart';
import '../../helpers/tiles_on_the_engine.dart';

/// R9-rest (the text tool): THE ONE PLACE A TEXT'S PIXELS COME FROM.
/// `bakeCelTextPlate` turns a set text into the plate its cel keeps — and
/// that plate is what every route shows (`celSurfaceWithTextsLaid`), so
/// what it holds here is what the person sees, saves and exports.
///
/// ⚠️The test font sets every glyph as a filled box one letter-size wide
/// and tall, so at a line pitch of 1 and size 128 — the fixture's tile — a
/// letter on the grid IS a tile: the one it fills, its edge antialiased as
/// its renderer draws it (`expectLetters`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ink = [10, 20, 30, 255];

  CelTextContent said(
    List<CelTextSpan> spans, {
    double x = 128,
    double y = 128,
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
    double size = 128,
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
        pasteboard: celTextTestCanvas.pasteboardAt(PasteboardReach.whole),
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
    final wall = celTextTestCanvas.pasteboardAt(PasteboardReach.whole).rect;
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

  /// [plate] as a failure says it: each tile, how many of its pixels hold
  /// any alpha, the most one holds, and the box they lie in. On the Mac
  /// runner a plate held tiles a letter does not cover (round-1091-builds-
  /// all-stop-at-their-checks, 11-16) — what is in them says whether the
  /// raster left a trace there or the plate took tiles it should not.
  String inkOf(Map<TileCoord, BitmapTile> plate) => [
    for (final MapEntry(:key, :value) in plate.entries)
      '(${key.x},${key.y}) ${_inkIn(value.pixels, value.size)}',
  ].join(' · ');

  /// The tiles of [plate] a letter fills: every pixel of them [rgba].
  Set<TileCoord> lettersIn(
    Map<TileCoord, BitmapTile> plate, [
    List<int> rgba = ink,
  ]) => {
    for (final MapEntry(:key, :value) in plate.entries)
      if (_allOf(value.pixels, rgba)) key,
  };

  /// [plate] holding [letters], each the tile it fills in [rgba], and no
  /// ink anywhere else but a letter's edge: less than a whole pixel of it,
  /// in the row or column of a tile beside a letter that touches it, or the
  /// corner of one at its corner.
  ///
  /// 🚨A RENDERER ANTIALIASES THE BOX'S EDGE, and the pixel that edge lies
  /// in may be the next tile's (저장 2026-11-16, round-1091-builds-all-
  /// stop-at-their-checks): on the Mac runner each letter on the grid
  /// filled its tile whole and left alpha up to 156 in the row above it
  /// and up to 81 in the column at either side, nothing below — and nine
  /// of these tests, pinning the tiles letters fill and no other, or a
  /// tile beside a letter the same, failed there alone. The plate is what
  /// the engine draws either way (the test of that is green on the Mac):
  /// a test here names where its letters stand, and leaves their edges to
  /// the renderer.
  void expectLetters(
    Map<TileCoord, BitmapTile> plate,
    Set<TileCoord> letters, [
    List<int> rgba = ink,
  ]) {
    expect(lettersIn(plate, rgba), letters, reason: inkOf(plate));
    for (final MapEntry(:key, :value) in plate.entries) {
      if (!letters.contains(key)) {
        expect(
          _inkOffTheEdge(value.pixels, value.size, key, letters),
          isNull,
          reason: 'the tile at $key holds ink off a letter\'s edge',
        );
      }
    }
  }

  /// A text that tries every setting at once, off the pixel grid.
  CelTextContent everything({double turn = 30}) => said(
    [
      run('a', size: 160),
      run('b', size: 224, outline: 0xFFFF0000, outlineWidth: 48),
      run('\nc', size: 144, color: 0x800000FF),
    ],
    x: 152.5,
    y: 100.25,
    turn: turn,
    background: 0x4000FF00,
    lineHeight: 1.25,
  );

  test('a letter set on the grid is the tile it covers, in its colour — '
      'and the plate holds nothing else but its edge', () async {
    final plate = await baked(said([run('ab')]));

    expectLetters(plate, {TileCoord(x: 1, y: 1), TileCoord(x: 2, y: 1)});
  });

  // 세로쓰기 (유저 2026-10-06). 「123」 is three digits — too many for one
  // cell — so each stands in a cell of its own: a tile apiece at size 128.
  test('🚨a text in COLUMNS is drawn DOWN from its anchor and to its left: '
      'a letter a tile, one under the other', () async {
    final plate = await baked(said([run('123')], x: 256, vertical: true));

    expectLetters(plate, {
      TileCoord(x: 1, y: 1),
      TileCoord(x: 1, y: 2),
      TileCoord(x: 1, y: 3),
    });

    // ⛔CONTROL: in lines the very text runs to the RIGHT of that anchor.
    final lines = await baked(said([run('123')], x: 256));
    expectLetters(lines, {
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
              fontSize: 128,
              color: 0xFF0A141E,
              letterSpacing: 128,
            ),
          ),
        ],
        x: 256,
        y: 0,
        vertical: true,
      ),
    );

    // 「1」 at the anchor's left, a tile of room, 「2」 — and nothing of
    // either in the tile between them, or in the columns beside them, but
    // their edges.
    expectLetters(
      {
        for (final MapEntry(:key, :value) in plate.entries)
          if (key.y <= 2) key: value,
      },
      {TileCoord(x: 1, y: 0), TileCoord(x: 1, y: 2)},
    );
  });

  test('a break typed into a text in columns opens the next one to the '
      'LEFT, and a word lying down runs down its column', () async {
    final plate = await baked(said([run('7\nab')], x: 384, vertical: true));

    // 「7」 at the anchor's left; 「ab」 lying down the column left of that.
    expectLetters(plate, {
      TileCoord(x: 2, y: 1),
      TileCoord(x: 1, y: 1),
      TileCoord(x: 1, y: 2),
    });
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
    // The fixture's canvas is 512 wide and its pasteboard a canvas more on
    // every side: the wall stands at 1024, the right edge of tile 7.
    test('a text set across it is cut there, as every picture is', () async {
      const size = celTextTestTileSize;
      final plate = await baked(said([run('abc')], x: 960));

      final cut = TileCoord(x: 7, y: 1);
      expect(plate.keys, contains(cut), reason: inkOf(plate));
      expect(
        plate.keys.where((coord) => coord.x > cut.x),
        isEmpty,
        reason: 'nothing past the wall',
      );
      for (final MapEntry(:key, :value) in plate.entries) {
        if (key != cut) {
          expect(
            _inkOffTheEdge(value.pixels, size, key, {cut}),
            isNull,
            reason: 'the tile at $key holds ink off the letter\'s edge',
          );
        }
      }
      final pixels = plate[cut]!.pixels;
      for (var y = 0; y < size; y += 1) {
        for (var x = 0; x < size; x += 1) {
          final at = (y * size + x) * 4;
          if (x == 63) {
            // The letter's edge, its renderer's to antialias
            // (`expectLetters`): less than a whole pixel of it.
            expect(
              pixels[at + 3],
              lessThan(255),
              reason: 'the letter starts at 960 — pixel 63 is its edge',
            );
          } else {
            expect(
              pixels.sublist(at, at + 4),
              x < 64 ? [0, 0, 0, 0] : ink,
              reason: 'the letter starts at 960 — pixel ($x, $y) of the tile',
            );
          }
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
      final wall = celTextTestCanvas.pasteboardAt(PasteboardReach.whole);

      expect(celTextBakeWindow(huge, wall), wall.rect);

      final small = layoutCelText(said([run('ab')]));
      addTearDown(small.dispose);
      expect(celTextBakeWindow(small, wall), small.inkBounds);
    });

    test('a text set wholly beyond it has no plate', () async {
      expect(await baked(said([run('ab')], x: 8000, y: 8000)), isEmpty);
      expect(await baked(said([run('ab')], x: -8000, y: -8000)), isEmpty);
    });
  });

  group('the plate it had before', () {
    // Letters a space apart, here and below: a letter's edge, antialiased
    // as its renderer draws it, lies in the tile beside it
    // (`expectLetters`), and a letter typed or changed there would change
    // the tile of its neighbour too.
    test('🚨a tile that came out the same IS the last plate\'s tile — the '
        'object, so what was laid and uploaded for it stands', () async {
      final before = await baked(said([run('a b')]));

      final after = await baked(said([run('a b c')]), previous: before);

      expectLetters(after, {
        TileCoord(x: 1, y: 1),
        TileCoord(x: 3, y: 1),
        TileCoord(x: 5, y: 1),
      });
      expect(after[TileCoord(x: 1, y: 1)], same(before[TileCoord(x: 1, y: 1)]));
      expect(after[TileCoord(x: 3, y: 1)], same(before[TileCoord(x: 3, y: 1)]));
    });

    test('🚨the last plate is read back from the engine, only where the new '
        'one has a tile', () async {
      addTearDown(() => EngineTileLedger.debugBeforeRead = null);
      final before = await baked(said([run('a b')]));
      final reads = <int>[];
      EngineTileLedger.debugBeforeRead = (tiles) => reads.add(tiles.length);

      await baked(said([run('abc')]));
      expect(reads, isEmpty, reason: 'no last plate to read');

      final after = await baked(
        said([run('a')]),
        previous: {
          for (final MapEntry(:key, :value) in before.entries)
            key: tileOnEngine(value),
        },
      );
      final left = before.keys.where((coord) => !after.containsKey(coord));
      expect(left, contains(TileCoord(x: 3, y: 1)), reason: '⛔fixture');
      expect(
        reads,
        [after.keys.where(before.containsKey).length],
        reason: 'the tiles both plates have, and none the text left',
      );
    });

    test('a tile that changed is the new one', () async {
      final before = await baked(said([run('a b')]));

      final after = await baked(
        said([run('a '), run('b', color: 0xFFC80000)]),
        previous: before,
      );

      expect(after[TileCoord(x: 1, y: 1)], same(before[TileCoord(x: 1, y: 1)]));
      expect(
        after[TileCoord(x: 3, y: 1)]!.pixels,
        tileFilledWith([200, 0, 0, 255]).pixels,
      );
    });

    test('a tile the text left is gone from the plate', () async {
      final before = await baked(said([run('ab')]));

      final after = await baked(said([run('a')]), previous: before);

      expectLetters(after, {TileCoord(x: 1, y: 1)});
    });
  });
}

/// What of [pixels] — a tile [side] square, straight RGBA — holds any alpha:
/// how many pixels, the most alpha one holds, and the box they lie in.
String _inkIn(Uint8List pixels, int side) {
  var count = 0;
  var most = 0;
  var (left, top, right, bottom) = (side, side, -1, -1);
  for (var at = 0; at < side * side; at += 1) {
    final alpha = pixels[at * 4 + 3];
    if (alpha == 0) {
      continue;
    }
    count += 1;
    if (alpha > most) {
      most = alpha;
    }
    final (x, y) = (at % side, at ~/ side);
    (left, right) = (x < left ? x : left, x > right ? x : right);
    (top, bottom) = (y < top ? y : top, y > bottom ? y : bottom);
  }
  return count == 0
      ? 'no alpha'
      : '$count px, alpha up to $most, x $left..$right y $top..$bottom';
}

/// Whether every pixel of [pixels] is [rgba].
bool _allOf(Uint8List pixels, List<int> rgba) {
  for (var at = 0; at < pixels.length; at += 1) {
    if (pixels[at] != rgba[at % 4]) {
      return false;
    }
  }
  return true;
}

/// The first pixel of [pixels] — the tile at [at], [side] square — that
/// holds any alpha and is no letter's edge: less than a whole pixel, on an
/// edge of the tile that touches a letter's tile, beside it or at its
/// corner. None, null.
(int, int)? _inkOffTheEdge(
  Uint8List pixels,
  int side,
  TileCoord at,
  Set<TileCoord> letters,
) {
  int toward(int coordinate) =>
      coordinate == 0 ? -1 : (coordinate == side - 1 ? 1 : 0);
  bool letterAt(int dx, int dy) =>
      letters.contains(TileCoord(x: at.x + dx, y: at.y + dy));
  for (var y = 0; y < side; y += 1) {
    for (var x = 0; x < side; x += 1) {
      final alpha = pixels[(y * side + x) * 4 + 3];
      if (alpha == 0) {
        continue;
      }
      final (dx, dy) = (toward(x), toward(y));
      final onAnEdge =
          alpha < 255 &&
          ((dx != 0 && letterAt(dx, 0)) ||
              (dy != 0 && letterAt(0, dy)) ||
              (dx != 0 && dy != 0 && letterAt(dx, dy)));
      if (!onAnEdge) {
        return (x, y);
      }
    }
  }
  return null;
}
