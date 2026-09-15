import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';

/// ONE ANSWER TO 「DOES THIS DRAWING HAVE A NAME」 (C-save-percent).
///
/// [Frame.celNumber] answered it for the sheet and the cel export, and seven
/// places on screen answered it again with `name.isEmpty` — so a name of
/// spaces printed as spaces there and as the mark on the sheet. A painter
/// holds a name rather than a frame, so the answer is a function of the
/// name; these pins say what it answers.
void main() {
  test('a name prints trimmed; a blank one is no name', () {
    expect(celNumberOf('12'), '12');
    expect(celNumberOf(' 12 '), '12');
    expect(celNumberOf(null), isNull);
    expect(celNumberOf(''), isNull);
    expect(celNumberOf(' \t'), isNull);
  });

  test("no name prints the mark — the sheet's ○", () {
    expect(unnamedDrawingMark, '○');
    expect(celNumberOrMark('A1'), 'A1');
    expect(celNumberOrMark(null), unnamedDrawingMark);
    expect(celNumberOrMark('   '), unnamedDrawingMark);
  });
}
