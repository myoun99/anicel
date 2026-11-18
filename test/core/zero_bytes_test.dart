import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/core/zero_bytes.dart';

/// `zeroBytes` makes every byte it is handed 0 — however many, past the
/// zeros it copies from — and not one byte beside them.
void main() {
  for (final length in [0, 1, 65535, 65536, 65537, 200003]) {
    test('$length bytes, each 0', () {
      final bytes = Uint8List(length)..setAll(0, List.filled(length, 0xab));

      zeroBytes(bytes);

      expect(bytes.every((byte) => byte == 0), isTrue);
    });
  }

  test('a view in the middle of its buffer, and nothing beside it', () {
    final whole = Uint8List(70000)..setAll(0, List.filled(70000, 0xab));

    zeroBytes(Uint8List.sublistView(whole, 3, 69990));

    expect(whole.sublist(0, 3), [0xab, 0xab, 0xab]);
    expect(whole.sublist(3, 69990).every((byte) => byte == 0), isTrue);
    expect(whole.sublist(69990), List.filled(10, 0xab));
  });
}
