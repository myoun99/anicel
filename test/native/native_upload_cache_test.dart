import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/native_upload_cache.dart';

/// The identity-keyed LRU that hands kernels a native copy of a Dart
/// buffer: a hit is the same pointer, a miss copies once, and the two
/// limits (entries, bytes) evict from the OLDEST end — never the entry
/// just uploaded, even when it alone is over the budget. Neither of the
/// two instances the engine used to hand-roll had a test.
void main() {
  Uint8List bytes(int length, int fill) =>
      Uint8List(length)..fillRange(0, length, fill);

  test('a hit is the same pointer, and the bytes are the source bytes', () {
    final cache = NativeUploadCache<Uint8List>(
      entryCap: 4,
      byteBudget: 1 << 20,
    );
    final source = bytes(16, 0xAB);

    final first = cache.upload(source);
    final second = cache.upload(source);

    expect(second, first, reason: 'identity-keyed: the same list, once');
    expect(first.asTypedList(16), source);
    expect(cache.entryCount, 1);
    expect(cache.residentBytes, 16);
  });

  test('a Float64List uploads its bytes, not its element count', () {
    final cache = NativeUploadCache<Float64List>(
      entryCap: 8,
      byteBudget: 1 << 20,
    );
    final alphas = Float64List.fromList([0.25, 0.5, 1.0]);

    final pointer = cache.upload(alphas);

    expect(pointer.cast<Double>().asTypedList(3), alphas);
    expect(cache.residentBytes, 24);
  });

  test('the entry cap evicts the least recently USED, not the oldest '
      'uploaded', () {
    final cache = NativeUploadCache<Uint8List>(
      entryCap: 2,
      byteBudget: 1 << 20,
    );
    final a = bytes(4, 1);
    final b = bytes(4, 2);
    final c = bytes(4, 3);

    final pointerA = cache.upload(a);
    cache.upload(b);
    // Touch a: b is now the least recently used.
    expect(cache.upload(a), pointerA);
    cache.upload(c);

    expect(cache.entryCount, 2);
    expect(cache.upload(a), pointerA, reason: 'a survived, it was touched');
    expect(cache.residentBytes, 8);
  });

  test('the byte budget evicts from the oldest end', () {
    final cache = NativeUploadCache<Uint8List>(entryCap: 8, byteBudget: 10);
    final a = bytes(4, 1);
    final b = bytes(4, 2);
    final c = bytes(4, 3);

    cache.upload(a);
    cache.upload(b);
    expect(cache.residentBytes, 8, reason: 'both fit');
    final pointerC = cache.upload(c);

    expect(cache.residentBytes, 8, reason: 'a is gone, b and c stay');
    expect(cache.entryCount, 2);
    expect(cache.upload(c), pointerC);
  });

  test('the newest entry survives even when it alone exceeds the budget', () {
    final cache = NativeUploadCache<Uint8List>(entryCap: 4, byteBudget: 10);
    final small = bytes(4, 1);
    final huge = bytes(64, 2);

    cache.upload(small);
    final pointer = cache.upload(huge);

    expect(cache.entryCount, 1, reason: 'the budget evicted the small one');
    expect(cache.residentBytes, 64);
    expect(cache.upload(huge), pointer, reason: 'and kept the huge one');
  });
}
