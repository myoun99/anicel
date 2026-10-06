import 'dart:io';
import 'dart:ui' as ui;

import 'png_srgb.dart';

/// What one export run did: [processed] tasks were attempted (fewer than the
/// plan when cancelled) and [written] files hit the disk ([renderImage]
/// returning `null` skips the file, e.g. empty cels).
typedef ExportWriteSummary = ({int written, int processed});

/// The bytes of one image's file, or null to write none.
typedef ExportImageEncoder = Future<List<int>?> Function(ui.Image image);

/// Streams rendered images to disk — one image rendered, encoded and
/// released at a time, so a full-resolution sequence never lives in memory
/// at once.
class PngSequenceExportService {
  const PngSequenceExportService();

  /// [encoderFor] names the encoder of each file whose bytes are not the
  /// default's — the engine PNG + the sRGB tag — (the JPG path, later
  /// PSD). It is asked a FILE: one run writes files of more than one format
  /// (the Cels tab's cels beside its sheets and envelopes). A null encoder
  /// is the default; a null encode RESULT skips the file like a null render
  /// does.
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
    for (var index = 0; index < count; index += 1) {
      if (isCancelled?.call() ?? false) {
        break;
      }
      final image = await renderImage(index);
      if (image != null) {
        final path =
            '$directoryPath${Platform.pathSeparator}${fileNameFor(index)}';
        if (await _writeOneImage(image, path, encoderFor?.call(index))) {
          written += 1;
        }
      }
      processed += 1;
      onProgress?.call(processed, count);
    }
    return (written: written, processed: processed);
  }

  /// Encodes [image] and writes it at [path]; false = nothing to write
  /// (the encoder had no bytes for it), which the caller counts the same
  /// way it counts a null render.
  ///
  /// ⚠️It OWNS the image: disposed here whichever way the encode goes.
  Future<bool> _writeOneImage(
    ui.Image image,
    String path,
    ExportImageEncoder? encode,
  ) async {
    try {
      final List<int>? fileBytes;
      if (encode != null) {
        fileBytes = await encode(image);
      } else {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        // C1-v1: delivered PNGs declare the working color space (sRGB) so
        // downstream tools stop guessing. Pixels untouched.
        fileBytes = bytes == null
            ? null
            : tagPngAsSrgb(bytes.buffer.asUint8List());
      }
      if (fileBytes == null) {
        return false;
      }
      final file = File(path);
      // File names may carry subfolders (per-cut/per-layer cels).
      await file.parent.create(recursive: true);
      await file.writeAsBytes(fileBytes, flush: true);
      return true;
    } finally {
      image.dispose();
    }
  }
}
