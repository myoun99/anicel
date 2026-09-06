import 'dart:convert' show utf8;
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_scratch.dart';
import 'qa_engine_abi.dart';

/// The OS video encoder (AUDIO-PRO R7): frames + mixed PCM in, an
/// H.264/AAC MP4 out through the operating system's own codec stack —
/// Media Foundation on Windows, AVAssetWriter on Apple, NDK MediaCodec on
/// Android. No ffmpeg.
///
/// Absence is graceful: no binary, or a platform with no OS encoder
/// (Linux), leaves [isSupported] false and the caller on the ffmpeg
/// fallback — chosen, not crashed into.
final class QaVideoEncoder {
  QaVideoEncoder._(this._library);

  final DynamicLibrary _library;

  static QaVideoEncoder? _instance;
  static bool _tried = false;

  static void debugResetForTests() {
    _instance = null;
    _tried = false;
  }

  static QaVideoEncoder? get instance {
    if (!_tried) {
      _tried = true;
      final library = openQaEngineLibrary();
      _instance = library == null ? null : QaVideoEncoder._(library);
    }
    return _instance;
  }

  late final _supported = _library
      .lookupFunction<Int32 Function(), int Function()>(
        'qa_video_export_supported',
      );
  late final _open = _library
      .lookupFunction<
        Int32 Function(
          Pointer<Utf8>,
          Int32,
          Int32,
          Int32,
          Int32,
          Int32,
          Int32,
          Int32,
          Int32,
          Int32,
          Int32,
        ),
        int Function(
          Pointer<Utf8>,
          int,
          int,
          int,
          int,
          int,
          int,
          int,
          int,
          int,
          int,
        )
      >('qa_video_export_open');
  late final _probe = _library
      .lookupFunction<
        Int32 Function(Int32, Int32),
        int Function(int, int)
      >('qa_video_export_probe');
  late final _writeFrame = _library
      .lookupFunction<
        Int32 Function(Pointer<Uint8>),
        int Function(Pointer<Uint8>)
      >('qa_video_export_write_frame');
  late final _writeAudio = _library
      .lookupFunction<
        Int32 Function(Pointer<Int16>, Int32),
        int Function(Pointer<Int16>, int)
      >('qa_video_export_write_audio');
  late final _finish = _library
      .lookupFunction<Int32 Function(), int Function()>(
        'qa_video_export_finish',
      );
  late final _abort = _library
      .lookupFunction<Void Function(), void Function()>(
        'qa_video_export_abort',
      );
  late final _error = _library
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, int)
      >('qa_video_export_error');

  /// Whether THIS build and OS can encode (Android answers by actually
  /// resolving the NDK media symbols).
  bool get isSupported {
    try {
      return _supported() != 0;
    } on Object {
      return false; // an older binary without the export surface
    }
  }

  /// Whether this platform could take the [container]/[codec] pair
  /// (ABI v21) — the format picker grays what the machine cannot write.
  /// An older binary without the probe answers the legacy truth: only
  /// MP4·H.264 existed.
  bool probe({required int container, required int codec}) {
    try {
      return _probe(container, codec) != 0;
    } on Object {
      return container == 0 && codec == 0;
    }
  }

  /// Opens the output at [path]. [channels] 0 = silent video;
  /// [container]/[codec] follow the ABI v21 values ([alpha] only matters
  /// for ProRes 4444, [bitrateBps] 0 = the encoder's own budget).
  /// Returns false with [lastError] readable on any refusal.
  bool open({
    required String path,
    required int width,
    required int height,
    required int fpsNumerator,
    required int fpsDenominator,
    int sampleRate = 0,
    int channels = 0,
    int container = 0,
    int codec = 0,
    bool alpha = false,
    int bitrateBps = 0,
  }) {
    final pathUtf8 = path.toNativeUtf8();
    try {
      return _open(
            pathUtf8,
            width,
            height,
            fpsNumerator,
            fpsDenominator,
            sampleRate,
            channels,
            container,
            codec,
            alpha ? 1 : 0,
            bitrateBps,
          ) !=
          0;
    } finally {
      calloc.free(pathUtf8);
    }
  }

  /// Writes one top-down RGBA frame (exactly the renderer's rawRgba).
  bool writeFrame(Uint8List rgba) =>
      withNativeBytes(rgba, (buffer) => _writeFrame(buffer) != 0);

  /// Writes interleaved int16 PCM ([frames] per channel) — call in chunks
  /// alongside the frames so neither side buffers the whole track.
  bool writeAudio(Int16List interleaved, int frames) {
    final buffer = calloc<Int16>(interleaved.length);
    try {
      buffer.asTypedList(interleaved.length).setAll(0, interleaved);
      return _writeAudio(buffer, frames) != 0;
    } finally {
      calloc.free(buffer);
    }
  }

  /// Finalizes the MP4 — a cancelled run finalizes a playable partial,
  /// matching the ffmpeg path's behavior.
  bool finish() => _finish() != 0;

  /// Discards an export that failed partway.
  void abort() => _abort();

  /// The last failure, for the export dialog to show verbatim.
  String get lastError {
    final buffer = calloc<Uint8>(256);
    try {
      final length = _error(buffer.cast<Utf8>(), 256);
      if (length <= 0) {
        return '';
      }
      return utf8.decode(buffer.asTypedList(length));
    } finally {
      calloc.free(buffer);
    }
  }
}
