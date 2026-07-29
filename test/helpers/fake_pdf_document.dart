import 'dart:ui' as ui;

import 'package:anicel/src/services/pdf/pdf_render_service.dart';

/// A [PdfDocumentHandle] fake driven through
/// [PdfRenderService.debugOpenerOverride]: pages render as solid colored
/// rects via [ui.Picture.toImageSync], so no FFI, no file IO, and no
/// fake-async deadlock (the image exists synchronously).
class FakePdfDocument implements PdfDocumentHandle {
  FakePdfDocument({required this.pageSizes});

  /// One entry per page, in PDF points.
  final List<ui.Size> pageSizes;

  /// Every render request as (pageIndex, width, height) — resolution
  /// assertions read these.
  final List<(int, int, int)> renderRequests = [];

  bool disposed = false;

  @override
  int get pageCount => pageSizes.length;

  @override
  ui.Size pageSize(int pageIndex) => pageSizes[pageIndex];

  /// The color page [pageIndex] fills with (distinct per page so folding
  /// or misindexed bakes would be visible).
  static ui.Color pageColor(int pageIndex) =>
      ui.Color(0xFF000000 | ((0x40 * (pageIndex + 1)) & 0xFF) << 16 | 0x33);

  @override
  Future<ui.Image> renderPage(
    int pageIndex, {
    required int width,
    required int height,
  }) async {
    renderRequests.add((pageIndex, width, height));
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = pageColor(pageIndex),
    );
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(width, height);
    } finally {
      picture.dispose();
    }
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
