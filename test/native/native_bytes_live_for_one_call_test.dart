@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/native_scratch.dart';

/// The copy-in scope every byte-taking FFI door shares: the body sees the
/// bytes, its answer comes back, and the block is gone whatever happened.
///
/// ⚠️These run WITHOUT the native engine: the scope is pure Dart over
/// malloc, so the law is testable even where the engine's own paths are
/// not.
void main() {
  test('the body reads exactly the bytes it was handed', () {
    final bytes = Uint8List.fromList([1, 2, 3, 250, 255]);
    final seen = withNativeBytes(
      bytes,
      (data) => Uint8List.fromList(data.asTypedList(bytes.length)),
    );
    expect(seen, bytes);
  });

  test('the body\'s answer is the call\'s answer', () {
    expect(withNativeBytes(Uint8List(4), (data) => data != nullptr), isTrue);
    expect(withNativeBytes(Uint8List(4), (_) => 'done'), 'done');
  });

  test('a throwing body still propagates, after the block is released', () {
    Pointer<Uint8>? handed;
    expect(
      () => withNativeBytes(Uint8List(8), (data) {
        handed = data;
        throw StateError('inside');
      }),
      throwsStateError,
    );
    expect(handed, isNot(nullptr));
  });

  test('a fresh call may reuse the address, never the old bytes', () {
    // The block is freed on the way out, so the next call sees whatever
    // it copied in — not what the previous body wrote.
    withNativeBytes(Uint8List.fromList([9, 9, 9]), (data) {
      data.asTypedList(3).fillRange(0, 3, 7);
      return null;
    });
    final again = withNativeBytes(
      Uint8List.fromList([1, 2, 3]),
      (data) => Uint8List.fromList(data.asTypedList(3)),
    );
    expect(again, [1, 2, 3]);
  });
}
