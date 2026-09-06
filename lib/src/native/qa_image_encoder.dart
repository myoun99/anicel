import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_scratch.dart';
import 'qa_engine_abi.dart';

/// The still-image encoder (EX4): baseline JPEG through the engine's
/// vendored stb_image_write — memory to memory, byte-deterministic,
/// no ffmpeg, no pub dependency.
///
/// Unlike the video encoder there is NO test gate: encoding a buffer is
/// a pure function with no device side effects, and the widget tests
/// exercise the real thing when the standalone binary is around
/// ([debugQaEngineLibraryPathOverride], same as the parity suites).
final class QaImageEncoder {
  QaImageEncoder._(this._library);

  final DynamicLibrary _library;

  static QaImageEncoder? _instance;
  static bool _tried = false;

  static void debugResetForTests() {
    _instance = null;
    _tried = false;
  }

  static QaImageEncoder? get instance {
    if (!_tried) {
      _tried = true;
      final library = openQaEngineLibrary();
      _instance = library == null ? null : QaImageEncoder._(library);
    }
    return _instance;
  }

  late final _encodeJpg = _library
      .lookupFunction<
        Int32 Function(
          Pointer<Uint8>,
          Int32,
          Int32,
          Int32,
          Pointer<Pointer<Uint8>>,
          Pointer<Int32>,
        ),
        int Function(
          Pointer<Uint8>,
          int,
          int,
          int,
          Pointer<Pointer<Uint8>>,
          Pointer<Int32>,
        )
      >('qa_image_encode_jpg');
  late final _free = _library
      .lookupFunction<Void Function(Pointer<Uint8>), void Function(Pointer<Uint8>)>(
        'qa_image_encode_free',
      );

  bool get isSupported {
    try {
      _encodeJpg;
      return true;
    } on Object {
      return false; // an older binary without the image surface
    }
  }

  /// Encodes top-down RGB24 into JPEG bytes; null on refusal (an older
  /// binary, a degenerate size).
  Uint8List? encodeJpg({
    required Uint8List rgb,
    required int width,
    required int height,
    required int quality,
  }) {
    if (rgb.length < width * height * 3 || width <= 0 || height <= 0) {
      return null;
    }
    final outData = calloc<Pointer<Uint8>>();
    final outSize = calloc<Int32>();
    try {
      final ok = withNativeBytes(
        rgb,
        (input) => _encodeJpg(input, width, height, quality, outData, outSize),
      );
      if (ok == 0 || outSize.value <= 0) {
        return null;
      }
      final bytes = Uint8List.fromList(
        outData.value.asTypedList(outSize.value),
      );
      _free(outData.value);
      return bytes;
    } on Object {
      return null;
    } finally {
      calloc.free(outData);
      calloc.free(outSize);
    }
  }
}
