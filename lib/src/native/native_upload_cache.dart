import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../core/lru.dart';

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
    _copies.fit();
  }

  int _byteBudget;

  final Expando<_Upload> _bySource = Expando<_Upload>('nativeUploads');

  /// The copies by address, the least recently used first — bounded by
  /// [byteBudget] and [entryCap] both, the newest excepted.
  late final Lru<Pointer<Uint8>, _Upload> _copies = Lru(
    limit: () => _byteBudget,
    costOf: (copy) => copy.length,
    entryCap: () => entryCap,
    letGo: (_, copy) => _free(copy),
  );
  late final Finalizer<_Upload> _sourceGone = Finalizer<_Upload>(
    _sourceCollected,
  );

  int get entryCount => _copies.length;

  int get residentBytes => _copies.held;

  /// The native copy of [data], uploaded once.
  ///
  /// ⚠️Valid while [data] is reachable — use it in the same synchronous
  /// stretch that holds the list. A finalizer runs from the event loop, so
  /// it can never free a copy in the middle of a kernel call.
  Pointer<Uint8> upload(L data) {
    final cached = _bySource[data];
    if (cached != null && cached.resident) {
      _copies.use(cached.pointer);
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
    _copies.keep(pointer, entry);
    return pointer;
  }

  /// [entry]'s source was collected: its copy goes, unless the budget let
  /// it go first.
  void _sourceCollected(_Upload entry) {
    if (entry.resident) {
      _copies.take(entry.pointer);
      _free(entry);
    }
  }

  /// Frees [entry]'s copy, out of [_copies] already — ONCE: the budget let
  /// it go, or its source was collected, whichever came first, and the
  /// other finds it gone.
  void _free(_Upload entry) {
    entry.resident = false;
    _sourceGone.detach(entry);
    malloc.free(entry.pointer);
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
