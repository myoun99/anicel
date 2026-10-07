import 'dart:ui' as ui;

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/ui/text/canvas_letter_passes.dart';
import 'package:anicel/src/ui/text/text_cel_render.dart';
import 'package:flutter/foundation.dart';
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

  /// A text set — [letters] long, so that one set can be told from another
  /// by its width.
  TextPainter set([int letters = 1]) => TextPainter(
    text: TextSpan(text: 'a' * letters, style: const TextStyle(fontSize: 10)),
    textDirection: TextDirection.ltr,
  )..layout();

  /// The passes of a text whose runs are in [letters] — and, pass by pass
  /// in the order they were set, what each run was to be painted with. The
  /// Nth pass set is N letters long.
  ({
    CanvasLetterPasses<TextPainter> passes,
    List<Map<TextLetterStyle, ui.Paint?>> said,
  })
  passesOf(List<TextLetterStyle> letters, {TextPainter? measured}) {
    final said = <Map<TextLetterStyle, ui.Paint?>>[];
    final passes = canvasLetterPainterPasses(letters, (pass) {
      said.add({for (final style in letters) style: pass.paintOf(style)});
      return set(said.length);
    }, measured: measured);
    addTearDown(passes.dispose);
    return (passes: passes, said: said);
  }

  /// What [passes] draw, call by call: each pass by the number it was set
  /// as, and the layers opened and shut round them.
  List<String> drawnBy(CanvasLetterPasses<TextPainter> passes) {
    final canvas = _WritesDown();
    passes.paintAt(
      canvas,
      ui.Offset.zero,
      within: const ui.Rect.fromLTWH(0, 0, 100, 100),
    );
    return canvas.calls;
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

    test('🚨EVERY outline is under EVERY fill — smooth or hard — and each '
        'hard pass in a layer of its own', () {
      final (:passes, said: _) = passesOf([smoothOutlined, hardOutlined]);

      // Set as: 1 the fill · 2 the smooth outline · 3 the hard outline ·
      // 4 the hard fill. (The hard outline's colour is see-through: a
      // layer of its own round the hard one.)
      expect(drawnBy(passes), [
        'pass 2',
        'cut',
        'layer',
        'layer',
        'pass 3',
        'restore',
        'restore',
        'restore',
        'pass 1',
        'cut',
        'layer',
        'pass 4',
        'restore',
        'restore',
      ]);
    });

    test('hard letters alone, outlined: no smooth pass strokes for them', () {
      final (:passes, :said) = passesOf([hardOutlined]);

      // The fill (it measures) · the hard outline · the hard fill.
      expect(said, hasLength(3));
      expect(drawnBy(passes), [
        'cut',
        'layer',
        'layer',
        'pass 2',
        'restore',
        'restore',
        'restore',
        'pass 1',
        'cut',
        'layer',
        'pass 3',
        'restore',
        'restore',
      ]);
    });

    test('a SMOOTH run in the very colour of a hard one — fill or outline — '
        'is none of the hard pass\'s', () {
      const smoothTwin = TextLetterStyle(
        color: 0xFFAA0000,
        outlineColor: 0x8000BB00,
        outlineWidth: 5,
      );
      final (passes: _, :said) = passesOf([smoothTwin, hardOutlined]);

      expect(said, hasLength(4));
      final [_, _, hardStroke, hardFill] = said;
      expect(drawsNothing(hardStroke[smoothTwin]), isTrue);
      expect(drawsNothing(hardFill[smoothTwin]), isTrue);
    });

    test('two hard runs outlined in two colours: each outline\'s pass '
        'strokes its own and paints the other with nothing', () {
      const otherOutline = TextLetterStyle(
        color: 0xFFAA0000,
        outlineColor: 0xFF0000BB,
        outlineWidth: 2,
        antialias: false,
      );
      final (passes: _, :said) = passesOf([hardOutlined, otherOutline]);

      // The fill · two hard outlines · one hard fill (one colour).
      expect(said, hasLength(4));
      final [_, first, second, _] = said;
      expect(first[hardOutlined]!.strokeWidth, 5);
      expect(drawsNothing(first[otherOutline]), isTrue);
      expect(drawsNothing(second[hardOutlined]), isTrue);
      expect(second[otherOutline]!.strokeWidth, 2);
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
  // What a host that KEEPS what it set is given to keep it by — a text in
  // columns keeps its cells' painters (`cel_text_cell_painters.dart`).
  group('a pass says which it is', () {
    /// The passes a text in [letters] is set in, as a setter is handed them.
    List<CanvasLetterPass> handedFor(List<TextLetterStyle> letters) {
      final handed = <CanvasLetterPass>[];
      final passes = canvasLetterPainterPasses(letters, (pass) {
        handed.add(pass);
        return set();
      });
      addTearDown(passes.dispose);
      return handed;
    }

    test('🚨every pass of a text has a KEY of its own — two hard colours, '
        'two keys', () {
      const hardBlue = TextLetterStyle(color: 0xFF0000AA, antialias: false);

      final handed = handedFor([smoothOutlined, hardOutlined, hardBlue]);

      // The fill · the outline · the hard outline · the two hard fills.
      expect(handed, hasLength(5));
      expect({for (final pass in handed) pass.key}, hasLength(5));
    });

    test('🚨the same pass of ANOTHER text has the same key — and paints a '
        'run of the same letters as the first did: with the letters, the '
        'key says all of it', () {
      final one = handedFor([smoothOutlined, hardOutlined]);
      final other = handedFor([hardOutlined, smooth, smoothOutlined]);

      expect(
        [for (final pass in other) pass.key],
        [for (final pass in one) pass.key],
      );
      for (final (index, pass) in one.indexed) {
        for (final style in [smoothOutlined, hardOutlined]) {
          final first = pass.paintOf(style);
          final second = other[index].paintOf(style);
          expect(second?.color, first?.color);
          expect(second?.style, first?.style);
          expect(second?.strokeWidth, first?.strokeWidth);
          expect(second?.strokeJoin, first?.strokeJoin);
        }
      }
    });

    test('says which runs are its own to DRAW: a run that names a paint '
        'drawing nothing is not', () {
      const all = [smooth, smoothOutlined, hard, hardOutlined];
      var drawn = 0;
      var left = 0;

      for (final pass in handedFor(all)) {
        for (final style in all) {
          expect(
            pass.draws(style),
            !drawsNothing(pass.paintOf(style)),
            reason: '${pass.key}',
          );
          pass.draws(style) ? drawn += 1 : left += 1;
        }
      }

      // Five passes of four runs: the fill draws 2 · the outline 1 · the
      // hard outline 1 · the two hard fills 1 each (the hard styles' two
      // colours differ, by how see-through they are).
      expect((drawn, left), (6, 14));
    });
  });

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

    test('🚨a smooth tag sets its letters ONCE — what it set to measure '
        'itself is what it draws (it is set every frame it is on screen) — '
        'and lets go of everything it set', () {
      final made = <Object>{};
      final gone = <Object>{};
      void heard(ObjectEvent event) {
        if (event.object is! TextPainter) {
          return;
        }
        if (event is ObjectCreated) {
          made.add(event.object);
        } else if (event is ObjectDisposed) {
          gone.add(event.object);
        }
      }

      FlutterMemoryAllocations.instance.addListener(heard);
      addTearDown(
        () => FlutterMemoryAllocations.instance.removeListener(heard),
      );

      layoutTextCel(
        content: const TextCelContent(
          text: 'ab',
          style: TextCelStyle(fontSize: 10),
        ),
        canvas: canvas,
      ).dispose();

      expect(made, hasLength(1));
      expect(gone, made);

      made.clear();
      gone.clear();
      layoutTextCel(
        content: const TextCelContent(
          text: 'ab',
          style: TextCelStyle(fontSize: 10, antialias: false),
        ),
        canvas: canvas,
      ).dispose();

      expect(made, hasLength(3), reason: 'measured, the fill, its cover');
      expect(gone, made, reason: 'the one it measured with too');
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

/// A canvas that writes down what is drawn on it, and draws nothing: a set
/// text by how many letters long it is (`passesOf` sets its Nth pass N
/// letters long, in the test font's ten-pixel boxes).
class _WritesDown implements ui.Canvas {
  final List<String> calls = [];

  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) => calls.add('layer');

  @override
  void clipRect(
    ui.Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) => calls.add('cut');

  @override
  void restore() => calls.add('restore');

  @override
  void drawParagraph(ui.Paragraph paragraph, ui.Offset offset) =>
      calls.add('pass ${(paragraph.longestLine / 10).round()}');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A canvas that counts the layers opened on it and draws nothing.
class _CountsLayers implements ui.Canvas {
  int layers = 0;

  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) => layers += 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
