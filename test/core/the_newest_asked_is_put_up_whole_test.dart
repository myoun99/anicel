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

  // ↩️Till 2026-11-12 the other was put up and what was up laid again — a
  // frame of a want given up (F-377).
  test('🚨asked back to what is up while another is laid, the other is let '
      'go of unseen once it is whole, and nothing is laid again', () {
    final (:pieces, :begun) = aHolder();
    pieces
      ..ask('a')
      ..laid()
      ..ask('b')
      ..ask('a');

    expect(pieces.laid(), isNull, reason: 'b never comes up');

    expect(pieces.shown, (of: 'a'));
    expect(pieces.behind, isFalse);
    expect(pieces.layTheNewest(), isFalse);
    expect(begun, ['a', 'b']);
  });

  test('behind: what is up is not of what is asked for, and nothing is '
      'being laid', () {
    final (:pieces, begun: _) = aHolder();
    expect(pieces.behind, isFalse, reason: 'nothing is asked for');
    pieces.ask('a');
    expect(pieces.behind, isFalse, reason: 'it is being laid');
    pieces
      ..ask('b')
      ..laid();

    expect(pieces.behind, isTrue, reason: 'a is up, b is asked for');
    pieces.layTheNewest();
    expect(pieces.behind, isFalse);
  });

  test('a piece that will never be whole leaves what was up standing, and '
      'says whether another was asked for meanwhile — what failed is not '
      'begun again of itself', () {
    final (:pieces, :begun) = aHolder();
    pieces
      ..ask('a')
      ..laid()
      ..ask('b');

    expect(pieces.layingGivenUp(), isFalse, reason: 'b is the newest');
    expect(pieces.shown, (of: 'a'));
    expect(pieces.laying, isNull);

    pieces
      ..ask('c')
      ..ask('d');
    expect(begun, ['a', 'b', 'c']);
    expect(pieces.layingGivenUp(), isTrue, reason: 'd was asked meanwhile');
    expect(pieces.layTheNewest(), isTrue);
    expect(begun, ['a', 'b', 'c', 'd']);
  });

  test('🚨a piece stood up unlaid while another is laid is what is up and '
      'asked for: the other is let go of unseen once whole', () {
    final (:pieces, :begun) = aHolder();
    pieces
      ..ask('a')
      ..laid()
      ..ask('b');

    pieces.stand((of: 'c'), 'c');

    expect(pieces.shown, (of: 'c'));
    expect(pieces.wanted, 'c');
    expect(pieces.laid(), isNull, reason: 'b was given up for c');
    expect(pieces.shown, (of: 'c'));
    expect(pieces.layTheNewest(), isFalse, reason: 'c is up');
    expect(begun, ['a', 'b'], reason: 'what stands is not laid');
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
