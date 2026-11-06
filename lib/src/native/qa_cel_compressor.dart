import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_scratch.dart';
import 'qa_engine_abi.dart';

/// zstd for cel blobs — the compressor whose DEcompression is on the frame
/// path.
///
/// 🚨★★★**THE SPEED THAT MATTERS IS THE READ.** A cel is compressed once
/// per save, on a background isolate. It is DECOMPRESSED on the main
/// isolate, synchronously, every time a cold cel is promoted to hot —
/// which is the first time you scrub onto it. Measured on a real 22.8MB
/// project: the median cel takes 3.35ms with deflate and **0.11ms** with
/// zstd. At 60fps a frame is 16.7ms, so deflate was spending a fifth of
/// one on a single cel.
///
/// ⛔It does NOT replace deflate. `dart:io` has zlib and always works —
/// tests, host runs, any build where the engine did not load. The blob
/// carries a codec byte, both are read, and zstd is chosen only when the
/// engine answered. **A file this app writes must never need a library
/// that might not be there.**
final class QaCelCompressor {
  QaCelCompressor._(this._library);

  final DynamicLibrary _library;

  static QaCelCompressor? _instance;
  static bool _tried = false;

  /// Test seam, the same shape [PdfRenderService.debugOpenerOverride] uses:
  /// when set, [instance] answers this instead of probing.
  ///
  /// ⛔`() => null` is the ONLY way a test can say「no engine」on a machine
  /// that has one — a bogus library path cannot, because
  /// [openQaEngineLibrary] deliberately falls THROUGH a bad override to the
  /// default search. CI runs two jobs with the engine on PATH, and a test
  /// that assumed its own runner went red only there.
  static QaCelCompressor? Function()? debugInstanceOverride;

  static void debugResetForTests() {
    _instance = null;
    _tried = false;
  }

  static QaCelCompressor? get instance {
    final override = debugInstanceOverride;
    if (override != null) {
      return override();
    }
    if (!_tried) {
      _tried = true;
      final library = openQaEngineLibrary();
      _instance = library == null ? null : QaCelCompressor._(library);
    }
    return _instance;
  }

  late final _bound = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'qa_zstd_compress_bound',
      );
  late final _compress = _library
      .lookupFunction<
        Int64 Function(Pointer<Uint8>, Int64, Pointer<Uint8>, Int64, Int32),
        int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, int)
      >('qa_zstd_compress');
  late final _sizeOf = _library
      .lookupFunction<
        Int64 Function(Pointer<Uint8>, Int64),
        int Function(Pointer<Uint8>, int)
      >('qa_zstd_decompressed_size');
  late final _decompress = _library
      .lookupFunction<
        Int64 Function(Pointer<Uint8>, Int64, Pointer<Uint8>, Int64),
        int Function(Pointer<Uint8>, int, Pointer<Uint8>, int)
      >('qa_zstd_decompress');

  /// False on an older engine binary that predates these exports — the
  /// same shape every other surface here uses to survive a stale DLL.
  bool get isSupported {
    try {
      _bound;
      _compress;
      _sizeOf;
      _decompress;
      return true;
    } on Object {
      return false;
    }
  }

  /// Compresses [bytes] at [level], or null when the engine refused —
  /// null means "write deflate instead", never "lose the cel".
  Uint8List? compress(Uint8List bytes, {required int level}) {
    if (bytes.isEmpty) {
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
        (src) => _compress(dst, capacity, src, bytes.length, level),
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
  R? readFrame<R extends Object>(
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
