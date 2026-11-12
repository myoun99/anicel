import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/core/laid_whole.dart';

/// 🚨★★★THE NEWEST ASKED FOR IS LAID OFF SCREEN AND PUT UP WHOLE, the last
/// one up standing meanwhile ([LaidWhole]) — the one law of a shape dragged
/// (I-69-Q4ⓒ) and of a screen's picture under a box dragged
/// (a-float-in-hand-draws-the-frame-as-it-stands-Q2). What each holder does
/// with it is its own pins'; this is the law alone.
void main() {
  /// A holder laying what it is asked for as a piece of its own, and the
  /// pieces it began, in order.
  ({LaidWhole<String, ({String of})> pieces, List<String> begun}) aHolder() {
    final begun = <String>[];
    return (
      pieces: LaidWhole<String, ({String of})>(
        begin: (wanted) {
          begun.add(wanted);
          return (of: wanted);
        },
        holds: (laid, wanted) => laid.of == wanted,
      ),
      begun: begun,
    );
  }

  test('the first ask is begun at once', () {
    final (:pieces, :begun) = aHolder();

    expect(pieces.ask('a'), isTrue);

    expect(begun, ['a']);
    expect(pieces.laying, (of: 'a'));
    expect(pieces.shown, isNull, reason: 'nothing is up till it is whole');
  });

  test('🚨asked again while one is being laid, the newest waits — begun '
      'once the one being laid is whole, and the ones between never', () {
    final (:pieces, :begun) = aHolder();
    pieces.ask('a');

    expect(pieces.ask('b'), isFalse);
    expect(pieces.ask('c'), isFalse);
    expect(begun, ['a'], reason: 'one piece is laid at a time');

    expect(pieces.laid(), (of: 'a'));
    expect(pieces.shown, (of: 'a'), reason: 'up whole');
    expect(pieces.layTheNewest(), isTrue);

    expect(begun, ['a', 'c'], reason: 'the hand\'s newest, not the one between');
    expect(pieces.shown, (of: 'a'), reason: 'the last whole one stands');
  });

  test('what is up already is laid again for no one', () {
    final (:pieces, :begun) = aHolder();
    pieces
      ..ask('a')
      ..laid();

    expect(pieces.ask('a'), isFalse);
    expect(pieces.layTheNewest(), isFalse);

    expect(begun, ['a']);
  });

  test('asked back to what was up while another is laid, it is laid again '
      'once that one is whole — what is up by then is the other', () {
    final (:pieces, :begun) = aHolder();
    pieces
      ..ask('a')
      ..laid()
      ..ask('b')
      ..ask('a');

    pieces.laid();

    expect(pieces.shown, (of: 'b'));
    expect(pieces.layTheNewest(), isTrue, reason: 'b is up; a is asked');
    expect(begun, ['a', 'b', 'a']);
  });

  test('a piece that will never be whole leaves what was up standing, and '
      'the newest is begun next', () {
    final (:pieces, :begun) = aHolder();
    pieces
      ..ask('a')
      ..laid()
      ..ask('b');

    pieces.layingFailed();

    expect(pieces.shown, (of: 'a'));
    expect(pieces.laying, isNull);
    expect(pieces.layTheNewest(), isTrue);
    expect(begun, ['a', 'b', 'b']);
  });

  test('dropped, nothing is asked, laid or up', () {
    final (:pieces, :begun) = aHolder();
    pieces
      ..ask('a')
      ..laid()
      ..ask('b');

    pieces.drop();

    expect(pieces.wanted, isNull);
    expect(pieces.laying, isNull);
    expect(pieces.shown, isNull);
    expect(pieces.layTheNewest(), isFalse);
  });
}
