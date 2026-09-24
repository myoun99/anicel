import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'native_scratch.dart';
import 'qa_engine_abi.dart';

/// A medium stored in a span of a file — its own bytes, or FRAMED in
/// compressed blocks — read a window at a time by the engine's one reader of
/// both (`qa_media_span.c`).
///
/// 🚨★★★**THE READER THE DECODERS USE, AND NOW DART'S TOO.** A framed medium
/// was read by a Dart copy of the block walk for everything Dart reads (a
/// PDF's pages, a picture, a fingerprint) and by nothing at all on the
/// native side, which is why a carried movie kept compressed could not be
/// played and a framed sound was assembled whole before it was decoded
/// (board `carried-movie-compressed`, 유저 2026-09-24 「최대한 통일할거
/// 통일해줘」). Both sides read through this one now, so a Dart read and a
/// decoder's read of one span cannot come to disagree.
///
/// ⛔A PLAIN span is read through here only by native code. Dart reads a
/// plain file with `RandomAccessFile` (`MediaByteSource`), because a build
/// without the engine still has to read one; a framed medium has no such
/// floor — its blocks are zstd, which only the engine carries.
final class QaMediaSpan {
  QaMediaSpan._(this._api, this._handle, this.size);

  final _QaMediaSpanApi _api;
  Pointer<Void> _handle;

  /// How many bytes the MEDIUM has — for a framed span, decoded.
  final int size;

  /// Whether this build can read a span at all.
  static bool get available => _QaMediaSpanApi.instance != null;

  /// The medium stored in `[offset, offset + length)` of [path] — its own
  /// bytes, or a framed blob of them when [framed]. Null when there is no
  /// engine, or when the span does not hold together: not inside the file,
  /// or a framed header that disagrees with the span it sits in.
  static QaMediaSpan? open(
    String path, {
    required int offset,
    required int length,
    required bool framed,
  }) {
    final api = _QaMediaSpanApi.instance;
    if (api == null) {
      return null;
    }
    final utf8Path = path.toNativeUtf8(allocator: malloc);
    final Pointer<Void> handle;
    try {
      handle = api.open(utf8Path, offset, length, framed ? 1 : 0);
    } finally {
      malloc.free(utf8Path);
    }
    if (handle == nullptr) {
      return null;
    }
    return QaMediaSpan._(api, handle, api.size(handle));
  }

  /// Up to [count] bytes of the medium from [position] into [buffer]: how
  /// many landed, short only at the end and 0 past it. Throws a
  /// [FormatException] when the file would not read or a block would not
  /// decode — a broken medium says so rather than handing back less.
  ///
  /// ⚠️Through a scratch of at most [_windowBytes] at a time, so reading a
  /// whole medium does not also park one of its size in native memory.
  int readInto(Uint8List buffer, int position, int count) {
    if (_handle == nullptr) {
      throw StateError('read from a closed media span');
    }
    var wrote = 0;
    while (wrote < count) {
      final want = count - wrote < _windowBytes ? count - wrote : _windowBytes;
      final scratch = _window.ensure(want);
      final got = _api.read(_handle, position + wrote, scratch.cast(), want);
      if (got < 0) {
        throw const FormatException('the stored medium would not read back');
      }
      if (got == 0) {
        break;
      }
      buffer.setRange(wrote, wrote + got, scratch.asTypedList(got));
      wrote += got;
      if (got < want) {
        break;
      }
    }
    return wrote;
  }

  /// What this span has cost so far: blocks decoded, and stored bytes read
  /// (the framed header included) — what tells a reader that reads only the
  /// blocks a window lands in from one that quietly reads them all.
  ({int blocksDecoded, int storedBytesRead}) get stats {
    final decoded = calloc<Int64>();
    final read = calloc<Int64>();
    try {
      _api.stats(_handle, decoded, read);
      return (blocksDecoded: decoded.value, storedBytesRead: read.value);
    } finally {
      calloc
        ..free(decoded)
        ..free(read);
    }
  }

  void close() {
    if (_handle != nullptr) {
      debugOnClose?.call(stats);
      _api.close(_handle);
      _handle = nullptr;
    }
  }

  /// Test hook: handed what each span cost as it closes — the one way to
  /// count what a ONE-SHOT read spent, since the span it read through is
  /// gone by the time the read returns.
  @visibleForTesting
  static void Function(({int blocksDecoded, int storedBytesRead}) cost)?
  debugOnClose;

  /// The most one native read hands over at a time.
  static const int _windowBytes = 1024 * 1024;

  /// ⚠️One for the isolate, not one per span: nothing here suspends between
  /// the native read and the copy out, and a scratch per span would be one
  /// more buffer per open PDF.
  static final NativeScratch<Uint8> _window = NativeScratch<Uint8>(
    (count) => calloc<Uint8>(count),
  );
}

/// The span reader's exports, resolved once per isolate.
final class _QaMediaSpanApi {
  _QaMediaSpanApi._(DynamicLibrary library)
    : open = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Utf8>, Int64, Int64, Int32),
            Pointer<Void> Function(Pointer<Utf8>, int, int, int)
          >('qa_media_span_open'),
      size = library
          .lookupFunction<
            Int64 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('qa_media_span_size'),
      read = library
          .lookupFunction<
            Int64 Function(Pointer<Void>, Int64, Pointer<Void>, Int64),
            int Function(Pointer<Void>, int, Pointer<Void>, int)
          >('qa_media_span_read'),
      close = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('qa_media_span_close'),
      stats = library
          .lookupFunction<
            Void Function(Pointer<Void>, Pointer<Int64>, Pointer<Int64>),
            void Function(Pointer<Void>, Pointer<Int64>, Pointer<Int64>)
          >('qa_media_span_stats');

  final Pointer<Void> Function(Pointer<Utf8>, int, int, int) open;
  final int Function(Pointer<Void>) size;
  final int Function(Pointer<Void>, int, Pointer<Void>, int) read;
  final void Function(Pointer<Void>) close;
  final void Function(Pointer<Void>, Pointer<Int64>, Pointer<Int64>) stats;

  static _QaMediaSpanApi? _instance;
  static bool _tried = false;

  static _QaMediaSpanApi? get instance {
    if (!_tried) {
      _tried = true;
      final library = openQaEngineLibrary();
      try {
        _instance = library == null ? null : _QaMediaSpanApi._(library);
      } on ArgumentError {
        _instance = null;
      }
    }
    return _instance;
  }
}
