import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/services/media/viewer_document.dart';

/// A [ViewerDocument] fake driven through
/// [PdfRenderService.debugOpenerOverride]: pages render as solid colored
/// rects via [ui.Picture.toImageSync], so no FFI, no file IO, and no
/// fake-async deadlock (the image exists synchronously).
class FakePdfDocument implements ViewerDocument {
  FakePdfDocument({required this.pageSizes, this.framesPerSecond});

  /// One entry per page, in PDF points.
  final List<ui.Size> pageSizes;

  /// Every render request as (pageIndex, width, height) — resolution
  /// assertions read these.
  final List<(int, int, int)> renderRequests = [];

  bool disposed = false;

  @override
  int get pageCount => pageSizes.length;

  /// The fake stands in for a PDF, which does not play. Tests that need a
  /// playing document set this.
  @override
  final double? framesPerSecond;

  @override
  ui.Size pageSize(int pageIndex) => pageSizes[pageIndex];

  /// The color page [pageIndex] fills with — distinct per page so folding
  /// or misindexed bakes would be visible. 0x35 is coprime with 0xFF, so
  /// the red channel cycles through all 255 values before repeating (the
  /// old 0x40-step version collided every four pages).
  static ui.Color pageColor(int pageIndex) =>
      ui.Color(0xFF000033 | (((0x35 * (pageIndex + 1)) % 0xFF) << 16));

  /// Held renders, keyed by page — a test that needs「this page has not
  /// landed yet」completes them by hand.
  ///
  /// 🚨Without this every render finishes inside the same pump, so the
  /// state a viewer is in WHILE a page is decoding — the one a movie
  /// spends most of its first play in — was unreachable from a test.
  final Map<int, Completer<void>> renderGates = {};

  /// Makes [pageIndex] wait until [releaseRender] is called for it.
  void holdRender(int pageIndex) => renderGates[pageIndex] = Completer<void>();

  void releaseRender(int pageIndex) {
    final gate = renderGates.remove(pageIndex);
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  @override
  Future<ui.Image> renderPage(
    int pageIndex, {
    required int width,
    required int height,
  }) async {
    renderRequests.add((pageIndex, width, height));
    final gate = renderGates[pageIndex];
    if (gate != null) {
      await gate.future;
    }
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

  /// Every region read as (pageIndex, left, top, width, height).
  final List<(int, int, int, int, int)> regionReads = [];

  /// Holds every region read until [releaseRegionReads] — the state a cut
  /// is in while its read is out.
  Completer<void>? regionGate;

  void holdRegionReads() => regionGate = Completer<void>();

  void releaseRegionReads() {
    final gate = regionGate;
    regionGate = null;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  /// The pixel a region read hands back at page pixel ([x], [y]): its own
  /// coordinates in the colour, so a test can tell WHICH source pixels a
  /// piece holds, and at what size.
  static List<int> regionPixel(int pageIndex, int x, int y) => [
    x & 0xFF,
    y & 0xFF,
    (0x35 * (pageIndex + 1)) & 0xFF,
    0xFF,
  ];

  @override
  Future<Uint8List> readRegionRgba(
    int pageIndex, {
    required int left,
    required int top,
    required int width,
    required int height,
  }) async {
    regionReads.add((pageIndex, left, top, width, height));
    final gate = regionGate;
    if (gate != null) {
      await gate.future;
    }
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        rgba.setAll(
          (y * width + x) * 4,
          regionPixel(pageIndex, left + x, top + y),
        );
      }
    }
    return rgba;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
