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

  test('no name prints the in-between mark — ONE filled dot for both of '
      'its uses (F-149)', () {
    // 🗣️유저 2026-09-16: 「일단 이름 없는 기본상태를 속이 찬 동그라미로
    // 통일적용 … 추후 두번째 중간나누기 마크(속이 빈)를 활용할지도
    // 모르겠지만 당장은 제거」. The GLYPH is pinned here by value — every
    // other test asks the constant, so this is the one place that says
    // what the constant is.
    expect(inbetweenMark, '●');
    expect(
      unnamedDrawingMark,
      inbetweenMark,
      reason: 'the unnamed drawing prints the in-between mark itself',
    );
    expect(celNumberOrMark('A1'), 'A1');
    expect(celNumberOrMark(null), unnamedDrawingMark);
    expect(celNumberOrMark('   '), unnamedDrawingMark);
  });
}
