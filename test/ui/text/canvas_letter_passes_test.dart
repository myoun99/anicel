import 'dart:ui' as ui;

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/text/canvas_letter_passes.dart';
import 'package:anicel/src/ui/text/text_cel_render.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// THE PASSES A CANVAS TEXT'S LETTERS ARE DRAWN IN (`CanvasLetterPasses`) —
/// asked at the seam both texts hand it: how each sets its letters once
/// more, every run painted by what the passes say of its letters.
///
/// What comes of the passes in PIXELS is asked of the engine
/// (`hard_letters_have_no_soft_edge_test.dart`); here, which passes there
/// are, what each paints which letters with, and that the SE name tag —
/// set every frame — sets nothing twice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const smooth = TextLetterStyle(color: 0xFF112233);
  const smoothOutlined = TextLetterStyle(
    color: 0xFF112233,
    outlineColor: 0xFF445566,
    outlineWidth: 3,
  );
  const hard = TextLetterStyle(color: 0x80AA0000, antialias: false);
  const hardOutlined = TextLetterStyle(
    color: 0xFFAA0000,
    outlineColor: 0x8000BB00,
    outlineWidth: 5,
    antialias: false,
  );

  TextPainter set() => TextPainter(
    text: const TextSpan(text: 'a'),
    textDirection: TextDirection.ltr,
  )..layout();

  /// The passes of a text whose runs are in [letters] — and, pass by pass
  /// in the order they were set, what each run was to be painted with.
  ({CanvasLetterPasses passes, List<Map<TextLetterStyle, ui.Paint?>> said})
  passesOf(List<TextLetterStyle> letters, {TextPainter? measured}) {
    final said = <Map<TextLetterStyle, ui.Paint?>>[];
    final passes = CanvasLetterPasses.of(letters, (paintOf) {
      said.add({for (final style in letters) style: paintOf(style)});
      return set();
    }, measured: measured);
    addTearDown(passes.dispose);
    return (passes: passes, said: said);
  }

  bool drawsNothing(ui.Paint? paint) => paint != null && paint.color.a == 0;

  group('smooth letters', () {
    test('with no outline are ONE pass: the letters in their own colour', () {
      final (passes: _, :said) = passesOf([smooth]);

      expect(said, hasLength(1));
      expect(said.single[smooth], isNull, reason: 'its own colour');
    });

    test('with an outline are two: the fill, and the outline under it — a '
        'run with none painted with nothing there', () {
      final (passes: _, :said) = passesOf([smooth, smoothOutlined]);

      expect(said, hasLength(2));
      final [fill, stroke] = said;
      expect(fill.values, everyElement(isNull));
      expect(drawsNothing(stroke[smooth]), isTrue);
      final outline = stroke[smoothOutlined]!;
      expect(outline.style, ui.PaintingStyle.stroke);
      expect(outline.strokeWidth, 3);
      expect(outline.color.toARGB32(), 0xFF445566);
    });
  });

  group('hard letters', () {
    test('🚨are not the smooth passes\' to draw, and each COLOUR of them is '
        'a pass of its own — set in that colour, opaque', () {
      final (passes: _, :said) = passesOf([smooth, hard]);

      expect(said, hasLength(2));
      final [fill, cover] = said;
      expect(fill[smooth], isNull);
      expect(drawsNothing(fill[hard]), isTrue);
      expect(drawsNothing(cover[smooth]), isTrue);
      expect(
        cover[hard]!.color.toARGB32(),
        0xFFAA0000,
        reason: 'its own colour, whole: the colour\'s alpha is not cover',
      );
      expect(cover[hard]!.style, ui.PaintingStyle.fill);
    });

    test('with an outline: the outline\'s colour is a pass too, under the '
        'fills — stroked as wide, and no smooth pass strokes it', () {
      final (passes: _, :said) = passesOf([smoothOutlined, hardOutlined]);

      // The fill · the smooth outline · the hard outline · the hard fill.
      expect(said, hasLength(4));
      final [fill, stroke, hardStroke, hardFill] = said;
      expect(drawsNothing(fill[hardOutlined]), isTrue);
      expect(drawsNothing(stroke[hardOutlined]), isTrue);
      expect(drawsNothing(hardStroke[smoothOutlined]), isTrue);
      expect(drawsNothing(hardFill[smoothOutlined]), isTrue);
      final outline = hardStroke[hardOutlined]!;
      expect(outline.style, ui.PaintingStyle.stroke);
      expect(outline.strokeWidth, 5);
      expect(outline.strokeJoin, ui.StrokeJoin.round);
      expect(outline.color.toARGB32(), 0xFF00BB00);
      expect(hardFill[hardOutlined]!.color.toARGB32(), 0xFFAA0000);
    });

    test('two runs of ONE colour are one pass; of two colours, two — each '
        'painting the other\'s letters with nothing', () {
      const other = TextLetterStyle(color: 0xFF0000AA, antialias: false);
      const same = TextLetterStyle(
        color: 0x80AA0000,
        fontSize: 12,
        antialias: false,
      );

      expect(passesOf([hard, same]).said, hasLength(2));
      final (passes: _, :said) = passesOf([hard, other]);
      expect(said, hasLength(3));
      expect(drawsNothing(said[1][other]), isTrue);
      expect(drawsNothing(said[2][hard]), isTrue);
    });

    test('an outline of no width is no outline', () {
      const named = TextLetterStyle(
        color: 0xFFAA0000,
        outlineColor: 0xFF00BB00,
        antialias: false,
      );

      expect(passesOf([named]).said, hasLength(2));
    });
  });

  // The SE name tag is set every frame it is on screen, and has to set its
  // letters to know how large it is.
  group('what was set to measure the text', () {
    test('🚨IS the fill pass where no letter is hard: nothing is set twice', () {
      final measured = set();

      final (:passes, :said) = passesOf([smooth], measured: measured);

      expect(passes.fill, same(measured));
      expect(said, isEmpty);
    });

    test('is let go of where one is — the fill pass draws nothing of a hard '
        'letter', () {
      final measured = set();

      final (:passes, :said) = passesOf([hard], measured: measured);

      expect(passes.fill, isNot(same(measured)));
      expect(measured.debugDisposed, isTrue);
      expect(said, hasLength(2));
    });
  });

  group('the SE name tag is drawn through them', () {
    const canvas = CanvasSize(width: 64, height: 32);

    int layersOf(TextCelStyle style) {
      final layout = layoutTextCel(
        content: TextCelContent(
          text: 'ab',
          style: style,
          position: const ui.Offset(20.5, 8.25),
        ),
        canvas: canvas,
      );
      final spy = _CountsLayers();
      layout.paint(spy);
      layout.dispose();
      return spy.layers;
    }

    test('a smooth tag in no layer, as it always was', () {
      expect(
        layersOf(
          const TextCelStyle(
            fontSize: 10,
            outlineColor: 0xFF000000,
            outlineWidth: 2,
            backgroundColor: 0xFFC95C5C,
          ),
        ),
        0,
      );
    });

    test('a hard tag in a layer for its letters, one for their outline and '
        'one for its box', () {
      expect(layersOf(const TextCelStyle(fontSize: 10, antialias: false)), 1);
      expect(
        layersOf(
          const TextCelStyle(
            fontSize: 10,
            outlineColor: 0xFF000000,
            outlineWidth: 2,
            backgroundColor: 0xFFC95C5C,
            antialias: false,
          ),
        ),
        3,
      );
    });

    test('a hard tag is the size and stands where the smooth one does', () {
      TextCelLayout tag({required bool antialias}) => layoutTextCel(
        content: TextCelContent(
          text: 'ab',
          style: TextCelStyle(fontSize: 10, antialias: antialias),
        ),
        canvas: canvas,
      );
      final smoothTag = tag(antialias: true);
      final hardTag = tag(antialias: false);
      addTearDown(smoothTag.dispose);
      addTearDown(hardTag.dispose);

      expect(hardTag.textSize, smoothTag.textSize);
      expect(hardTag.topLeft, smoothTag.topLeft);
      expect(hardTag.inkBounds, smoothTag.inkBounds);
    });
  });
}

/// A canvas that counts the layers opened on it and draws nothing.
class _CountsLayers implements ui.Canvas {
  int layers = 0;

  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) => layers += 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
