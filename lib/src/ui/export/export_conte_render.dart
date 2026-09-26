import 'dart:ui' as ui;

import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/conte/conte_page_marks.dart';
import '../../models/conte/conte_sheet_layout.dart';
import '../../models/conte/conte_sheet_source.dart';
import '../../models/conte/conte_words.dart';
import '../../models/sheet_marks.dart';
import '../../services/import/raster_cel_import.dart' show readImageFileOrNull;
import '../conte/conte_page_painter.dart';
import 'offscreen_raster.dart';

/// Every media image [pages] print — the company logo, the cover's picture
/// — decoded by the asset path its mark names; one that cannot be read is
/// absent, and its place prints empty, as on the panel.
///
/// ⛔THE MARKS SAY WHICH. The exports read the images the pages NAME rather
/// than a list of their own: a list kept here printed the logo and dropped
/// the cover's picture the panel showed. The caller owns the images.
Future<Map<String, ui.Image>> readContePageImages(
  Iterable<ContePageLayout> pages,
  ConteSheetSource source,
  ConteWords words,
) async {
  final images = <String, ui.Image>{};
  final asked = <String>{};
  for (final page in pages) {
    for (final mark in contePageMarks(page, source, words: words)) {
      if (mark is SheetImage && asked.add(mark.assetPath)) {
        final image = await readImageFileOrNull(mark.assetPath);
        if (image != null) {
          images[mark.assetPath] = image;
        }
      }
    }
  }
  return images;
}

/// Renders one conte page offscreen with the panel's own renderer
/// ([ContePagePainter], fit-to-size path) — what the Conte tab shows is
/// what exports, the timesheet render's rule. Sheet ink (R5) rides
/// [inkImageFor] into the same painter, so the PNG carries it for free.
///
/// [scale] rasters at a multiple of the page's logical point size;
/// [outputSize] (previews) wins over it when set.
Future<ui.Image> renderContePageImage({
  required ContePageLayout page,
  required ConteSheetSource source,
  ui.Image? Function(String cutId, int pictureFrame)? pictureFor,
  ui.Image? Function(String assetPath)? imageFor,
  ui.Image? Function(BrushFrameKey key)? inkImageFor,
  double scale = 1,
  CanvasSize? outputSize,
  required ConteWords words,
}) {
  final metrics = page.metrics;
  final (:width, :height) = offscreenRasterSize(
    naturalWidth: metrics.pageWidth,
    naturalHeight: metrics.pageHeight,
    scale: scale,
    outputSize: outputSize,
  );
  return rasterizeOffscreen(
    width: width,
    height: height,
    paint: (canvas) => ContePagePainter(
      page: page,
      source: source,
      pictureFor: pictureFor,
      imageFor: imageFor,
      inkImageFor: inkImageFor,
      words: words,
    ).paint(canvas, ui.Size(width.toDouble(), height.toDouble())),
  );
}
