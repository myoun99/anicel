@TestOn('vm')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/native_scratch.dart';

/// 🚨★★★THE BUFFER AND ITS LENGTH CANNOT COME APART.
///
/// The engine used to keep them as nineteen pairs of fields, with a helper
/// that returned only the pointer — so every caller carried its own
/// `if (len < need) len = need;`. A caller that forgets re-allocates every
/// call; one that updates the length alone hands the C a buffer smaller
/// than it was told, and that is a native crash rather than an exception.
///
/// ⚠️These run WITHOUT the native engine: the class is pure Dart over
/// calloc, so the allocation law is testable even where the engine's own
/// paths are not.
void main() {
  test('the first ask allocates, and the size is remembered', () {
    final scratch = NativeScratch<Uint8>((n) => calloc<Uint8>(n));
    addTearDown(scratch.release);

    expect(scratch.pointer, nullptr, reason: 'nothing is held before a use');
    expect(scratch.length, 0);

    final buffer = scratch.ensure(64);
    expect(buffer, isNot(nullptr));
    expect(scratch.length, 64);
    expect(scratch.pointer, buffer);
  });

  test('a smaller ask keeps the buffer it has', () {
    final scratch = NativeScratch<Uint8>((n) => calloc<Uint8>(n));
    addTearDown(scratch.release);

    final big = scratch.ensure(128);
    final small = scratch.ensure(8);
    expect(
      small,
      big,
      reason: 'scratch is reused across calls; shrinking buys nothing',
    );
    expect(
      scratch.length,
      128,
      reason: 'the length still says what the buffer really holds',
    );
  });

  test('a bigger ask grows it, and the length grows with it', () {
    final scratch = NativeScratch<Uint8>((n) => calloc<Uint8>(n));
    addTearDown(scratch.release);

    scratch.ensure(16);
    final grown = scratch.ensure(1024);
    expect(scratch.pointer, grown);
    expect(
      scratch.length,
      1024,
      reason: 'a length left behind is a buffer the C is told is bigger',
    );
    // The grown buffer really holds what it says: writing the last element
    // would be out of bounds if the allocation had not moved.
    grown.asTypedList(1024)[1023] = 7;
    expect(grown.asTypedList(1024)[1023], 7);
  });

  test('release forgets both, so the next ask allocates again', () {
    final scratch = NativeScratch<Uint8>((n) => calloc<Uint8>(n));
    addTearDown(scratch.release);

    scratch.ensure(32);
    scratch.release();
    expect(scratch.pointer, nullptr);
    expect(
      scratch.length,
      0,
      reason: 'a freed buffer that still claims a size is a use-after-free',
    );

    final again = scratch.ensure(32);
    expect(again, isNot(nullptr));
    expect(scratch.length, 32);
  });

  test('releasing twice is not a double free', () {
    final scratch = NativeScratch<Uint8>((n) => calloc<Uint8>(n));
    scratch.ensure(8);
    scratch.release();
    expect(scratch.release, returnsNormally);
  });

  test('grow carries the elements the caller asked to keep', () {
    final scratch = NativeScratch<Int32>((n) => calloc<Int32>(n));
    addTearDown(scratch.release);

    final first = scratch.ensure(4);
    first.asTypedList(4).setAll(0, [10, 20, 30, 40]);

    final grown = scratch.grow(
      8,
      keep: 3,
      copy: (from, to, elements) => to
          .asTypedList(elements)
          .setRange(0, elements, from.asTypedList(elements)),
    );
    expect(scratch.length, 8);
    expect(
      grown.asTypedList(3),
      [10, 20, 30],
      reason: 'a stack grown mid-walk must still hold what it was walking',
    );
  });

  test('grow keeps the buffer when it is already big enough', () {
    final scratch = NativeScratch<Int32>((n) => calloc<Int32>(n));
    addTearDown(scratch.release);

    final held = scratch.ensure(16);
    final same = scratch.grow(
      4,
      keep: 4,
      copy: (from, to, elements) => fail('nothing should be copied'),
    );
    expect(same, held);
    expect(scratch.length, 16);
  });
}
