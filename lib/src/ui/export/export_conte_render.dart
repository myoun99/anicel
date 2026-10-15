import 'dart:ui' as ui;

import '../../models/brush_frame_key.dart';
import '../../models/cel_photo.dart';
import '../../models/canvas_size.dart';
import '../../models/conte/conte_page_marks.dart';
import '../../models/conte/conte_sheet_layout.dart';
import '../../models/conte/conte_sheet_source.dart';
import '../../models/conte/conte_words.dart';
import '../../models/sheet_marks.dart';
import '../conte/conte_page_painter.dart';
import '../sheet/sheet_image_cache.dart'
    show SheetImageRun, paintWithSheetImages;
import '../sheet_painting.dart' show SheetPictureLookup, SheetPictureOverInk;
import 'offscreen_raster.dart';

/// The asset path of every media image [pages] print — the company logo,
/// the cover's picture — as its mark names it: what the PDF carries whole.
///
/// ⛔THE MARKS SAY WHICH. The exports read the images the pages NAME rather
/// than a list of their own: a list kept here printed the logo and dropped
/// the cover's picture the panel showed. (A page image is told by its
/// painter instead — [SheetImageRun].)
Set<String> contePageImagePaths(
  Iterable<ContePageLayout> pages,
  ConteSheetSource source,
  ConteWords words,
) => {
  for (final page in pages)
    for (final mark in contePageMarks(page, source, words: words))
      if (mark is SheetImage) mark.assetPath,
};

/// Renders one conte page offscreen with the panel's own renderer
/// ([ContePagePainter], fit-to-size path) — what the Conte tab shows is
/// what exports, the timesheet render's rule. Sheet ink (R5) rides
/// [inkImageFor] into the same painter — the photos on it [inkPhotosFor]
/// (I-97) — so the PNG carries it for free; the media images it prints, the
/// photos' files among them, are the ones it asks [images] for.
///
/// The page rasters at its PAPER'S PIXELS — the paper at its own
/// resolution, the panel's 100% (`ConteSheetMetrics.paperPixelSize`, F-294;
/// ↩️it multiplied the page's size in points, 595×842 at 1x) — or at
/// [outputSize], for a preview.
Future<ui.Image> renderContePageImage({
  required ContePageLayout page,
  required ConteSheetSource source,
  SheetPictureLookup? pictureFor,
  SheetImageRun? images,
  ui.Image? Function(BrushFrameKey key)? inkImageFor,
  List<CelPhoto> Function(BrushFrameKey key)? inkPhotosFor,
  List<SheetPictureOverInk> picturesOverInk = const [],
  CanvasSize? outputSize,
  required ConteWords words,
}) {
  final metrics = page.metrics;
  final paper = metrics.paperPixelSize;
  final (:width, :height) = offscreenRasterSize(
    naturalWidth: paper.width.toDouble(),
    naturalHeight: paper.height.toDouble(),
    outputSize: outputSize,
  );
  void paintPage(ui.Canvas canvas) => ContePagePainter(
    page: page,
    source: source,
    pictureFor: pictureFor,
    imageFor: images?.imageFor,
    inkImageFor: inkImageFor,
    inkPhotosFor: inkPhotosFor,
    picturesOverInk: picturesOverInk,
    words: words,
  ).paint(canvas, ui.Size(width.toDouble(), height.toDouble()));
  return rasterizeOffscreen(
    width: width,
    height: height,
    paint: (canvas) => paintWithSheetImages(canvas, images, paintPage),
  );
}
