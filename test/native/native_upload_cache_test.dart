import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/native_upload_cache.dart';

import '../helpers/collect_garbage.dart';

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

  test('🚨the cache does not keep a source alive, and a source nobody '
      'holds takes its native copy with it (C-ipad-crash)', () async {
    final cache = NativeUploadCache<Uint8List>(
      entryCap: 4,
      byteBudget: 1 << 20,
    );
    WeakReference<Uint8List> uploadAndLetGo() {
      final oneShot = bytes(64, 1);
      cache.upload(oneShot);
      return WeakReference(oneShot);
    }

    final gone = uploadAndLetGo();
    final kept = bytes(32, 2);
    final keptPointer = cache.upload(kept);
    expect(cache.residentBytes, 96, reason: 'fixture: both copies resident');

    await collectGarbageUntil(() => cache.residentBytes == 32);

    expect(gone.target, isNull, reason: 'the cache must not pin its source');
    expect(cache.residentBytes, 32, reason: 'the dead source took its copy');
    expect(cache.entryCount, 1);
    expect(cache.upload(kept), keptPointer, reason: 'a live one still hits');
  });

  test('a source the budget evicted uploads again when it comes back — '
      'a fresh copy, never the freed one', () {
    final cache = NativeUploadCache<Uint8List>(
      entryCap: 2,
      byteBudget: 1 << 20,
    );
    final a = bytes(4, 1);
    final b = bytes(4, 2);
    final c = bytes(4, 3);

    cache.upload(a);
    cache.upload(b);
    cache.upload(c);
    expect(cache.entryCount, 2, reason: 'fixture: the cap evicted a');

    final again = cache.upload(a);

    expect(cache.entryCount, 2, reason: 'a is a miss: it evicts b');
    expect(cache.residentBytes, 8);
    expect(again.asTypedList(4), a, reason: 'and reads its own bytes');
  });

  test('lowering the byte budget evicts at once, from the least recently '
      'used end — the newest still survives', () {
    final cache = NativeUploadCache<Uint8List>(
      entryCap: 8,
      byteBudget: 1 << 20,
    );
    final a = bytes(4, 1);
    final b = bytes(4, 2);
    final c = bytes(4, 3);
    cache
      ..upload(a)
      ..upload(b)
      ..upload(c);
    expect(cache.residentBytes, 12);

    cache.byteBudget = 8;
    expect(cache.residentBytes, 8, reason: 'a, the oldest, went');

    cache.byteBudget = 0;
    expect(cache.entryCount, 1, reason: 'the newest always survives');
    expect([a, b, c], hasLength(3));
  });
}
