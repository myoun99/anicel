import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// A native scratch buffer that remembers how big it is.
///
/// ⛔THE POINTER AND ITS LENGTH MOVE TOGETHER, and that is the whole
/// point. The engine kept nineteen pairs of fields that had to be updated
/// in step, and its `_ensureUint8` returned only the pointer — so every
/// caller carried `if (len < need) len = need;` of its own. A caller that
/// forgets re-allocates on every call while reporting the old size; one
/// that updates the length without the pointer hands the C a buffer
/// smaller than it was told, which is a native crash, not an exception.
///
/// ⚠️[allocate] is written per field because `calloc<T>()` needs the size
/// at compile time — a generic allocation is not something FFI can do.
class NativeScratch<T extends NativeType> {
  NativeScratch(this.allocate);

  /// Allocates [count] elements. Always `(n) => calloc<Something>(n)`.
  final Pointer<T> Function(int count) allocate;

  Pointer<T> _pointer = nullptr;
  int _length = 0;

  /// The buffer, grown to hold [count] elements when it has to be.
  ///
  /// ⚠️GROWS ONLY. A smaller ask keeps the buffer it has: this is scratch
  /// reused across calls, and shrinking would trade an allocation for
  /// nothing.
  Pointer<T> ensure(int count) {
    if (_length >= count) {
      return _pointer;
    }
    release();
    _pointer = allocate(count);
    _length = count;
    return _pointer;
  }

  /// The buffer as it stands — `nullptr` before the first [ensure].
  Pointer<T> get pointer => _pointer;

  /// How many elements it holds.
  int get length => _length;

  /// Grows to [count] elements, CARRYING the first [keep] of them across.
  ///
  /// ⛔[ensure] throws the old bytes away, which is right for scratch that
  /// is refilled every call. A buffer being grown MID-USE — a stack the
  /// fill is still walking — has to keep what it holds, and [copy] is how
  /// the caller says which elements those are.
  Pointer<T> grow(
    int count, {
    required int keep,
    required void Function(Pointer<T> from, Pointer<T> to, int elements) copy,
  }) {
    if (_length >= count) {
      return _pointer;
    }
    final grown = allocate(count);
    if (keep > 0 && _pointer != nullptr) {
      copy(_pointer, grown, keep);
    }
    release();
    _pointer = grown;
    _length = count;
    return _pointer;
  }

  void release() {
    if (_pointer != nullptr) {
      calloc.free(_pointer);
      _pointer = nullptr;
      _length = 0;
    }
  }
}

/// [bytes] copied into native memory for the length of ONE call: [body]
/// gets the pointer, and the block is freed whatever [body] does. The
/// copy-in scope every FFI door that takes a Dart byte list needs (a
/// decode, a compress, a decompress, a video frame, a JPEG input) — it
/// was written out at each of them, and two of them disagreed on the
/// allocator with no reason on the disagreeing side.
///
/// malloc, not calloc: the copy below overwrites every byte — the
/// calloc memset doubled an 8000² fill stamp's 256MB upload traffic.
///
/// ⛔Uint8 only. `malloc<T>()` needs the element type at compile time, so
/// a version generic over it cannot be written in Dart (the same limit
/// [NativeScratch.allocate] states); the Float, Int16 and Double copies
/// stay where they are until one of those types has three sites.
R withNativeBytes<R>(Uint8List bytes, R Function(Pointer<Uint8> data) body) {
  final data = malloc<Uint8>(bytes.length);
  try {
    data.asTypedList(bytes.length).setAll(0, bytes);
    return body(data);
  } finally {
    malloc.free(data);
  }
}
