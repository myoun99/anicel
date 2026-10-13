import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'png_srgb.dart';

/// What one export run did: [processed] tasks were attempted (fewer than the
/// plan when cancelled) and [written] files hit the disk ([renderImage]
/// returning `null` skips the file, e.g. empty cels).
typedef ExportWriteSummary = ({int written, int processed});

/// The bytes of one image's file, or null to write none.
typedef ExportImageEncoder = Future<List<int>?> Function(ui.Image image);

/// Streams rendered images to disk — one image rendered, encoded and
/// released at a time, so a full-resolution sequence never lives in memory
/// at once. The one before is kept until the next is in, to know it by
/// ([_BytesBefore]).
class PngSequenceExportService {
  const PngSequenceExportService();

  /// How many images every run has encoded (test hook) — a file whose image
  /// is the one before, handed again, encodes none.
  @visibleForTesting
  static int debugEncodes = 0;

  /// [encoderFor] names the encoder of each file whose bytes are not the
  /// default's — the engine PNG + the sRGB tag — (JPG, a PNG without alpha,
  /// later PSD). It is asked a FILE: one run writes files of more than one
  /// format (the Cels tab's cels beside its sheets and envelopes). A null
  /// encoder is the default; a null encode RESULT skips the file like a null
  /// render does.
  ///
  /// 🚨A FILE WHOSE IMAGE IS THE ONE BEFORE IT, HANDED AGAIN, IS THE BYTES
  /// BEFORE IT: an image that is a clone of the one before
  /// (`ui.Image.isCloneOf` — a run's frame made of what the frame before it
  /// was made of, `ExportFrameRenderer.stillRun`), under the same encoder,
  /// is neither read back nor encoded again. A video's frames go to their
  /// encoder the same way (`VideoExportService`).
  Future<ExportWriteSummary> exportImages({
    required int count,
    required Future<ui.Image?> Function(int index) renderImage,
    required String Function(int index) fileNameFor,
    required String directoryPath,
    ExportImageEncoder? Function(int index)? encoderFor,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var written = 0;
    var processed = 0;
    final before = _BytesBefore();
    try {
      for (var index = 0; index < count; index += 1) {
        if (isCancelled?.call() ?? false) {
          break;
        }
        final image = await renderImage(index);
        if (image != null) {
          final bytes = await before.of(image, encoderFor?.call(index));
          if (bytes != null) {
            await _write(
              bytes,
              '$directoryPath${Platform.pathSeparator}${fileNameFor(index)}',
            );
            written += 1;
          }
        }
        processed += 1;
        onProgress?.call(processed, count);
      }
    } finally {
      before.dispose();
    }
    return (written: written, processed: processed);
  }

  /// Writes [bytes] as the file at [path].
  Future<void> _write(List<int> bytes, String path) async {
    final file = File(path);
    // File names may carry subfolders (per-cut/per-layer cels).
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }
}

/// The file bytes of the image before, and that image and its encoder —
/// kept to know the next by.
///
/// ⚠️A video's frames keep their pixels the same way (`VideoExportService`'s
/// `_FramePixels`). Two are left apart until a third keeps something of the
/// image before (the rule of three) — that one makes them one.
final class _BytesBefore {
  ui.Image? _image;
  ExportImageEncoder? _encode;
  List<int>? _bytes;

  /// [image]'s file bytes as [encode] writes them, or null to write none —
  /// the bytes before, when [image] is the image before handed again and
  /// [encode] the encoder before.
  ///
  /// ⚠️It OWNS [image] from here on: kept to know the next by, or let go at
  /// once when it is the one kept already.
  Future<List<int>?> of(ui.Image image, ExportImageEncoder? encode) async {
    final kept = _image;
    if (kept != null && image.isCloneOf(kept) && identical(encode, _encode)) {
      image.dispose();
      return _bytes;
    }
    kept?.dispose();
    _image = image;
    _encode = encode;
    _bytes = null;
    PngSequenceExportService.debugEncodes += 1;
    return _bytes = await _encoded(image, encode);
  }

  void dispose() {
    _image?.dispose();
    _image = null;
    _encode = null;
    _bytes = null;
  }
}

/// [image]'s file bytes as [encode] writes them — the engine's PNG with the
/// sRGB tag where [encode] is null.
Future<List<int>?> _encoded(ui.Image image, ExportImageEncoder? encode) async {
  if (encode != null) {
    return encode(image);
  }
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  // C1-v1: delivered PNGs declare the working color space (sRGB) so
  // downstream tools stop guessing. Pixels untouched.
  return bytes == null ? null : tagPngAsSrgb(bytes.buffer.asUint8List());
}
