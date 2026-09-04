import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/pin_counts.dart';

/// 🚨THE COUNT NESTS, AND ZERO MEANS GONE.
///
/// Both playback caches pin slots by hand-counting a Map. The pair that
/// has to agree is retain's `?? 0` and release's remove-at-one: a release
/// that decremented to zero WITHOUT removing leaves the key present, and a
/// key that is present is pinned — an image the cache can never evict.
void main() {
  test('a slot nobody took is not pinned', () {
    final pins = PinCounts<String>();
    expect(pins.isPinned('a'), isFalse);
    expect(pins.keys, isEmpty);
  });

  test('one retain pins it, one release lets it go', () {
    final pins = PinCounts<String>();
    pins.retain('a');
    expect(pins.isPinned('a'), isTrue);
    pins.release('a');
    expect(pins.isPinned('a'), isFalse);
    expect(
      pins.keys,
      isEmpty,
      reason: 'a key left behind at zero is a slot pinned forever',
    );
  });

  test('two holders: the first release does NOT let it go', () {
    final pins = PinCounts<String>();
    pins.retain('a');
    pins.retain('a');
    pins.release('a');
    expect(pins.isPinned('a'), isTrue);
    pins.release('a');
    expect(pins.isPinned('a'), isFalse);
  });

  test('keys names every pinned slot, once', () {
    final pins = PinCounts<String>();
    pins.retain('a');
    pins.retain('a');
    pins.retain('b');
    expect(pins.keys.toSet(), {'a', 'b'});
  });

  test('releasing what was never retained asserts', () {
    final pins = PinCounts<String>();
    expect(
      () => pins.release('a'),
      throwsA(isA<AssertionError>()),
      reason: 'an unbalanced release is a caller bug, not a no-op',
    );
  });
}
