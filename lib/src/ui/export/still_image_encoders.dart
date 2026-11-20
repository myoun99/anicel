import 'dart:isolate';
import 'dart:typed_data';

import 'package:gpu_engine/gpu_engine.dart' show GpuShown;

import '../../core/on_a_worker.dart';
import '../../models/export_format_selection.dart';
import '../../models/layer_blend_mode.dart';
import '../../native/qa_image_encoder.dart';
import '../../services/media/still_file_writing.dart';
import '../../services/photoshop/psd_writer.dart';
import 'png_sequence_export_service.dart';
import 'still_frame_bytes.dart';

/// The bytes a still file in [format] is written as, where they are not the
/// default's — the engine PNG ([PngSequenceExportService]); null keeps that.
///
/// ↩️The export window spelled this for itself; it lives here since
/// 「다른 이름으로 저장」 writes the same picture (backlog-21-Q7), so the
/// window's files and Save As's are one encoder.
///
/// 🗣️F-335 (유저 10-10): 「알파채널 아예없는걸 원하거든? RGBA가 아닌 RGB는
/// 그게 효율적이잖아」 → 「그렇게하자」 — a PNG asked for RGB has no alpha
/// channel in the file ([rgbPngOf]). The default PNG keeps the alpha, so it
/// keeps only the PNGs that keep their alpha.
///
/// ⛔A PSD is refused, not left to the engine's PNG: a Photoshop document
/// is its rows, which one picture does not hold — the tab that writes one
/// lays them out for [encodePsd] (I-117).
ExportImageEncoder? stillEncoderFor(ExportFormatSelection format) =>
    switch (format.stillFormat) {
      ExportStillFormat.jpg =>
        (frame) => _encodeStill(frame, format, _jpgAt(format.jpgQuality)),
      ExportStillFormat.png =>
        format.wantsAlpha
            ? null
            : (frame) => rgbPngOf(frame, format.backgroundArgb),
      ExportStillFormat.bmp =>
        (frame) => _encodeStill(frame, format, encodeBmp),
      ExportStillFormat.tga =>
        (frame) => _encodeStill(frame, format, encodeTga),
      ExportStillFormat.tiff =>
        (frame) => _encodeStill(frame, format, encodeTiff),
      ExportStillFormat.webp =>
        (frame) => _encodeStill(frame, format, encodeWebp),
      ExportStillFormat.psd => throw ArgumentError.value(
        format.stillFormat,
        'format',
        'A PSD is written from its rows (encodePsd), not one picture',
      ),
    };

/// [frame] through a writer of its file's bytes — one of
/// `still_file_writing.dart`'s, or the engine's JPEG encoder ([_jpgAt]):
/// its colour straight where the file keeps alpha ([straightOf]), and laid
/// over the format's background where it does not ([rgbOverGroundOf]).
/// Null where [write] refused the picture.
///
/// On a worker ([onAWorker]): a writer walks every byte, and a run of
/// frames would stall the window's cancel.
///
/// ↩️A JPG was encoded on this isolate, the engine's encoder walking the
/// whole frame here, while every other still went to a worker (card
/// `a-jpeg-still-is-encoded-on-the-ui-isolate`, the CPU census — 관제
/// 2026-11-13). It goes the one way now, and so the one switch tests turn
/// ([debugWorkersRunHere]): a hook a test sets on this isolate, as
/// [QaImageEncoder.debugForceRefusal] is, is not set on a worker's.
Future<List<int>?> _encodeStill(
  GpuShown frame,
  ExportFormatSelection format,
  Uint8List? Function(StillPixels picture) write,
) {
  final (width, height) = (frame.width, frame.height);
  final picture = format.wantsAlpha
      ? (pixels: straightOf(frame), width: width, height: height, channels: 4)
      : (
          pixels: rgbOverGroundOf(frame, format.backgroundArgb),
          width: width,
          height: height,
          channels: 3,
        );
  return onAWorker(() => write(picture));
}

/// What a layered still file (PSD — I-117) is laid up of, bottom-up: rows
/// and folders of them, each under its name, shown or hidden, and laid
/// over what is under it by its strength and blend.
sealed class ExportLayerNode {
  const ExportLayerNode({
    required this.name,
    required this.opacity,
    required this.blendMode,
    required this.visible,
    required this.clipped,
  });

  final String name;
  final double opacity;
  final LayerBlendMode blendMode;
  final bool visible;

  /// Clipped to the node under it (I-92) — Photoshop's clipping mask.
  final bool clipped;
}

/// A row of a layered still file and its picture — drawn when the file
/// comes to it, whole and in no blend on nothing, and handed over as its
/// pixels, straight, as a layer keeps its colour: one row's pixels at a
/// time, let go once they are packed ([PsdBuilder]).
///
/// 🚨PIXELS, NOT A PICTURE TO READ BACK. A row of a frame is made on the
/// engine and read off it as every still is ([straightOf]); a picture the
/// app's one door made of it (`pictureOf`) is one Impeller holds no texture
/// of till its raster thread has turned, and read back at once it was
/// none: every PSD of the image tab and the Cels tab failed 「Image was
/// null.」 (F-547 ⑦, the Surface's release, 2026-11-19). ↩️The rows were
/// pictures, read back here.
final class ExportLayerRow extends ExportLayerNode {
  const ExportLayerRow({
    required super.name,
    super.opacity = 1,
    super.blendMode = LayerBlendMode.normal,
    super.visible = true,
    super.clipped = false,
    required this.draw,
  });

  final Future<StillPixels> Function() draw;
}

/// A folder of a layered still file — a conte page's strata, a cut's folder
/// (I-117) — and what is inside it, bottom-up: 통과 unless it says
/// otherwise, as a folder is in the app.
final class ExportLayerFolder extends ExportLayerNode {
  const ExportLayerFolder({
    required super.name,
    super.opacity = 1,
    super.blendMode = LayerBlendMode.passThrough,
    super.visible = true,
    super.clipped = false,
    required this.children,
  });

  final List<ExportLayerNode> children;
}

/// The bytes a still in [format] is written as where its picture is laid
/// up of rows: a PSD keeps them apart ([encodePsd] — [nodes] is asked only
/// then), every other still is the picture alone ([stillEncoderFor]).
ExportImageEncoder? layeredEncoderFor(
  ExportFormatSelection format,
  List<ExportLayerNode> Function() nodes,
) => format.keepsRowsApart
    ? (composite) => encodePsd(composite, format, nodes())
    : stillEncoderFor(format);

/// [composite] as a Photoshop document of [nodes], bottom-up ([LayeredPsd]).
Future<List<int>?> encodePsd(
  GpuShown composite,
  ExportFormatSelection format,
  List<ExportLayerNode> nodes,
) async {
  final document = LayeredPsd(
    width: composite.width,
    height: composite.height,
  );
  await document.add(nodes);
  return document.encode(composite, format);
}

/// A Photoshop document laid up row by row, bottom-up (I-117) — for a
/// caller that lays it in steps of its own, as the conte's pages are. Each
/// row's pixels are packed in an isolate before the next row is drawn
/// ([packPsdLayer]).
///
/// ↩️A row whose picture gave no bytes made the document none, and its
/// caller skipped the file — a road no read took: a read back that fails
/// throws, as F-547 ⑦'s 「Image was null.」 came, the export's failure.
final class LayeredPsd {
  LayeredPsd({required int width, required int height})
    : _builder = PsdBuilder(width: width, height: height);

  final PsdBuilder _builder;

  /// [nodes] over every row laid before them, each folder's inside it.
  Future<void> add(List<ExportLayerNode> nodes) async {
    for (final node in nodes) {
      await switch (node) {
        final ExportLayerRow row => _addRow(row),
        final ExportLayerFolder folder => _addFolder(folder),
      };
    }
  }

  Future<void> _addRow(ExportLayerRow row) async {
    final picture = await row.draw();
    _builder.addLayer(
      name: row.name,
      pixels: await Isolate.run(() => packPsdLayer(picture)),
      opacity: row.opacity,
      visible: row.visible,
      blendMode: row.blendMode,
      clipped: row.clipped,
    );
  }

  Future<void> _addFolder(ExportLayerFolder folder) async {
    _builder.openGroup(
      name: folder.name,
      opacity: folder.opacity,
      visible: folder.visible,
      blendMode: folder.blendMode,
      clipped: folder.clipped,
    );
    await add(folder.children);
    _builder.closeGroup();
  }

  /// The document over [composite], which is written as every other still
  /// in [format] is ([_encodeStill]).
  Future<List<int>?> encode(
    GpuShown composite,
    ExportFormatSelection format,
  ) => _encodeStill(
    composite,
    format,
    (pixels) => _builder.build(composite: pixels),
  );
}

/// The engine's JPEG encoder at [quality], for a picture over its ground —
/// RGB24, as a JPG keeps no alpha. Null = the encoder refused — the file
/// skips rather than lying.
///
/// ⚠️Made out here, so the writer that crosses to the worker carries
/// [quality] and nothing of its caller's scope (`onAWorkerReporting`'s 🚨).
Uint8List? Function(StillPixels picture) _jpgAt(int quality) =>
    (picture) => QaImageEncoder.encodeJpg(
      rgb: picture.pixels,
      width: picture.width,
      height: picture.height,
      quality: quality,
    );
