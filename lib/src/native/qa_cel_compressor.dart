// The engine's Rust library carries the compressor (rust/src/lib.rs), and
// its names are found in that code asset — no library opened, no path named.
@DefaultAsset(gpuEngineAsset)
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'gpu_engine_asset.dart';
import 'native_scratch.dart';

@Native<Int64 Function(Int64)>(symbol: 'qa_zstd_compress_bound')
external int _bound(int srcSize);

@Native<Int64 Function(Pointer<Uint8>, Int64, Pointer<Uint8>, Int64)>(
  symbol: 'qa_zstd_compress',
)
external int _compress(
  Pointer<Uint8> dst,
  int dstCapacity,
  Pointer<Uint8> src,
  int srcSize,
);

@Native<Int64 Function(Pointer<Uint8>, Int64)>(
  symbol: 'qa_zstd_decompressed_size',
)
external int _sizeOf(Pointer<Uint8> src, int srcSize);

@Native<Int64 Function(Pointer<Uint8>, Int64, Pointer<Uint8>, Int64)>(
  symbol: 'qa_zstd_decompress',
)
external int _decompress(
  Pointer<Uint8> dst,
  int dstCapacity,
  Pointer<Uint8> src,
  int srcSize,
);

/// zstd for cel blobs — the compressor whose DEcompression is on the frame
/// path, in the engine (native/compress, at its one level — which says
/// why there is one).
///
/// 🚨★★★**THE SPEED THAT MATTERS IS THE READ.** A cel is compressed once
/// per save, on a background isolate. It is DECOMPRESSED on the main
/// isolate, synchronously, every time a cold cel is promoted to hot —
/// which is the first time you scrub onto it. Measured on a real 22.8MB
/// project: the median cel takes 3.35ms with deflate and **0.11ms** with
/// zstd. At 60fps a frame is 16.7ms, so deflate was spending a fifth of
/// one on a single cel.
///
/// ⛔It does NOT replace deflate. `dart:io` has zlib and always works. The
/// blob carries a codec byte, both are read, and deflate is written where
/// zstd refuses ([compress] answers null). **A file this app writes must
/// never need a library that might not be there.** ↩️Until the connection
/// round (connection-round-checklist H, 2026-11-08) the compressor was the
/// C engine's, which a build could be without, and zstd was written only
/// where it loaded; the engine's ships with the app, so it is there
/// wherever a file is written or read.
abstract final class QaCelCompressor {
  /// Test hook: refuse every input, as the compressor refuses an empty one
  /// — what a save writes where zstd refuses is otherwise out of reach.
  static bool debugForceRefusal = false;

  /// Compresses [bytes], or null when the engine refused — null means
  /// "write deflate instead", never "lose the cel".
  static Uint8List? compress(Uint8List bytes) {
    if (debugForceRefusal || bytes.isEmpty) {
      return null;
    }
    final capacity = _bound(bytes.length);
    if (capacity <= 0) {
      return null;
    }
    final dst = malloc<Uint8>(capacity);
    try {
      final written = withNativeBytes(
        bytes,
        (src) => _compress(dst, capacity, src, bytes.length),
      );
      if (written <= 0) {
        return null;
      }
      return Uint8List.fromList(dst.asTypedList(written));
    } finally {
      malloc.free(dst);
    }
  }

  /// What [read] makes of the bytes a frame written by [compress] holds,
  /// or null — [read] never called — when the frame cannot be read: the
  /// caller turns that into the same failure a corrupt deflate stream
  /// already produces.
  ///
  /// 🚨★★★**THE BYTES [read] IS HANDED ARE NATIVE, AND FREED WHEN IT
  /// RETURNS** — [read] copies what it keeps. ↩️They were copied onto the
  /// Dart heap (`Uint8List.fromList`) and the native block freed at once:
  /// every cel a thaw, a pre-bake or an undo decoded left its whole picture
  /// there, past 256KB so straight into old space, garbage once its tiles
  /// were laid. 🔬Opening S5_BA to a cut's pre-bake (타임라인/콘티, profile
  /// build, 2026-11-05): ~825MB of it, 92% of the old garbage in that run —
  /// the collections that stop a frame 10–26ms (a-collection-stops-a-frame,
  /// 유저 「열 때 생기는 쓰레기를 줄인다」).
  ///
  /// ⚠️The size comes from the FRAME, not from our own header: zstd
  /// records it, and storing it a second time would be two numbers that
  /// can disagree.
  static R? readFrame<R extends Object>(
    Uint8List frame,
    R Function(Uint8List bytes) read,
  ) {
    if (frame.isEmpty) {
      return null;
    }
    return withNativeBytes(frame, (src) {
      final size = _sizeOf(src, frame.length);
      if (size <= 0) {
        return null;
      }
      final dst = malloc<Uint8>(size);
      try {
        final written = _decompress(dst, size, src, frame.length);
        if (written != size) {
          return null;
        }
        return read(dst.asTypedList(size));
      } finally {
        malloc.free(dst);
      }
    });
  }
}
