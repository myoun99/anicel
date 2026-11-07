// The engine's Rust library carries the encoder (rust/src/lib.rs), and its
// names are found in that code asset — no library opened, no path named.
@DefaultAsset(gpuEngineAsset)
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:gpu_engine/gpu_engine.dart' show gpuEngineAsset;

import 'native_scratch.dart';

@Native<
  Int32 Function(
    Pointer<Uint8>,
    Int32,
    Int32,
    Int32,
    Pointer<Pointer<Uint8>>,
    Pointer<Int32>,
  )
>(symbol: 'qa_image_encode_jpg')
external int _encodeJpg(
  Pointer<Uint8> rgb,
  int width,
  int height,
  int quality,
  Pointer<Pointer<Uint8>> outData,
  Pointer<Int32> outSize,
);

@Native<Void Function(Pointer<Uint8>)>(symbol: 'qa_image_encode_free')
external void _free(Pointer<Uint8> data);

/// The still-image encoder (EX4): baseline JPEG as stb_image_write v1.16
/// writes one, in the engine (native/image_encode) — memory to memory,
/// byte-deterministic, no ffmpeg, no pub dependency.
///
/// Wherever the app runs it is there: the engine's library ships with the
/// app, and `flutter test` builds it too. ↩️Until the connection round
/// (connection-round-checklist H, 2026-11-08) it was the C engine's, which a
/// machine could be without, and a JPG row stood off there.
abstract final class QaImageEncoder {
  /// Test hook: refuse every picture, as the encoder refuses a degenerate
  /// one — what a save that makes no file shows is otherwise out of reach.
  static bool debugForceRefusal = false;

  /// Encodes top-down RGB24 into JPEG bytes; null on refusal (a degenerate
  /// size).
  static Uint8List? encodeJpg({
    required Uint8List rgb,
    required int width,
    required int height,
    required int quality,
  }) {
    if (debugForceRefusal ||
        rgb.length < width * height * 3 ||
        width <= 0 ||
        height <= 0) {
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
    } finally {
      calloc.free(outData);
      calloc.free(outSize);
    }
  }
}
