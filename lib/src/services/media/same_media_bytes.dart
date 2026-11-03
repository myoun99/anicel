import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'media_byte_source.dart';

/// Of [pairs], whether each holds the same bytes on both sides — all of
/// them in ONE isolate ([MediaStagingStore.stageCarriedBytes]'s shape: a
/// read of a big file must not hold the UI), the lengths first and then a
/// window at a time, so a pair that differs early stops early and neither
/// side is ever held whole. A side that cannot be read is not the same.
///
/// 🗣️F-550-Q3 (유저 2026-11-04: 「새로 받는다」) takes a file imported again
/// as it is now — and one whose bytes are what the pool carries already
/// has nothing new to give. Carried again, it is a second copy of the same
/// bytes (a folder brought in again staged one — audit 2026-09-24), and
/// its viewer ink starts on blank paper (F-550-Q4) for nothing. ⛔Not by
/// [MediaIdentity]: it records the length alone, and a sound exported
/// again at the same length is other bytes.
Future<List<bool>> holdTheSameBytes(
  List<(MediaByteSource, MediaByteSource)> pairs,
) => pairs.isEmpty
    // Not async: the isolate copies the closure's context, and an async
    // body's would be the machinery around the wait.
    ? Future.value(const [])
    : Isolate.run(() => [for (final (a, b) in pairs) _holdTheSame(a, b)]);

bool _holdTheSame(MediaByteSource a, MediaByteSource b) {
  MediaWindowReader? left;
  MediaWindowReader? right;
  try {
    final length = a.lengthSync();
    if (b.lengthSync() != length) {
      return false;
    }
    left = a.openWindowReader();
    right = b.openWindowReader();
    const window = 1 << 20;
    final ours = Uint8List(window);
    final theirs = Uint8List(window);
    for (var at = 0; at < length; at += window) {
      final size = math.min(window, length - at);
      if (left.readIntoSync(ours, at, size) != size ||
          right.readIntoSync(theirs, at, size) != size) {
        return false;
      }
      for (var i = 0; i < size; i++) {
        if (ours[i] != theirs[i]) {
          return false;
        }
      }
    }
    return true;
  } on Object {
    return false;
  } finally {
    left?.close();
    right?.close();
  }
}
