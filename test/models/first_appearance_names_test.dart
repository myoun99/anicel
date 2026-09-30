import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/first_appearance_names.dart';

/// 🗣️I-18-Q1 (유저): 「그림마다 번호 — 다시 나오는 블록은 같은 번호」 — the
/// numbering law the frames and the cuts share.
void main() {
  test('a thing shown again reads the number it took the first time: '
      'a b a c from 5 is 5 6 5 7', () {
    const shown = ['a', 'b', 'a', 'c'];
    final names = namesByFirstAppearance(shown, from: 5);

    expect(names, {'a': '5', 'b': '6', 'c': '7'});
    expect(
      [for (final thing in shown) names[thing]],
      ['5', '6', '5', '7'],
      reason: 'what the four blocks read',
    );
  });

  test('nothing shown names nothing', () {
    expect(namesByFirstAppearance(const <String>[], from: 1), isEmpty);
  });

  test('things shown once each count straight up — the cuts\' case', () {
    expect(namesByFirstAppearance(const ['x', 'y', 'z'], from: 1), {
      'x': '1',
      'y': '2',
      'z': '3',
    });
  });

  test('the count starts where it is told, zero included', () {
    expect(namesByFirstAppearance(const ['p', 'q', 'p'], from: 0), {
      'p': '0',
      'q': '1',
    });
  });
}
