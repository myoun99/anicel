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
///
/// 🚨THE SOURCE IS HELD WEAKLY, and its copy goes when it does
/// (2026-09-11, C-ipad-crash). The keys were a `LinkedHashMap.identity()`,
/// and a map holds its keys: every buffer ever uploaded stayed alive in
/// Dart until the LRU pushed it out, next to its native copy — twice the
/// bytes, the Dart half counted by nobody. A transform uploads one-shot
/// buffers (the lifted pixels, the resampled result), so a whole-picture
/// transform left the budget's worth resident TWICE after it had landed.
/// An entry now lives exactly as long as somebody can still hand the same
/// list back; the budget caps what the live ones may keep.
final class NativeUploadCache<L extends TypedData> {
  NativeUploadCache({required this.entryCap, required int byteBudget})
    : _byteBudget = byteBudget;

  /// Entries resident at most (the newest is never evicted).
  final int entryCap;

  /// Bytes resident at most, the newest entry excepted. Lowered, it evicts
  /// at once — the memory tab's allowance moves it
  /// ([CacheBudgets.nativeUploads]).
  int get byteBudget => _byteBudget;

  set byteBudget(int value) {
    _byteBudget = value;
    _evictBeyondLimits();
  }

  int _byteBudget;

  final Expando<_Upload> _bySource = Expando<_Upload>('nativeUploads');
  final LinkedHashSet<_Upload> _recency = LinkedHashSet<_Upload>.identity();
  late final Finalizer<_Upload> _sourceGone = Finalizer<_Upload>(_free);
  int _bytes = 0;

  int get entryCount => _recency.length;

  int get residentBytes => _bytes;

  /// The native copy of [data], uploaded once.
  ///
  /// ⚠️Valid while [data] is reachable — use it in the same synchronous
  /// stretch that holds the list. A finalizer runs from the event loop, so
  /// it can never free a copy in the middle of a kernel call.
  Pointer<Uint8> upload(L data) {
    final cached = _bySource[data];
    if (cached != null && cached.resident) {
      _recency
        ..remove(cached)
        ..add(cached);
      return cached.pointer;
    }
    final length = data.lengthInBytes;
    // malloc, not calloc: the copy below overwrites every byte — the
    // calloc memset doubled an 8000² fill stamp's 256MB upload traffic.
    final pointer = malloc<Uint8>(length);
    pointer
        .asTypedList(length)
        .setAll(0, data.buffer.asUint8List(data.offsetInBytes, length));
    final entry = _Upload(pointer, length);
    _bySource[data] = entry;
    _sourceGone.attach(data, entry, detach: entry);
    _recency.add(entry);
    _bytes += length;
    _evictBeyondLimits();
    return pointer;
  }

  /// Frees from the least recently used end until both limits hold — the
  /// newest entry always survives.
  void _evictBeyondLimits() {
    while (_recency.length > 1 &&
        (_recency.length > entryCap || _bytes > _byteBudget)) {
      _free(_recency.first);
    }
  }

  /// Frees [entry]'s copy ONCE: the budget evicted it, or its source was
  /// collected — whichever comes first, and the other finds it gone.
  void _free(_Upload entry) {
    if (!entry.resident) {
      return;
    }
    entry.resident = false;
    _recency.remove(entry);
    _sourceGone.detach(entry);
    malloc.free(entry.pointer);
    _bytes -= entry.length;
  }
}

/// One native copy. It holds nothing of its source: the source's
/// liveness is the finalizer's to watch.
final class _Upload {
  _Upload(this.pointer, this.length);

  final Pointer<Uint8> pointer;
  final int length;
  bool resident = true;
}
