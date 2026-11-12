import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:gpu_engine/gpu_engine.dart' show GpuShown;

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
      ExportStillFormat.jpg => (frame) => _encodeJpg(frame, format),
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

/// [frame] through one of the writers the engine has no encoder for
/// (`still_file_writing.dart`): its colour straight where the file keeps
/// alpha ([straightOf]), and laid over the format's background where it
/// does not ([rgbOverGroundOf]).
///
/// In an isolate: a writer walks every byte, and a run of frames would
/// stall the window's cancel.
Future<List<int>?> _encodeStill(
  GpuShown frame,
  ExportFormatSelection format,
  Uint8List Function(StillPixels picture) write,
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
  return Isolate.run(() => write(picture));
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
/// comes to it, whole and in no blend on nothing, and let go once it is
/// packed: one row's pixels at a time ([PsdBuilder]).
final class ExportLayerRow extends ExportLayerNode {
  const ExportLayerRow({
    required super.name,
    super.opacity = 1,
    super.blendMode = LayerBlendMode.normal,
    super.visible = true,
    super.clipped = false,
    required this.draw,
  });

  final Future<ui.Image> Function() draw;
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
  return await document.add(nodes)
      ? document.encode(composite, format)
      : null;
}

/// A Photoshop document laid up row by row, bottom-up (I-117) — for a
/// caller that lays it in steps of its own, as the conte's pages are. Each
/// row is drawn, read back straight — as a layer keeps its colour — and
/// packed in an isolate before the next is drawn ([packPsdLayer]).
final class LayeredPsd {
  LayeredPsd({required int width, required int height})
    : _builder = PsdBuilder(width: width, height: height);

  final PsdBuilder _builder;

  /// [nodes] over every row laid before them, each folder's inside it.
  /// False where a picture could not be read: the document is then no
  /// document.
  Future<bool> add(List<ExportLayerNode> nodes) async {
    for (final node in nodes) {
      final laid = await switch (node) {
        final ExportLayerRow row => _addRow(row),
        final ExportLayerFolder folder => _addFolder(folder),
      };
      if (!laid) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _addRow(ExportLayerRow row) async {
    final picture = await row.draw();
    final width = picture.width;
    final height = picture.height;
    final ByteData? data;
    try {
      data = await picture.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
    } finally {
      picture.dispose();
    }
    if (data == null) {
      return false;
    }
    final rgba = Uint8List.sublistView(data);
    _builder.addLayer(
      name: row.name,
      pixels: await Isolate.run(
        () => packPsdLayer(
          (pixels: rgba, width: width, height: height, channels: 4),
        ),
      ),
      opacity: row.opacity,
      visible: row.visible,
      blendMode: row.blendMode,
      clipped: row.clipped,
    );
    return true;
  }

  Future<bool> _addFolder(ExportLayerFolder folder) async {
    _builder.openGroup(
      name: folder.name,
      opacity: folder.opacity,
      visible: folder.visible,
      blendMode: folder.blendMode,
      clipped: folder.clipped,
    );
    if (!await add(folder.children)) {
      return false;
    }
    _builder.closeGroup();
    return true;
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

/// [frame] over the format's background as RGB24 for the engine's JPEG
/// encoder ([rgbOverGroundOf]). Null = the encoder refused — the file
/// skips rather than lying.
Future<List<int>?> _encodeJpg(
  GpuShown frame,
  ExportFormatSelection format,
) async => QaImageEncoder.encodeJpg(
  rgb: rgbOverGroundOf(frame, format.backgroundArgb),
  width: frame.width,
  height: frame.height,
  quality: format.jpgQuality,
);
