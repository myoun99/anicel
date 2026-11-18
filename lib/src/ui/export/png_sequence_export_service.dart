import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart' show GpuShown;

import 'still_frame_bytes.dart';

/// What one export run did: [processed] tasks were attempted (fewer than the
/// plan when cancelled) and [written] files hit the disk ([renderImage]
/// returning `null` skips the file, e.g. empty cels).
typedef ExportWriteSummary = ({int written, int processed});

/// The bytes of one frame's file, or null to write none.
typedef ExportImageEncoder = Future<List<int>?> Function(GpuShown frame);

/// Streams rendered frames to disk — one frame rendered, encoded and
/// written at a time, so a full-resolution sequence never lives in memory
/// at once. The bytes of the one before are kept until the next is in, to
/// know it by ([_BytesBefore]).
class PngSequenceExportService {
  const PngSequenceExportService();

  /// How many frames every run has encoded (test hook) — a file whose frame
  /// is the one before, handed again, encodes none.
  @visibleForTesting
  static int debugEncodes = 0;

  /// [encoderFor] names the encoder of each file whose bytes are not the
  /// default's — the engine PNG + the sRGB tag ([rgbaPngOf]) — (JPG, a PNG
  /// without alpha, the stills the engine has no writer for, a PSD of its
  /// picture's rows). It is asked a FILE: one run writes files of more
  /// than one format (the Cels tab's cels beside its sheets and
  /// envelopes). A null encoder is the default; a null encode RESULT skips
  /// the file like a null render does.
  ///
  /// ⚠️[renderImage]'s frame is its maker's, held till the frame after it
  /// is asked (`ExportFrameRenderer`, `FramesOfPictures`): the run reads
  /// what it writes of each before it asks the next, and frees none.
  ///
  /// 🚨A FILE WHOSE FRAME IS THE ONE BEFORE IT, HANDED AGAIN, IS THE BYTES
  /// BEFORE IT: the frame before itself (a run's frame made of what the
  /// frame before it was made of, `ExportFrameRenderer.stillRun`), under
  /// the same encoder, is neither read back nor encoded again. A video's
  /// frames go to their encoder the same way (`VideoExportService`).
  Future<ExportWriteSummary> exportImages({
    required int count,
    required Future<GpuShown?> Function(int index) renderImage,
    required String Function(int index) fileNameFor,
    required String directoryPath,
    ExportImageEncoder? Function(int index)? encoderFor,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var written = 0;
    var processed = 0;
    final before = _BytesBefore();
    for (var index = 0; index < count; index += 1) {
      if (isCancelled?.call() ?? false) {
        break;
      }
      final frame = await renderImage(index);
      if (frame != null) {
        final bytes = await before.of(frame, encoderFor?.call(index));
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

/// The file bytes of the frame before, and that frame and its encoder —
/// kept to know the next by.
///
/// ⚠️A video's frames keep their pixels the same way (`VideoExportService`'s
/// `_FramePixels`). Two are left apart until a third keeps something of the
/// frame before (the rule of three) — that one makes them one.
final class _BytesBefore {
  GpuShown? _frame;
  ExportImageEncoder? _encode;
  List<int>? _bytes;

  /// [frame]'s file bytes as [encode] writes them, or null to write none —
  /// the bytes before, when [frame] is the frame before handed again and
  /// [encode] the encoder before.
  Future<List<int>?> of(GpuShown frame, ExportImageEncoder? encode) async {
    if (identical(frame, _frame) && identical(encode, _encode)) {
      return _bytes;
    }
    _frame = frame;
    _encode = encode;
    _bytes = null;
    PngSequenceExportService.debugEncodes += 1;
    return _bytes = await (encode ?? rgbaPngOf)(frame);
  }
}
