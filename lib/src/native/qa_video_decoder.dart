import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'qa_engine_abi.dart';

/// The OS video DECODER — a movie in, one RGBA frame out.
///
/// The export path's mirror ([QaVideoEncoder]): both go through the
/// operating system's own codec stack rather than an ffmpeg binary a
/// tablet does not have. Windows reads through Media Foundation's Source
/// Reader; the platforms whose reader is not written yet answer
/// [isSupported] false, and the app says "no decoder in this build"
/// instead of failing as a corrupt file.
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

  /// Opens [path], replacing whatever was open. Null when it cannot be
  /// read — [lastError] says why.
  QaVideoInfo? open(String path) {
    final utf8Path = path.toNativeUtf8(allocator: malloc);
    try {
      if (_open(utf8Path) == 0) {
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
  /// The buffer is allocated per call and copied out: a native buffer that
  /// outlives the call is the tile-lifetime mistake this repo already made
  /// once ([[native-tile-pixel-lifetime]]).
  Uint8List? frame(int index, {required int width, required int height}) {
    final bytes = width * height * 4;
    if (bytes <= 0) {
      return null;
    }
    final buffer = malloc<Uint8>(bytes);
    try {
      if (_frame(index, buffer, bytes) == 0) {
        return null;
      }
      return Uint8List.fromList(buffer.asTypedList(bytes));
    } finally {
      malloc.free(buffer);
    }
  }

  void close() => _close();
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
