import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/services/cel_text_edits.dart';
import 'package:flutter_test/flutter_test.dart';

/// R9-rest (the text tool): the edits a text's letters take — typing, and
/// changing how letters are set — and the one rule that says which letters a
/// setting speaks for.
void main() {
  const plain = TextLetterStyle();
  const red = TextLetterStyle(color: 0xFFFF0000);
  const big = TextLetterStyle(fontSize: 96);
  const next = TextLetterStyle(fontFamily: 'Next', fontSize: 7);

  CelTextContent said(List<CelTextSpan> spans) => CelTextContent(
    spans: spans,
    anchor: CanvasPoint(x: 3, y: 4),
    wrapWidth: 120,
    rotationDegrees: 15,
  );

  CelTextSpan run(String words, [TextLetterStyle style = plain]) =>
      CelTextSpan(text: words, style: style);

  /// 「ab」 plain, 「cd」 red, 「ef」 big.
  final three = said([run('ab'), run('cd', red), run('ef', big)]);

  CelTextContent typed(
    CelTextContent into,
    int start,
    int end,
    String letters,
  ) => celTextWithLetters(
    into,
    range: (start: start, end: end),
    letters: letters,
    nextLetterStyle: next,
  );

  group('typing', () {
    test('a letter typed between letters wears the one BEFORE it', () {
      expect(
        typed(three, 2, 2, 'X').spans,
        [run('abX'), run('cd', red), run('ef', big)],
        reason: 'at the seam of two runs: the run that ends there',
      );
      expect(typed(three, 3, 3, 'X').spans, [
        run('ab'),
        run('cXd', red),
        run('ef', big),
      ]);
      expect(typed(three, 6, 6, 'X').spans, [
        run('ab'),
        run('cd', red),
        run('efX', big),
      ]);
    });

    test('at the very start it wears the first letter', () {
      expect(
        typed(said([run('cd', red), run('ef', big)]), 0, 0, 'X').spans,
        [run('Xcd', red), run('ef', big)],
      );
    });

    test('over a selection it wears the FIRST letter it replaces', () {
      expect(
        typed(three, 3, 5, 'XY').spans,
        [run('ab'), run('cXY', red), run('f', big)],
        reason: 'from inside the red run into the big one',
      );
      expect(
        typed(three, 2, 4, 'X').spans,
        [run('ab'), run('X', red), run('ef', big)],
        reason: 'a whole run replaced: ITS style, not the run before it',
      );
      expect(
        typed(three, 0, 6, 'X').spans,
        [run('X')],
        reason: 'everything replaced: the first letter\'s',
      );
    });

    test('🚨only a text with NO letters wears the style of the next '
        'letter', () {
      expect(typed(said(const []), 0, 0, 'hi').spans, [run('hi', next)]);
      expect(
        typed(three, 0, 0, 'X').spans.first.style,
        plain,
        reason: 'a text with letters never reads it',
      );
    });

    test('letters taken out leave their neighbours — and two runs set '
        'alike meet as one', () {
      expect(typed(three, 1, 3, '').spans, [
        run('a'),
        run('d', red),
        run('ef', big),
      ]);
      expect(
        typed(said([run('ab'), run('cd', red), run('ef')]), 2, 4, '').spans,
        [run('abef')],
      );
      expect(typed(three, 0, 6, '').isEmpty, isTrue);
    });

    test('nothing but the letters changes', () {
      final after = typed(three, 2, 2, 'X');

      expect(after.anchor, three.anchor);
      expect(after.wrapWidth, 120);
      expect(after.rotationDegrees, 15);
    });

    test('a place outside the text is refused', () {
      expect(() => typed(three, 0, 7, 'X'), throwsRangeError);
      expect(() => typed(three, 4, 3, 'X'), throwsRangeError);
      expect(() => typed(three, -1, 2, 'X'), throwsRangeError);
    });
  });

  group('setting letters', () {
    CelTextContent coloured(CelTextContent content, int start, int end) =>
        celTextRestyled(
          content,
          range: (start: start, end: end),
          change: (style) => style.copyWith(color: 0xFF0000FF),
        );

    test('reaches the letters of the range and no others — a run is cut '
        'where the range starts and ends', () {
      expect(coloured(three, 1, 5).spans, [
        run('a'),
        // 「b」 and 「cd」 are now set alike, and meet as one run.
        run('bcd', const TextLetterStyle(color: 0xFF0000FF)),
        run('e', const TextLetterStyle(fontSize: 96, color: 0xFF0000FF)),
        run('f', big),
      ]);
    });

    test('🚨every letter keeps what the change leaves alone: a text in two '
        'sizes given one colour is still in two sizes', () {
      final after = coloured(three, 0, 6);

      expect(after.spans, [
        run('abcd', const TextLetterStyle(color: 0xFF0000FF)),
        run('ef', const TextLetterStyle(fontSize: 96, color: 0xFF0000FF)),
      ]);
    });

    test('a change that changes nothing leaves the content as it was', () {
      expect(
        celTextRestyled(
          three,
          range: (start: 1, end: 5),
          change: (style) => style,
        ),
        three,
      );
    });

    test('an empty range reaches nothing', () {
      expect(coloured(three, 3, 3), three);
    });

    test('a place outside the text is refused', () {
      expect(() => coloured(three, 0, 7), throwsRangeError);
      expect(() => coloured(three, 4, 3), throwsRangeError);
    });
  });

  group('🚨the letters a setting speaks for', () {
    test('the selected letters', () {
      expect(
        celTextLettersSpokenFor(three, selectionStart: 1, selectionEnd: 4),
        (start: 1, end: 4),
      );
    });

    test('a selection dragged backwards is the same letters', () {
      expect(
        celTextLettersSpokenFor(three, selectionStart: 4, selectionEnd: 1),
        (start: 1, end: 4),
      );
    });

    test('with none selected — a caret alone, wherever it stands — every '
        'letter of the text', () {
      for (final caret in [0, 3, 6]) {
        expect(
          celTextLettersSpokenFor(
            three,
            selectionStart: caret,
            selectionEnd: caret,
          ),
          (start: 0, end: 6),
          reason: 'the caret at $caret',
        );
      }
    });

    test('how those letters are set: one style a run, in reading order', () {
      expect(celTextStylesOf(three, (start: 0, end: 6)), [plain, red, big]);
      expect(celTextStylesOf(three, (start: 2, end: 4)), [red]);
      expect(celTextStylesOf(three, (start: 1, end: 3)), [plain, red]);
      expect(celTextStylesOf(three, (start: 3, end: 3)), isEmpty);
      expect(
        () => celTextStylesOf(three, (start: 0, end: 7)),
        throwsRangeError,
      );
    });
  });

  group('the edit a keyboard made, read back from the text it left', () {
    test('a letter typed', () {
      expect(textReplacementBetween('abc', 'abXc', caretAfter: 3), (
        range: (start: 2, end: 2),
        letters: 'X',
      ));
    });

    test('a letter taken out', () {
      expect(textReplacementBetween('abc', 'ac', caretAfter: 1), (
        range: (start: 1, end: 2),
        letters: '',
      ));
    });

    test('a selection typed over', () {
      expect(textReplacementBetween('abcdef', 'aXYf', caretAfter: 3), (
        range: (start: 1, end: 5),
        letters: 'XY',
      ));
    });

    test('🚨typed into a run of the same letter, the new one is the one AT '
        'the caret', () {
      expect(textReplacementBetween('aaa', 'aaaa', caretAfter: 1), (
        range: (start: 0, end: 0),
        letters: 'a',
      ));
      expect(textReplacementBetween('aaa', 'aaaa', caretAfter: 2), (
        range: (start: 1, end: 1),
        letters: 'a',
      ));
      expect(textReplacementBetween('aaa', 'aaaa', caretAfter: 4), (
        range: (start: 3, end: 3),
        letters: 'a',
      ));
    });

    test('taken out of a run of the same letter, it is the one the caret '
        'is left at', () {
      expect(textReplacementBetween('aaa', 'aa', caretAfter: 0), (
        range: (start: 0, end: 1),
        letters: '',
      ));
      expect(textReplacementBetween('aaa', 'aa', caretAfter: 2), (
        range: (start: 2, end: 3),
        letters: '',
      ));
    });

    test('with no caret to go by, the tail is matched as far as it goes', () {
      expect(textReplacementBetween('aaa', 'aaaa'), (
        range: (start: 0, end: 0),
        letters: 'a',
      ));
      expect(textReplacementBetween('abc', 'abXc'), (
        range: (start: 2, end: 2),
        letters: 'X',
      ));
    });

    test('a text left as it was is no edit', () {
      expect(textReplacementBetween('abc', 'abc', caretAfter: 1), (
        range: (start: 1, end: 1),
        letters: '',
      ));
    });

    test('everything replaced', () {
      expect(textReplacementBetween('abc', 'xyz', caretAfter: 3), (
        range: (start: 0, end: 3),
        letters: 'xyz',
      ));
      expect(textReplacementBetween('', 'hi', caretAfter: 2), (
        range: (start: 0, end: 0),
        letters: 'hi',
      ));
      expect(textReplacementBetween('hi', '', caretAfter: 0), (
        range: (start: 0, end: 2),
        letters: '',
      ));
    });

    test('the edit read back, made again, gives the text the keyboard '
        'left', () {
      const cases = [
        ('hello world', 'hello brave world', 11),
        ('hello world', 'held', 3),
        ('aXbXc', 'aXc', 2),
        ('한글', '한그', 2),
        ('ab', 'ab\n', 3),
      ];
      for (final (before, after, caret) in cases) {
        final edit = textReplacementBetween(before, after, caretAfter: caret);

        expect(
          before.replaceRange(
            edit.range.start,
            edit.range.end,
            edit.letters,
          ),
          after,
          reason: '「$before」 → 「$after」',
        );
      }
    });
  });
}
