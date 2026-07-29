import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/conte/conte_fonts.dart';
import 'package:anicel/src/ui/conte/conte_page_painter.dart';

/// The conte's ONE wrap ([conteWrappedLines]): the panel's own TextPainter
/// layout read back line by line, printed verbatim by the PDF. These pins
/// run in the test font (every glyph 1em wide), which makes the break
/// positions arithmetic: fontSize 10 and maxWidth 60 is six glyphs a line.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const style = TextStyle(fontSize: 10);

  test('spaces break the line and the break eats the space', () {
    expect(conteWrappedLines('aaa bbb ccc', style, 60), ['aaa', 'bbb', 'ccc']);
  });

  test('spaceless runs (CJK) break anywhere, at the width', () {
    expect(conteWrappedLines('ああああああああ', style, 60), [
      'ああああああ',
      'ああ',
    ]);
  });

  test('hard newlines are their own breaks, blank lines included', () {
    expect(conteWrappedLines('a\nb', style, 200), ['a', 'b']);
    expect(conteWrappedLines('a\n\nb', style, 200), ['a', '', 'b']);
  });

  test('empty text wraps to no lines at all', () {
    expect(conteWrappedLines('', style, 200), isEmpty);
  });

  test('every character survives the wrap — lines re-join to the text, '
      'whitespace aside', () {
    const text = 'セリフが 長い とき、それは おりかえす。';
    final lines = conteWrappedLines(text, style, 70);
    expect(lines.length, greaterThan(1));
    expect(
      lines.join().replaceAll(' ', ''),
      text.replaceAll(' ', ''),
      reason: 'a wrap may eat break whitespace, never writing',
    );
  });

  test('the shared style carries the embedded faces — the wrap\'s '
      'precondition, and the panel\'s type', () {
    final resolved = conteTextStyle(9, bold: true);
    expect(resolved.fontFamily, conteJpFontFamily);
    expect(resolved.fontFamilyFallback, [conteKrFontFamily]);
    expect(resolved.fontWeight, FontWeight.w700);
    expect(resolved.height, 1.25);
  });
}
