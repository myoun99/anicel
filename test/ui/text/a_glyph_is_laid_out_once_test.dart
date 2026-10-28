import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/se_dialogue_spacing.dart';
import 'package:anicel/src/ui/text/dialogue_fit_paint.dart';
import 'package:anicel/src/ui/text/laid_out_glyph.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/text/word_condensation.dart';
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';

/// 🚨I-57 (10-13, profile, the user's project): a placer that sets writing
/// glyph by glyph lays each glyph out ONCE, from the app's one cache
/// ([laidOutGlyph]). The SE dialogue's two placers and the vertical-writing
/// renderer laid every glyph out afresh at every paint, and an SE span
/// measured its dialogue the same way at every layout — so a cut crossing
/// laid all of them out again.
///
/// The oracle is the paragraph a paint DRAWS: a glyph laid out once is the
/// same paragraph at every paint, and the same one the cache holds.
class _Paragraphs implements Canvas {
  final drawn = <ui.Paragraph>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      drawn.add(paragraph);

  @override
  int getSaveCount() => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

List<ui.Paragraph> _drawnBy(void Function(Canvas canvas) paint) {
  final canvas = _Paragraphs();
  paint(canvas);
  return canvas.drawn;
}

/// What the one cache holds for each of [glyphs] in [style], as drawn.
List<ui.Paragraph> _cached(Iterable<String> glyphs, TextStyle style) => [
  for (final glyph in glyphs)
    ..._drawnBy(
      (canvas) => laidOutGlyph(glyph, style).paint(canvas, Offset.zero),
    ),
];

void _expectTheSame(
  List<ui.Paragraph> drawn,
  List<ui.Paragraph> laidOut, {
  required String reason,
}) {
  expect(drawn, hasLength(laidOut.length), reason: '$reason: a glyph each');
  for (var i = 0; i < drawn.length; i += 1) {
    expect(
      identical(drawn[i], laidOut[i]),
      isTrue,
      reason: '$reason: glyph $i was laid out again',
    );
  }
}

void main() {
  // Three glyphs with room to spare, so none of them is narrowed.
  const dialogue = 'せりふ';
  const style = TextStyle(fontSize: 20);

  test('🚨past its 2048 the one cache lets go of the glyph laid out longest '
      'ago — not one asked for again since', () {
    // Whatever another test left in the cache is older than all of these.
    const room = 2048;
    final first = laidOutGlyph('first', style);
    final second = laidOutGlyph('second', style);
    for (var i = 0; i < room - 2; i += 1) {
      laidOutGlyph('glyph $i', style);
    }
    expect(laidOutGlyph('first', style), same(first), reason: 'held');

    laidOutGlyph('one more', style);

    expect(laidOutGlyph('first', style), same(first), reason: 'asked again');
    expect(
      laidOutGlyph('second', style),
      isNot(same(second)),
      reason: 'laid out longest ago: it went',
    );
  });

  test('down a column, the dialogue draws the glyphs the one cache '
      'holds', () {
    final drawn = _drawnBy(
      (canvas) => paintDialogueFitColumn(
        canvas,
        dialogue,
        topCenter: const Offset(20, 0),
        extent: 600,
        frames: 30,
        spacing: SeDialogueSpacing.standard,
        style: style,
        setWord: paintFittedText,
        maxCrossExtent: 40,
      ),
    );

    expect(drawn, hasLength(3), reason: 'LIVENESS: the column painted');
    _expectTheSame(
      drawn,
      _cached(dialogue.characters, style),
      reason: 'the column',
    );
  });

  testWidgets('along a row, the dialogue draws the glyphs the one cache '
      'holds', (tester) async {
    late TextStyle printed;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 600,
            height: 40,
            child: Builder(
              builder: (context) {
                printed = dialogueFitStyle(
                  context,
                  color: Colors.black,
                  fontSize: 20,
                );
                return const DialogueFitText(
                  text: dialogue,
                  axis: Axis.horizontal,
                  color: Colors.black,
                  frames: 30,
                  spacing: SeDialogueSpacing.standard,
                  fontSize: 20,
                );
              },
            ),
          ),
        ),
      ),
    );
    final glyphs = find.descendant(
      of: find.byType(DialogueFitText),
      matching: find.byType(CustomPaint),
    );
    final painter = tester.widget<CustomPaint>(glyphs).painter!;
    final size = tester.getSize(glyphs);

    final drawn = _drawnBy((canvas) => painter.paint(canvas, size));

    expect(drawn, hasLength(3), reason: 'LIVENESS: the row painted');
    _expectTheSame(
      drawn,
      _cached(dialogue.characters, printed),
      reason: 'the row',
    );
  });

  test('the vertical writer draws, at every paint, the glyphs it laid out '
      'once', () {
    List<ui.Paragraph> paint() => _drawnBy(
      (canvas) => paintVerticalText(
        canvas,
        dialogue,
        style: style,
        centerX: 20,
        top: 0,
        mainExtent: 600,
        naturalCellExtent: 24,
        setWord: paintFittedText,
      ),
    );

    final first = paint();

    expect(first, hasLength(3), reason: 'LIVENESS: the column painted');
    _expectTheSame(paint(), first, reason: 'a second paint');
  });

  // The span's measure has no picture to read — what it measured is a
  // number, the same however it laid its glyphs out — so it is read off
  // the source: no placer lays a glyph out on its own.
  test('⛔no placer lays a glyph out itself — the span\'s measure '
      'included', () {
    for (final path in [
      'lib/src/ui/text/dialogue_fit_paint.dart',
      'lib/src/ui/text/vertical_writing_text.dart',
      'lib/src/ui/timeline/dialogue_fit_text.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('laidOutGlyph('),
        reason: 'LIVENESS: $path sets its glyphs',
      );
      expect(
        source,
        isNot(contains('TextPainter(')),
        reason: '$path lays a glyph out of its own',
      );
    }
  });
}
