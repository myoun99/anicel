import 'dart:typed_data';
import 'dart:ui' as ui;

import '../photoshop/psd_image.dart';
import '../straight_rgba_image.dart';
import 'viewer_document.dart';

/// A Photoshop document as a page: its composite, read once and kept as the
/// straight RGBA the reader gives back, rendered at the size asked — a
/// premultiplied copy each time, as a movie frame is.
///
/// ⚠️There is no smaller read. The parse takes the whole file and answers
/// with the picture at its own size, which is the price every entry point
/// already pays for a PSD ([decodePsdCompositeImage]); what this keeps is
/// that one buffer, where the platform codec's document keeps the encoded
/// file ([ImageViewerDocument]).
final class PsdCompositeDocument implements ViewerDocument {
  PsdCompositeDocument._(this._rgba, this._width, this._height);

  /// Reads the composite out of [bytes] — a file that begins like a
  /// Photoshop document ([looksLikePsdBytes]).
  static Future<PsdCompositeDocument> read(Uint8List bytes) async {
    final composite = await readPsdComposite(bytes);
    return PsdCompositeDocument._(
      composite.rgba,
      composite.width,
      composite.height,
    );
  }

  final Uint8List _rgba;
  final int _width;
  final int _height;

  @override
  int get pageCount => 1;

  @override
  double? get framesPerSecond => null;

  @override
  ui.Size pageSize(int pageIndex) =>
      ui.Size(_width.toDouble(), _height.toDouble());

  @override
  Future<ui.Image> renderPage(
    int pageIndex, {
    required int width,
    required int height,
  }) => decodeStraightRgbaImage(
    rgba: _rgba,
    width: _width,
    height: _height,
    targetWidth: width,
    targetHeight: height,
  );

  /// The composite is already the page at its own size, as bytes — the
  /// box is copied straight out of it.
  @override
  Future<Uint8List> readRegionRgba(
    int pageIndex,
    ({int left, int top, int width, int height}) box,
  ) async => cropStraightRgba(_rgba, sourceWidth: _width, box: box);

  @override
  Future<void> dispose() async {}
}
