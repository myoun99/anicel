import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/argb_channels.dart';
import '../../models/export_format_selection.dart';
import '../../native/qa_image_encoder.dart';
import 'png_sequence_export_service.dart';

/// The bytes a still file in [format] is written as, where they are not the
/// default's — the engine PNG ([PngSequenceExportService]); null keeps that.
///
/// ↩️The export window spelled this for itself; it lives here since
/// 「다른 이름으로 저장」 writes the same picture (backlog-21-Q7), so the
/// window's files and Save As's are one encoder.
ExportImageEncoder? stillEncoderFor(ExportFormatSelection format) {
  if (format.stillFormat != ExportStillFormat.jpg) {
    return null;
  }
  return (image) => _encodeJpg(image, format);
}

/// Flattens un-premultiplied RGBA over the format's background and
/// hands RGB24 to the native stb encoder. Null = no encoder (an older
/// binary) — the file skips rather than lying.
Future<List<int>?> _encodeJpg(
  ui.Image image,
  ExportFormatSelection format,
) async {
  final encoder = QaImageEncoder.instance;
  if (encoder == null) {
    return null;
  }
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) {
    return null;
  }
  final rgba = data.buffer.asUint8List();
  final pixelCount = image.width * image.height;
  final rgb = Uint8List(pixelCount * 3);
  final bg = format.backgroundArgb;
  final bgR = argbRed(bg);
  final bgG = argbGreen(bg);
  final bgB = argbBlue(bg);
  for (var i = 0; i < pixelCount; i += 1) {
    final a = rgba[i * 4 + 3];
    if (a == 255) {
      rgb[i * 3] = rgba[i * 4];
      rgb[i * 3 + 1] = rgba[i * 4 + 1];
      rgb[i * 3 + 2] = rgba[i * 4 + 2];
    } else {
      rgb[i * 3] = (rgba[i * 4] * a + bgR * (255 - a)) ~/ 255;
      rgb[i * 3 + 1] = (rgba[i * 4 + 1] * a + bgG * (255 - a)) ~/ 255;
      rgb[i * 3 + 2] = (rgba[i * 4 + 2] * a + bgB * (255 - a)) ~/ 255;
    }
  }
  return encoder.encodeJpg(
    rgb: rgb,
    width: image.width,
    height: image.height,
    quality: format.jpgQuality,
  );
}
