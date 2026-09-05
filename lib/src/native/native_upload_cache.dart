import 'dart:collection';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Native copies of Dart buffers, keyed by the SOURCE's identity, so a
/// kernel that is handed the same list again reads the same pointer with
/// no copy. One algorithm, two instances: the engine's stamp bytes and
/// its mask alphas each used to write this LRU out.
///
/// Small LRU: a hit moves the entry to the front; a miss copies once.
///
/// Entry-count AND byte-budgeted (R19-8K): a full-canvas fill stamp at
/// 8000² is 256MB — four of those resident was a 1GB RSS bomb. The
/// newest entry always survives even when it alone exceeds the budget.
final class NativeUploadCache<L extends TypedData> {
  NativeUploadCache({required this.entryCap, required this.byteBudget});

  /// Entries resident at most (the newest is never evicted).
  final int entryCap;

  /// Bytes resident at most, the newest entry excepted.
  final int byteBudget;

  final LinkedHashMap<Object, Pointer<Uint8>> _uploads =
      LinkedHashMap.identity();
  final Map<Object, int> _sizes = HashMap.identity();
  int _bytes = 0;

  int get entryCount => _uploads.length;

  int get residentBytes => _bytes;

  /// The native copy of [data], uploaded once.
  Pointer<Uint8> upload(L data) {
    final cached = _uploads.remove(data);
    if (cached != null) {
      _uploads[data] = cached;
      return cached;
    }
    final length = data.lengthInBytes;
    // malloc, not calloc: the copy below overwrites every byte — the
    // calloc memset doubled an 8000² fill stamp's 256MB upload traffic.
    final pointer = malloc<Uint8>(length);
    pointer
        .asTypedList(length)
        .setAll(0, data.buffer.asUint8List(data.offsetInBytes, length));
    _uploads[data] = pointer;
    _sizes[data] = length;
    _bytes += length;
    while (_uploads.length > 1 &&
        (_uploads.length > entryCap || _bytes > byteBudget)) {
      final oldest = _uploads.keys.first;
      malloc.free(_uploads.remove(oldest)!);
      _bytes -= _sizes.remove(oldest)!;
    }
    return pointer;
  }
}
