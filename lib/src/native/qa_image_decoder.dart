// The engine's Rust library carries the decoder (rust/src/lib.rs), and its
// names are found in that code asset — no library opened, no path named.
@DefaultAsset(gpuEngineAsset)
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'gpu_engine_asset.dart';
import 'native_scratch.dart';

@Native<Pointer<Void> Function(Pointer<Uint8>, Size)>(
  symbol: 'qa_image_decode_jpg_open',
)
external Pointer<Void> _open(Pointer<Uint8> bytes, int length);

@Native<Int32 Function(Pointer<Void>, Pointer<Int32>)>(
  symbol: 'qa_image_decode_jpg_size',
)
external int _size(Pointer<Void> opened, Pointer<Int32> size);

@Native<Int32 Function(Pointer<Void>, Int32, Pointer<Uint8>)>(
  symbol: 'qa_image_decode_jpg_row',
)
external int _row(Pointer<Void> opened, int y, Pointer<Uint8> rgba);

@Native<Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32)>(
  symbol: 'qa_image_decode_jpg_error',
)
external int _error(Pointer<Void> opened, Pointer<Uint8> text, int room);

@Native<Void Function(Pointer<Void>)>(symbol: 'qa_image_decode_jpg_close')
external void _close(Pointer<Void> opened);

/// The still-image decoder: a JPEG's pixels in the engine
/// (native/image_decode, zune-jpeg) — decoded on the worker that lays
/// them, never on the isolate that paints.
///
/// 🗣️유저 2026-11-15 (a-raster-import-goes-gpu-cpu-gpu-cpu-Q2) 「빠른 JPEG
/// 디코더를 들인다」. ↩️The image package read a still JPEG till then, in
/// 0.80–0.83 s for 4000×3000 on the Surface.
abstract final class QaImageDecoder {
  /// The JPEG [bytes] decoded: [sized] told its width and height as it
  /// shows, then [row] handed each row of it top to bottom — straight
  /// RGBA8, opaque, turned by its EXIF as the engine turns it, its colours
  /// as the file codes them. [row]'s bytes are one buffer, written again
  /// for the next row.
  ///
  /// Throws a [FormatException] saying why where the file does not decode;
  /// [sized] may throw to read no row.
  static void readJpegRows(
    Uint8List bytes, {
    required void Function(int width, int height) sized,
    required void Function(int y, Uint8List rgba) row,
  }) {
    final opened = withNativeBytes(
      bytes,
      (data) => _open(data, bytes.length),
    );
    if (opened == nullptr) {
      throw const FormatException('A JPEG with no bytes.');
    }
    try {
      final (width, height) = _shownSize(opened);
      sized(width, height);
      final rows = calloc<Uint8>(width * 4);
      try {
        final rgba = rows.asTypedList(width * 4);
        for (var y = 0; y < height; y += 1) {
          if (_row(opened, y, rows) == 0) {
            throw FormatException('A JPEG with no row $y.');
          }
          row(y, rgba);
        }
      } finally {
        calloc.free(rows);
      }
    } finally {
      _close(opened);
    }
  }

  /// [opened]'s size as it shows — or a [FormatException] saying why it
  /// did not decode.
  static (int, int) _shownSize(Pointer<Void> opened) {
    final size = calloc<Int32>(2);
    try {
      if (_size(opened, size) == 0) {
        throw FormatException(_whyNot(opened));
      }
      return (size[0], size[1]);
    } finally {
      calloc.free(size);
    }
  }

  static String _whyNot(Pointer<Void> opened) {
    const room = 256;
    final text = calloc<Uint8>(room);
    try {
      final length = _error(opened, text, room);
      return length < 0
          ? 'A JPEG that did not decode.'
          : String.fromCharCodes(text.asTypedList(length));
    } finally {
      calloc.free(text);
    }
  }
}
