import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'qa_engine_abi.dart';

/// The OS video DECODER — a movie in, one RGBA frame out.
///
/// The export path's mirror ([QaVideoEncoder]): both go through the
/// operating system's own codec stack rather than an ffmpeg binary a
/// tablet does not have. Windows reads through Media Foundation's Source
/// Reader, Apple through AVAssetImageGenerator, Android through the NDK
/// media codecs; anything else answers [isSupported] false, and the app
/// says "no decoder in this build" instead of failing as a corrupt file.
///
/// 2026-08-25: this paragraph used to say the non-Windows readers were not
/// written yet. They were, and the stale note had readers believing in a
/// limit that no longer existed. Decision comments are never deleted here,
/// which only works if a wrong one is CORRECTED.
///
/// ONE document at a time, like the export session — scrubbing a preview
/// is the driving case and it looks at one movie.
final class QaVideoDecoder {
  QaVideoDecoder._(this._library);

  final DynamicLibrary _library;

  static QaVideoDecoder? _instance;
  static bool _tried = false;

  static void debugResetForTests() {
    _instance = null;
    _tried = false;
  }

  static QaVideoDecoder? get instance {
    if (!_tried) {
      _tried = true;
      final library = openQaEngineLibrary();
      _instance = library == null ? null : QaVideoDecoder._(library);
    }
    return _instance;
  }

  late final _supported = _library
      .lookupFunction<Int32 Function(), int Function()>(
        'qa_video_decode_supported',
      );
  late final _open = _library
      .lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>(
        'qa_video_decode_open',
      );
  late final _openRange = _library
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int64, Int64),
        int Function(Pointer<Utf8>, int, int)
      >('qa_video_decode_open_range');
  late final _info = _library
      .lookupFunction<
        Int32 Function(
          Pointer<Int32>,
          Pointer<Int32>,
          Pointer<Int64>,
          Pointer<Int32>,
          Pointer<Int32>,
        ),
        int Function(
          Pointer<Int32>,
          Pointer<Int32>,
          Pointer<Int64>,
          Pointer<Int32>,
          Pointer<Int32>,
        )
      >('qa_video_decode_info');
  late final _frame = _library
      .lookupFunction<
        Int32 Function(Int64, Pointer<Uint8>, Int32),
        int Function(int, Pointer<Uint8>, int)
      >('qa_video_decode_frame');
  late final _close = _library
      .lookupFunction<Void Function(), void Function()>(
        'qa_video_decode_close',
      );
  late final _lastError = _library
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'qa_video_decode_last_error',
      );

  /// Whether THIS build can decode at all. False is an answer the caller
  /// shows, never a crash it recovers from.
  bool get isSupported => _supported() != 0;

  /// What the last failure was, for the sentence the window shows.
  String get lastError {
    final pointer = _lastError();
    return pointer == nullptr ? '' : pointer.toDartString();
  }

  /// Which movie the one native document is holding, or null when that is
  /// not known — see [openDocument].
  QaVideoDocument? _current;

  /// Opens [path] as a DOCUMENT a caller can keep and come back to.
  ///
  /// 🚨★★★**THERE IS ONE NATIVE DOCUMENT AND THERE ARE TWO CALLERS.** The
  /// viewer plays a movie; the import window scrubs one. Both used to call
  /// [open] and then [frame], and the second open silently closed the
  /// first — the import preview even said so in a comment: 「opening one
  /// here is also what closes the last」. What that reads as is a viewer
  /// that stops changing its picture, with no error anywhere.
  ///
  /// ⛔The fix is not 「remember to re-open」 at two call sites. A handle
  /// carries WHICH movie and how to get back to it, and [frameOf] re-opens
  /// when the document that is loaded is not the one being asked about. A
  /// caller cannot ask for a frame without saying which movie any more,
  /// which is the only shape where forgetting is impossible.
  ///
  /// ⚠️Re-opening is not free — a random-access frame measured ~111ms at
  /// 1080p. Two consumers alternating pay that per switch, which is the
  /// honest price of one native document and is still incomparably better
  /// than one of them going quietly blank.
  QaVideoDocument? openDocument(String path, {({int offset, int length})? range}) {
    final info = open(path, range: range);
    if (info == null) {
      return null;
    }
    return _current = QaVideoDocument._(path: path, range: range, info: info);
  }

  /// The frame at [index] OF [document], re-opening it first if the native
  /// side is currently holding a different movie.
  ///
  /// Null when the movie could not be re-opened or the frame could not be
  /// read — [lastError] says which.
  Uint8List? frameOf(QaVideoDocument document, int index, {Uint8List? into}) {
    if (!identical(_current, document)) {
      if (open(document.path, range: document.range) == null) {
        return null;
      }
      _current = document;
    }
    return frame(
      index,
      width: document.info.width,
      height: document.info.height,
      into: into,
    );
  }

  /// Closes [document] — and ONLY if it is the one that is open.
  ///
  /// ⛔A bare [close] from one consumer would take the other's movie with
  /// it, which is the same bug as the silent replace above wearing a
  /// different hat.
  void closeDocument(QaVideoDocument document) {
    if (identical(_current, document)) {
      close();
    }
  }

  /// Opens [path], replacing whatever was open. Null when it cannot be
  /// read — [lastError] says why.
  ///
  /// ⚠️Prefer [openDocument]: this one leaves nothing that says WHICH movie
  /// is loaded, so the next [frameOf] has to re-open on principle.
  ///
  /// [range] opens a MOVIE THAT LIVES INSIDE [path] rather than the file
  /// itself — the shape a carried video has, since its bytes are a stretch
  /// of the `.anicel` and there is no path pointing at the movie. ⛔The
  /// range must be the movie's own bytes, contiguous and unmodified; the
  /// native side says why in its own comment, and the short version is that
  /// Android below API 28 has no other way to open one.
  QaVideoInfo? open(String path, {({int offset, int length})? range}) {
    _current = null;
    final utf8Path = path.toNativeUtf8(allocator: malloc);
    try {
      final opened = range == null
          ? _open(utf8Path)
          : _openRange(utf8Path, range.offset, range.length);
      if (opened == 0) {
        return null;
      }
    } finally {
      malloc.free(utf8Path);
    }
    final width = malloc<Int32>();
    final height = malloc<Int32>();
    final frames = malloc<Int64>();
    final fpsNum = malloc<Int32>();
    final fpsDen = malloc<Int32>();
    try {
      if (_info(width, height, frames, fpsNum, fpsDen) == 0) {
        return null;
      }
      return QaVideoInfo(
        width: width.value,
        height: height.value,
        frameCount: frames.value,
        fpsNumerator: fpsNum.value,
        fpsDenominator: fpsDen.value,
      );
    } finally {
      malloc
        ..free(width)
        ..free(height)
        ..free(frames)
        ..free(fpsNum)
        ..free(fpsDen);
    }
  }
  /// Straight RGBA for [index], or null when that frame cannot be read.
  ///
  /// 🚨★★★**NOTHING IS MINTED PER FRAME.** Playing a 4K movie at 24fps used
  /// to allocate a 32MB native buffer AND a 32MB Dart list every frame —
  /// 1.5GB of churn a second, on the device class this app promises to run
  /// on ([[old-device-support-policy]]). Both are reused now: the decoder
  /// owns one native scratch for as long as the document is open, and
  /// [into] lets the caller own one Dart buffer for the same span.
  ///
  /// ⛔The native scratch is NEVER handed out. That is the whole of
  /// [[native-tile-pixel-lifetime]]: the mistake was a pointer whose
  /// lifetime the receiver could not see, not a buffer the owner keeps and
  /// frees in [close].
  ///
  /// ⚠️Reusing [into] is safe because every consumer copies it
  /// SYNCHRONOUSLY — `decodeStraightRgbaImage` premultiplies into its own
  /// scratch (or a fresh list) before the async decode begins. A consumer
  /// that held this buffer across an await would read the NEXT frame.
  Uint8List? frame(
    int index, {
    required int width,
    required int height,
    Uint8List? into,
  }) {
    final bytes = width * height * 4;
    if (bytes <= 0) {
      return null;
    }
    if (_scratchBytes < bytes) {
      if (_scratchBytes > 0) {
        malloc.free(_scratch);
      }
      _scratch = malloc<Uint8>(bytes);
      _scratchBytes = bytes;
    }
    if (_frame(index, _scratch, bytes) == 0) {
      return null;
    }
    final view = _scratch.asTypedList(bytes);
    final out = (into != null && into.length == bytes)
        ? into
        : Uint8List(bytes);
    out.setRange(0, bytes, view);
    return out;
  }

  Pointer<Uint8> _scratch = nullptr;
  int _scratchBytes = 0;

  void close() {
    _current = null;
    _close();
    if (_scratchBytes > 0) {
      malloc.free(_scratch);
      _scratch = nullptr;
      _scratchBytes = 0;
    }
  }
}

/// A movie a caller has opened, and everything needed to open it AGAIN.
///
/// 🚨It exists because there is one native document and more than one part
/// of the app wants one. Holding a handle rather than a path is what lets
/// [QaVideoDecoder.frameOf] notice that somebody else's movie is loaded and
/// put yours back, instead of reading frames out of theirs.
///
/// ⛔Compared by IDENTITY, not by path: two consumers looking at the same
/// file still each own their document, and「my document」is a question about
/// who opened it, not about which bytes it is.
final class QaVideoDocument {
  const QaVideoDocument._({
    required this.path,
    required this.range,
    required this.info,
  });

  final String path;
  final ({int offset, int length})? range;
  final QaVideoInfo info;
}

/// What a document says about itself.
class QaVideoInfo {
  const QaVideoInfo({
    required this.width,
    required this.height,
    required this.frameCount,
    required this.fpsNumerator,
    required this.fpsDenominator,
  });

  final int width;
  final int height;

  /// Frames the file holds, as duration × rate. A container with no
  /// duration answers 1 rather than 0 — a movie always has a picture.
  final int frameCount;

  /// The rate as a FRACTION, because 30000/1001 is not 29.97 and rounding
  /// it is how a frame index drifts a second out over a long take.
  final int fpsNumerator;
  final int fpsDenominator;

  double get fps => fpsDenominator == 0 ? 0 : fpsNumerator / fpsDenominator;
}
