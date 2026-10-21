import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/argb_channels.dart';
import '../../models/export_format_selection.dart';
import '../../models/layer_blend_mode.dart';
import '../../native/qa_image_encoder.dart';
import '../../services/media/png_writing.dart';
import '../../services/media/still_file_writing.dart';
import '../../services/photoshop/psd_writer.dart';
import 'png_sequence_export_service.dart';
import 'png_srgb.dart';

/// The bytes a still file in [format] is written as, where they are not the
/// default's — the engine PNG ([PngSequenceExportService]); null keeps that.
///
/// ↩️The export window spelled this for itself; it lives here since
/// 「다른 이름으로 저장」 writes the same picture (backlog-21-Q7), so the
/// window's files and Save As's are one encoder.
///
/// 🗣️F-335 (유저 10-10): 「알파채널 아예없는걸 원하거든? RGBA가 아닌 RGB는
/// 그게 효율적이잖아」 → 「그렇게하자」 — a PNG asked for RGB has no alpha
/// channel in the file ([_encodeRgbPng]). The engine's encoder cannot write
/// one: it writes RGBA whatever the picture holds, so it keeps only the PNGs
/// that keep their alpha.
///
/// ⛔A PSD is refused, not left to the engine's PNG: a Photoshop document
/// is its rows, which one picture does not hold — the tab that writes one
/// lays them out for [encodePsd] (I-117).
ExportImageEncoder? stillEncoderFor(ExportFormatSelection format) =>
    switch (format.stillFormat) {
      ExportStillFormat.jpg => (image) => _encodeJpg(image, format),
      ExportStillFormat.png =>
        format.wantsAlpha
            ? null
            : (image) => _encodeRgbPng(image, format.backgroundArgb),
      ExportStillFormat.bmp => (image) => _encodeStill(image, format, encodeBmp),
      ExportStillFormat.tga => (image) => _encodeStill(image, format, encodeTga),
      ExportStillFormat.tiff =>
        (image) => _encodeStill(image, format, encodeTiff),
      ExportStillFormat.webp =>
        (image) => _encodeStill(image, format, encodeWebp),
      ExportStillFormat.psd => throw ArgumentError.value(
        format.stillFormat,
        'format',
        'A PSD is written from its rows (encodePsd), not one picture',
      ),
    };

/// [image] through one of the writers the engine has no encoder for
/// (`still_file_writing.dart`): its colour NOT premultiplied where the file
/// keeps alpha, and laid over the format's background where it does not —
/// the RGB a PNG without alpha is written from ([_overGround]).
///
/// In an isolate, as [_encodeRgbPng] is: a writer walks every byte, and a
/// run of frames would stall the window's cancel.
Future<List<int>?> _encodeStill(
  ui.Image image,
  ExportFormatSelection format,
  Uint8List Function(StillPixels picture) write,
) async {
  final alpha = format.wantsAlpha;
  final data = await image.toByteData(
    format: alpha
        ? ui.ImageByteFormat.rawStraightRgba
        : ui.ImageByteFormat.rawRgba,
  );
  if (data == null) {
    return null;
  }
  final rgba = Uint8List.sublistView(data);
  final width = image.width;
  final height = image.height;
  final ground = format.backgroundArgb;
  return Isolate.run(() {
    if (alpha) {
      return write((pixels: rgba, width: width, height: height, channels: 4));
    }
    final rgb = Uint8List(width * height * 3);
    _overGround(rgba, ground, rgb);
    return write((pixels: rgb, width: width, height: height, channels: 3));
  });
}

/// A row of a layered still file (PSD — I-117): its name, how the file lays
/// it over the rows under it, and its picture — drawn when the file comes
/// to it, whole and in no blend on nothing, and let go once it is packed:
/// one row's pixels at a time ([PsdBuilder]).
typedef ExportLayerRow = ({
  String name,
  double opacity,
  LayerBlendMode blendMode,
  Future<ui.Image> Function() draw,
});

/// A folder of a layered still file — a conte page's strata (I-117): its
/// name, and its rows, bottom-up.
typedef ExportLayerFolder = ({String name, List<ExportLayerRow> rows});

/// The bytes a still in [format] is written as where its picture is laid
/// up of rows: a PSD keeps them apart ([encodePsd] — [rows] is asked only
/// then), every other still is the picture alone ([stillEncoderFor]).
ExportImageEncoder? layeredEncoderFor(
  ExportFormatSelection format,
  List<ExportLayerRow> Function() rows,
) => format.stillFormat == ExportStillFormat.psd
    ? (composite) => encodePsd(composite, format, rows())
    : stillEncoderFor(format);

/// [composite] as a Photoshop document of [rows], bottom-up ([LayeredPsd]).
Future<List<int>?> encodePsd(
  ui.Image composite,
  ExportFormatSelection format,
  List<ExportLayerRow> rows,
) async {
  final document = LayeredPsd(
    width: composite.width,
    height: composite.height,
  );
  return await document.addRows(rows)
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

  /// [rows] over every row laid before them. False where a picture could
  /// not be read: the document is then no document.
  Future<bool> addRows(List<ExportLayerRow> rows) async {
    for (final row in rows) {
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
        blendMode: row.blendMode,
      );
    }
    return true;
  }

  /// [folder] over every row laid before it, its rows inside it — as
  /// [addRows] answers.
  Future<bool> addFolder(ExportLayerFolder folder) async {
    _builder.openGroup(name: folder.name);
    if (!await addRows(folder.rows)) {
      return false;
    }
    _builder.closeGroup();
    return true;
  }

  /// The document over [composite], which is written as every other still
  /// in [format] is ([_encodeStill]).
  Future<List<int>?> encode(
    ui.Image composite,
    ExportFormatSelection format,
  ) => _encodeStill(
    composite,
    format,
    (pixels) => _builder.build(composite: pixels),
  );
}

/// [image] over the format's background as RGB24 for the native stb
/// encoder. Null = no encoder (an older binary) — the file skips rather
/// than lying.
Future<List<int>?> _encodeJpg(
  ui.Image image,
  ExportFormatSelection format,
) async {
  final encoder = QaImageEncoder.instance;
  if (encoder == null) {
    return null;
  }
  final rgba = await _rgbaOf(image);
  if (rgba == null) {
    return null;
  }
  final rgb = Uint8List(image.width * image.height * 3);
  _overGround(rgba, format.backgroundArgb, rgb);
  return encoder.encodeJpg(
    rgb: rgb,
    width: image.width,
    height: image.height,
    quality: format.jpgQuality,
  );
}

/// [image] over [groundArgb] as a PNG of three channels — colour type 2,
/// no alpha at all — with the sRGB stamp every PNG this app hands out
/// carries ([tagPngAsSrgb]).
///
/// The work runs in an isolate of its own: the engine's encoder never held
/// the UI isolate, and five filters over every byte would (about 100 ms a
/// 2436×1678 frame — a run of frames would stall the window's cancel).
Future<List<int>?> _encodeRgbPng(ui.Image image, int groundArgb) async {
  final rgba = await _rgbaOf(image);
  if (rgba == null) {
    return null;
  }
  final picture = (
    rgba: rgba,
    width: image.width,
    height: image.height,
    groundArgb: groundArgb,
  );
  return tagPngAsSrgb(await Isolate.run(() => _rgbPngOf(picture)));
}

/// What [_rgbPngOf] is handed: bytes and numbers, all an isolate can carry.
typedef _RgbPicture = ({
  Uint8List rgba,
  int width,
  int height,
  int groundArgb,
});

/// [picture] as a PNG without alpha, its rows deflated twice in one pass —
/// under libpng's per-row filter guess, and unfiltered — and the smaller
/// kept.
///
/// ⚠️BOTH, because the guess loses to no filter at all on a picture of flat
/// colours and wins on gradients (measured 10-11 against the engine's RGBA
/// PNG of the same picture: a cel 2436×1678 — engine 812,659 B · filtered
/// 732,890 B · unfiltered 588,376 B; a page of lines and boxes the same
/// size — 2,814,565 B · 2,456,257 B · 1,858,095 B; a picture of gradients
/// 1920×1080 — engine 1,180,600 B, this 1,083,146 B). Kept to one, a cel or
/// a gradient each pays for the other's.
Uint8List _rgbPngOf(_RgbPicture picture) {
  final width = picture.width;
  final filtered = PngImageData(width: width, bytesPerPixel: 3);
  final unfiltered = PngImageData(
    width: width,
    bytesPerPixel: 3,
    filtered: false,
  );
  final row = Uint8List(width * 3);
  final stride = width * 4;
  for (var y = 0; y < picture.height; y += 1) {
    _overGround(
      Uint8List.sublistView(picture.rgba, y * stride, (y + 1) * stride),
      picture.groundArgb,
      row,
    );
    filtered.add(row);
    unfiltered.add(row);
  }
  final underFilters = filtered.finish();
  final asTheyAre = unfiltered.finish();
  return encodeStillPng(
    width: width,
    height: picture.height,
    colourType: pngRgb,
    imageData: underFilters.length <= asTheyAre.length
        ? underFilters
        : asTheyAre,
  );
}

/// [image]'s pixels as the engine reads them back — RGBA, the colour
/// premultiplied by its alpha (`ImageByteFormat.rawRgba`).
Future<Uint8List?> _rgbaOf(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data == null ? null : Uint8List.sublistView(data);
}

/// Premultiplied [rgba] laid over [groundArgb] into [rgb], three bytes a
/// pixel.
///
/// ↩️It was the straight-alpha sum, `(c·a + ground·(255−a)) / 255`, on
/// premultiplied bytes — the same answer wherever a pixel is opaque, which
/// is every pixel an opaque ground is drawn under
/// (`ExportFrameRenderer.forFormat`), and too dark anywhere else.
void _overGround(Uint8List rgba, int groundArgb, Uint8List rgb) {
  final red = argbRed(groundArgb);
  final green = argbGreen(groundArgb);
  final blue = argbBlue(groundArgb);
  for (var p = 0, q = 0; p < rgba.length; p += 4, q += 3) {
    final rest = 255 - rgba[p + 3];
    if (rest == 0) {
      rgb[q] = rgba[p];
      rgb[q + 1] = rgba[p + 1];
      rgb[q + 2] = rgba[p + 2];
    } else {
      rgb[q] = rgba[p] + red * rest ~/ 255;
      rgb[q + 1] = rgba[p + 1] + green * rest ~/ 255;
      rgb[q + 2] = rgba[p + 2] + blue * rest ~/ 255;
    }
  }
}
