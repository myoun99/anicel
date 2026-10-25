import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/core/hashed_once.dart';

/// A value that counts how often it is hashed, and hashes as [hash] says —
/// so two values may share a hash and still differ.
class _Counted {
  _Counted(this.name, {required this.hash});

  final String name;
  final int hash;
  int hashes = 0;

  @override
  int get hashCode {
    hashes += 1;
    return hash;
  }

  @override
  bool operator ==(Object other) => other is _Counted && other.name == name;
}

void main() {
  test('a key is its value: equal values are one key, another value is '
      'another key', () {
    final a = HashedOnce(('glyph', 12.0, null));
    final again = HashedOnce(('glyph', 12.0, null));
    expect(a, again);
    expect(a.hashCode, again.hashCode);
    expect(a, isNot(HashedOnce(('glyph', 13.0, null))));
    expect({a: 1}[again], 1, reason: 'a map finds it by an equal key');
  });

  test('🔬the value is hashed ONCE, however often its key is asked', () {
    final value = _Counted('word', hash: 7);
    final key = HashedOnce(value);
    final map = <HashedOnce<_Counted>, int>{key: 1};
    map.remove(key);
    map[key] = 2;
    expect(map[key], 2);
    expect(value.hashes, 1);
  });

  test('two values that share a hash are still two keys', () {
    final one = HashedOnce(_Counted('one', hash: 1));
    final other = HashedOnce(_Counted('other', hash: 1));
    expect(one.hashCode, other.hashCode, reason: 'fixture: one hash');
    expect(one, isNot(other));
    expect({one: 1, other: 2}, hasLength(2));
  });
}
