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
/// MANY documents at once, each a HANDLE the caller keeps. It held one at a
/// time while scrubbing a preview was the only caller; a movie kept as a
/// reference put three more in the room — the canvas, the playback warmer
/// and export — and one document means a re-open per switch (~111ms).
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
  late final _openSpan = _library
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int64, Int64, Int32),
        int Function(Pointer<Utf8>, int, int, int)
      >('qa_video_decode_open_span');
  late final _framedSupported = _library
      .lookupFunction<Int32 Function(), int Function()>(
        'qa_video_decode_framed_supported',
      );
  late final _info = _library
      .lookupFunction<
        Int32 Function(
          Int32,
          Pointer<Int32>,
          Pointer<Int32>,
          Pointer<Int64>,
          Pointer<Int32>,
          Pointer<Int32>,
        ),
        int Function(
          int,
          Pointer<Int32>,
          Pointer<Int32>,
          Pointer<Int64>,
          Pointer<Int32>,
          Pointer<Int32>,
        )
      >('qa_video_decode_info');
  late final _frame = _library
      .lookupFunction<
        Int32 Function(Int32, Int64, Pointer<Uint8>, Int32),
        int Function(int, int, Pointer<Uint8>, int)
      >('qa_video_decode_frame');
  late final _close = _library
      .lookupFunction<Void Function(Int32), void Function(int)>(
        'qa_video_decode_close',
      );
  late final _closeAll = _library
      .lookupFunction<Void Function(), void Function()>(
        'qa_video_decode_close_all',
      );
  late final _lastError = _library
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'qa_video_decode_last_error',
      );

  /// Whether THIS build can decode at all. False is an answer the caller
  /// shows, never a crash it recovers from.
  bool get isSupported => _supported() != 0;

  /// Whether this DEVICE's decoder can be fed a movie kept FRAMED — every
  /// platform can but Android below API 28, which has no custom source to
  /// serve decoded blocks through (`qa_video_decode.c` says why). There a
  /// carried movie kept framed is read from its original while one exists:
  /// the cost 유저 accepted on board `carried-movie-compressed-Q1`.
  bool get readsFramed => _framedSupported() != 0;

  /// What the last failure was, for the sentence the window shows.
  String get lastError {
    final pointer = _lastError();
    return pointer == nullptr ? '' : pointer.toDartString();
  }

  /// Opens [path] as a DOCUMENT a caller keeps — and it STAYS open.
  ///
  /// 🚨★★★**THE DOCUMENT IS A NATIVE HANDLE NOW.** It used to be a note
  /// saying which movie the one native document ought to be holding, and
  /// [frameOf] put yours back whenever somebody else's was loaded. That was
  /// the honest fix while the native side had room for one — a viewer going
  /// quietly blank is worse than a re-open — but re-opening measured ~111ms
  /// at 1080p, and the callers stopped being two people scrubbing: a movie
  /// kept as a reference decodes where the canvas stands, the playback
  /// warmer fills the frames ahead of it, and export walks a whole cut. Any
  /// two of those interleaving paid that price per switch.
  ///
  /// ⛔A caller still cannot ask for a frame without saying WHICH movie —
  /// that shape is what made forgetting impossible, and it is unchanged.
  ///
  /// [span] opens a MOVIE THAT LIVES INSIDE [path] rather than the file
  /// itself — the shape a carried video has, since its bytes are a stretch
  /// of the `.anicel` or a staged copy and no path points at the movie. The
  /// stretch holds the movie as it is, or FRAMED (compressed in blocks) —
  /// which a device answers for through [readsFramed].
  QaVideoDocument? openDocument(
    String path, {
    ({int offset, int length, bool framed})? span,
  }) {
    final utf8Path = path.toNativeUtf8(allocator: malloc);
    final int handle;
    try {
      handle = span == null
          ? _open(utf8Path)
          : _openSpan(
              utf8Path,
              span.offset,
              span.length,
              span.framed ? 1 : 0,
            );
    } finally {
      malloc.free(utf8Path);
    }
    if (handle == 0) {
      return null;
    }
    final info = _infoOf(handle);
    if (info == null) {
      _close(handle);
      return null;
    }
    return QaVideoDocument._(
      handle: handle,
      path: path,
      span: span,
      info: info,
    );
  }

  /// The frame at [index] OF [document]. Null when it could not be read —
  /// [lastError] says why.
  Uint8List? frameOf(QaVideoDocument document, int index, {Uint8List? into}) {
    final bytes = document.info.width * document.info.height * 4;
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
    if (_frame(document.handle, index, _scratch, bytes) == 0) {
      return null;
    }
    final view = _scratch.asTypedList(bytes);
    final out = (into != null && into.length == bytes)
        ? into
        : Uint8List(bytes);
    out.setRange(0, bytes, view);
    return out;
  }

  /// Closes [document] — and only it. ⛔A close that took the OTHER
  /// consumer's movie with it is the bug the handle exists to make
  /// unthinkable.
  void closeDocument(QaVideoDocument document) => _close(document.handle);

  /// What a document says about itself.
  QaVideoInfo? _infoOf(int handle) {
    final width = malloc<Int32>();
    final height = malloc<Int32>();
    final frames = malloc<Int64>();
    final fpsNum = malloc<Int32>();
    final fpsDen = malloc<Int32>();
    try {
      if (_info(handle, width, height, frames, fpsNum, fpsDen) == 0) {
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
  /// 🚨★★★**NOTHING IS MINTED PER FRAME.** Playing a 4K movie at 24fps used
  /// to allocate a 32MB native buffer AND a 32MB Dart list every frame —
  /// 1.5GB of churn a second, on the device class this app promises to run
  /// on ([[old-device-support-policy]]). Both are reused: [frameOf] keeps
  /// one native scratch for as long as this decoder lives, and its `into`
  /// lets the caller own one Dart buffer for the same span.
  ///
  /// ⛔The native scratch is NEVER handed out. That is the whole of
  /// [[native-tile-pixel-lifetime]]: the mistake was a pointer whose
  /// lifetime the receiver could not see, not a buffer the owner keeps and
  /// frees in [close].
  ///
  /// ⚠️Reusing `into` is safe because every consumer copies it
  /// SYNCHRONOUSLY — `decodeStraightRgbaImage` premultiplies into its own
  /// scratch (or a fresh list) before the async decode begins. A consumer
  /// that held this buffer across an await would read the NEXT frame.
  Pointer<Uint8> _scratch = nullptr;
  int _scratchBytes = 0;

  /// Closes EVERY document — what a teardown wants, and the only close a
  /// caller holding no handle can honestly make.
  void close() {
    _closeAll();
    if (_scratchBytes > 0) {
      malloc.free(_scratch);
      _scratch = nullptr;
      _scratchBytes = 0;
    }
  }
}

/// A movie a caller has opened — the native document itself, by handle.
///
/// 🚨It exists because more than one part of the app wants a movie open at
/// the same time: the canvas showing a reference movie, the warmer filling
/// the frames ahead, export walking a cut, the viewer, the placement
/// window. Asking for a frame without saying WHICH movie is not
/// expressible, which is the only shape where forgetting is impossible.
///
/// ⛔Compared by IDENTITY, not by path: two consumers looking at the same
/// file still each own their document, and「my document」is a question about
/// who opened it, not about which bytes it is.
final class QaVideoDocument {
  const QaVideoDocument._({
    required this.handle,
    required this.path,
    required this.span,
    required this.info,
  });

  /// The native document. ⛔Never 0: that is how the native side spells
  /// 「no document」, and a handle that reads it never leaves [openDocument].
  final int handle;

  final String path;
  final ({int offset, int length, bool framed})? span;
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
