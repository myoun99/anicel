import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/let_go_wanted_latest.dart';

/// [letGoLeastRecentlyUsed] — the order a budget lets go by, for a cache no
/// step wants anything of (card storyboard-thumbnails-let-go-by-the-one-
/// order): the least recently used first, until what is held is at or under
/// the line, and never the newest — what was just asked for.
void main() {
  /// Lets go among [bytes] (its keys oldest first) down to [maxBytes]:
  /// what went, in the order it went, and the answer.
  ({List<String> gone, bool fits}) run(
    Map<String, int> bytes, {
    required int maxBytes,
  }) {
    final gone = <String>[];
    final fits = letGoLeastRecentlyUsed(
      usedOldestFirst: bytes.keys,
      heldBytes: bytes.values.fold(0, (sum, each) => sum + each),
      maxBytes: maxBytes,
      bytesOf: (key) => bytes[key]!,
      letGo: gone.add,
    );
    return (gone: gone, fits: fits);
  }

  test('the least recently used goes first — not the largest — and only '
      'until what is held is at the line', () {
    // 65 held, the line at 25: the oldest two make it 10. Largest first
    // would have let go of `b` alone.
    final result = run({'a': 5, 'b': 50, 'c': 5, 'd': 5}, maxBytes: 25);

    expect(result.gone, ['a', 'b']);
    expect(result.fits, isTrue);
  });

  test('AT the line is under it: what got there stops the letting go', () {
    final result = run({'a': 10, 'b': 10, 'c': 10, 'd': 10}, maxBytes: 20);

    expect(result.gone, ['a', 'b'], reason: '20 held is the line, not past');
    expect(result.fits, isTrue);
  });

  test('the newest never goes — however much it holds — and the answer says '
      'what is left is still past the line', () {
    final result = run({'a': 10, 'just asked': 100}, maxBytes: 50);

    expect(result.gone, ['a']);
    expect(result.fits, isFalse);
  });

  test('under the line already, nothing goes; a cache of one keeps it', () {
    final under = run({'a': 10, 'b': 10}, maxBytes: 40);
    expect(under.gone, isEmpty);
    expect(under.fits, isTrue);

    final one = run({'only': 100}, maxBytes: 10);
    expect(one.gone, isEmpty, reason: 'the one entry is the newest');
    expect(one.fits, isFalse);

    final none = run({}, maxBytes: 0);
    expect(none.gone, isEmpty);
    expect(none.fits, isTrue);
  });
}
