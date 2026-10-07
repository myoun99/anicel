import 'dart:ui' as ui;

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/text/cel_text_bake.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_text_fixture.dart';

/// R9-rest, the letters' AA switch (유저 2026-10-06: 「권장대로. 2차에서
/// 스위치로 넣음」): a letter whose style says `antialias` false is drawn
/// HARD — every pixel it covers by half or more is its colour, whole, and
/// every other is none of it.
///
/// 🚨ASKED OF THE ENGINE, through the one place a text's pixels come from
/// (`bakeCelTextPlate`): the hardness is made by the engine — a layer and
/// a filter — and only its pixels say whether it was.
///
/// ⚠️The test font sets every glyph as a filled box, which on the pixel
/// grid has no soft edge to begin with: every text here is TURNED and set
/// between pixels, so that smooth it has plenty (each test's control).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const red = 0xFFC80A14;
  const blue = 0xFF0A14C8;
  const green = 0xFF14C80A;

  CelTextSpan run(
    String words, {
    bool antialias = false,
    int color = red,
    int? outline,
    double outlineWidth = 0,
    double size = 10,
  }) => CelTextSpan(
    text: words,
    style: TextLetterStyle(
      fontSize: size,
      color: color,
      outlineColor: outline,
      outlineWidth: outlineWidth,
      antialias: antialias,
    ),
  );

  CelTextContent said(List<CelTextSpan> spans, {int? background}) =>
      CelTextContent(
        spans: spans,
        anchor: CanvasPoint(x: 9.5, y: 6.25),
        rotationDegrees: 25,
        lineHeight: 1,
        backgroundColor: background,
      );

  /// Every pixel with ink that [content] bakes to, as `0xAARRGGBB`.
  Future<List<int>> inkOf(CelTextContent content) async {
    final layout = layoutCelText(content);
    final Map<TileCoord, BitmapTile> plate;
    try {
      plate = await bakeCelTextPlate(
        layout,
        canvasSize: celTextTestCanvas,
        tileSize: celTextTestTileSize,
      );
    } finally {
      layout.dispose();
    }
    return [
      for (final tile in plate.values)
        ...tile.readPixels((_, view) {
          final ink = <int>[];
          for (var at = 0; at < view.length; at += 4) {
            if (view[at + 3] != 0) {
              ink.add(
                view[at + 3] << 24 |
                    view[at] << 16 |
                    view[at + 1] << 8 |
                    view[at + 2],
              );
            }
          }
          return ink;
        }),
    ];
  }

  Set<String> hex(Iterable<int> pixels) => {
    for (final pixel in pixels) pixel.toRadixString(16).padLeft(8, '0'),
  };

  group('a hard letter', () {
    test('🚨is its colour, whole, or nothing — turned and between pixels', () async {
      final hard = await inkOf(said([run('ab')]));

      expect(hard, isNotEmpty, reason: 'it IS drawn');
      expect(hex(hard), {'ffc80a14'});

      // ⛔CONTROL: smooth, the same text has an edge of in-between pixels.
      final smooth = await inkOf(said([run('ab', antialias: true)]));
      expect(hex(smooth).length, greaterThan(4), reason: '⛔fixture');
    });

    test('covers about what it covers smooth: half a pixel is the line', () async {
      final hard = await inkOf(said([run('ab')]));
      final smooth = await inkOf(said([run('ab', antialias: true)]));
      // Smooth, the cover is the sum of every pixel's share.
      final cover = smooth.fold<double>(
        0,
        (sum, pixel) => sum + (pixel >>> 24) / 255,
      );

      expect(hard.length, closeTo(cover, cover * 0.08));
    });

    test('in a see-through colour is that colour, as see-through as it is '
        'smooth — or nothing', () async {
      final hard = await inkOf(said([run('ab', color: 0x80C80A14)]));

      expect(hard, isNotEmpty);
      expect({for (final pixel in hard) pixel >>> 24}, {0x80});
      // What it covers is read off its SHAPE, never off how see-through
      // its colour is.
      final whole = await inkOf(said([run('ab')]));
      expect(hard.length, whole.length);
    });

    test('with an OUTLINE is fill, outline, or nothing', () async {
      final hard = await inkOf(
        said([run('ab', outline: blue, outlineWidth: 3)]),
      );

      expect(hex(hard), {'ffc80a14', 'ff0a14c8'});
    });

    test('🚨its outline is UNDER its fill, and whole: the fill covers what it '
        'covers with no outline, and the outline about what it covers '
        'smooth', () async {
      int count(List<int> pixels, int argb) =>
          pixels.where((pixel) => pixel == argb).length;
      final bare = await inkOf(said([run('ab')]));
      final hard = await inkOf(
        said([run('ab', outline: blue, outlineWidth: 3)]),
      );
      final smooth = await inkOf(
        said([run('ab', antialias: true, outline: blue, outlineWidth: 3)]),
      );
      // Smooth, the outline's cover is what is not the fill's.
      final all = smooth.fold<double>(
        0,
        (sum, pixel) => sum + (pixel >>> 24) / 255,
      );

      expect(count(hard, red), bare.length);
      expect(
        count(hard, blue),
        closeTo(all - bare.length, (all - bare.length) * 0.15),
      );
    });
  });

  group('beside other letters', () {
    test('🚨two hard letters of different colours never blend where they '
        'meet: each pixel is one of the two, whole', () async {
      final hard = await inkOf(said([run('a'), run('b', color: blue)]));

      expect(hex(hard), {'ffc80a14', 'ff0a14c8'});
    });

    test('a hard letter beside a SMOOTH one: the smooth one keeps its soft '
        'edge, the hard one has none', () async {
      final mixed = await inkOf(
        said([run('a'), run('b', antialias: true, color: blue)]),
      );

      int redOf(int pixel) => (pixel >> 16) & 0xFF;
      // The hard letter's pixels are the ones that are red at all: the
      // smooth one's are blue, however faint.
      final ofTheHard = mixed.where((pixel) => redOf(pixel) > 0x80);
      final ofTheSmooth = mixed.where((pixel) => redOf(pixel) <= 0x80);
      expect(hex(ofTheHard), {'ffc80a14'});
      expect(hex(ofTheSmooth).length, greaterThan(2));
    });
  });

  group('the box behind the letters', () {
    test('is HARD where every letter is: a text with no smoothed letter '
        'has no smoothed edge', () async {
      final hard = await inkOf(said([run('ab')], background: green));

      expect(hex(hard), {'ffc80a14', 'ff14c80a'});
    });

    test('⛔CONTROL: with one smooth letter the box is smooth — read off '
        'the box alone, where no letter is', () async {
      // The letters are see-through to nothing: only the box is drawn, and
      // every soft pixel is the box's own edge.
      final mixed = await inkOf(
        said([
          run('a', color: 0x00000000),
          run('b', antialias: true, color: 0x00000000),
        ], background: green),
      );
      final hard = await inkOf(
        said([
          run('a', color: 0x00000000),
          run('b', color: 0x00000000),
        ], background: green),
      );

      expect(hex(mixed).length, greaterThan(4), reason: 'a soft edge');
      expect(hex(hard), {'ff14c80a'}, reason: '⛔fixture: all hard, no edge');
    });
  });

  group('what is drawn for it', () {
    int layersOf(CelTextContent content) {
      final layout = layoutCelText(content);
      final canvas = _CountsLayers();
      layout.paint(canvas);
      layout.dispose();
      return canvas.layers;
    }

    test('🚨a text with NO hard letter is drawn in no layer at all — the two '
        'passes it always was', () {
      expect(
        layersOf(
          said([
            run('ab', antialias: true, outline: blue, outlineWidth: 2),
          ], background: green),
        ),
        0,
      );
    });

    test('one layer A COLOUR: the fills, and the outlines under them', () {
      expect(layersOf(said([run('ab')])), 1);
      expect(layersOf(said([run('a'), run('b')])), 1, reason: 'one colour');
      expect(layersOf(said([run('a'), run('b', color: blue)])), 2);
      expect(
        layersOf(said([run('ab', outline: blue, outlineWidth: 2)])),
        2,
        reason: 'the fill, and the outline',
      );
      expect(
        layersOf(said([run('ab')], background: green)),
        2,
        reason: 'the fill, and the box',
      );
    });

    test('an outline with no width is no outline, hard or smooth', () {
      expect(layersOf(said([run('ab', outline: blue)])), 1);
    });

    test('🚨a hard pass is CUT at the room it is given, on every engine — '
        'all the letters can draw, a letter\'s size past their block', () {
      final layout = layoutCelText(
        said([run('ab', outline: blue, outlineWidth: 4)]),
      );
      final canvas = _CountsLayers();
      layout.paint(canvas);

      // Size 10: the block is 20 by 10, and the room a letter's size and
      // half the outline past it on every side.
      expect(canvas.cuts, hasLength(2), reason: 'the outline, the fill');
      expect(
        canvas.cuts.toSet(),
        {layout.block.inflate(10 + 2)},
      );
      layout.dispose();
    });

    test('the box behind hard letters is cut at itself', () {
      final layout = layoutCelText(said([run('ab')], background: green));
      final canvas = _CountsLayers();
      layout.paint(canvas);
      layout.dispose();

      expect(canvas.cuts.first, layout.box);
    });
  });
}

/// A canvas that counts the layers opened on it, keeps the rects it was cut
/// at, and draws nothing.
class _CountsLayers implements ui.Canvas {
  int layers = 0;
  final List<ui.Rect> cuts = [];

  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) => layers += 1;

  @override
  void clipRect(
    ui.Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) => cuts.add(rect);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
