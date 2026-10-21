import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextStyle;

import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/cel_photo.dart';
import '../../models/cut.dart';
import '../../models/sheet_marks.dart';
import '../../models/sheet_paint_layer.dart';
import '../../models/timesheet_document.dart';
import '../../models/timesheet_words.dart';
import '../sheet/sheet_image_cache.dart'
    show SheetImageRun, paintWithSheetImages;
import '../timesheet/timesheet_document_painter.dart';
import 'offscreen_raster.dart';

/// One sheet PAGE exporting as an image (EX6): the same paper the
/// timesheet panel draws, offscreen. A single-page cut names plainly;
/// page splits carry `_p<n>` (the panel's page discipline).
class ExportTimesheetPageTask {
  const ExportTimesheetPageTask({
    required this.cut,
    required this.cutLabel,
    required this.cutStartFrame,
    required this.pageIndex,
    required this.pageCount,
    required this.fileName,
  });

  final Cut cut;

  /// The cut NUMBER as the sheet writes it — the cut's own name, which is
  /// what the timesheet panel has always printed.
  final String cutLabel;

  /// The cut's start on the TRACK axis (leading gaps included) — the SE
  /// column reads track-global spans.
  final int cutStartFrame;

  final int pageIndex;
  final int pageCount;
  final String fileName;
}

/// Renders one page of [document] at its PAPER'S PIXELS — the paper at its
/// own resolution, the panel's 100%
/// (`TimesheetDocumentLayout.paperPixelSize`) — or at [outputSize], for a
/// preview. The painter's strata are exactly what the panel shows — the
/// export IS the panel's picture, no second sheet layout to disagree with
/// it — the saved [ink] included: the windows it shows through (the
/// panel's own walk), each window's baked raster and the photos laid under
/// it (I-97), whose files are the ones it asks [images] for. [layers]
/// draws those strata alone — a Photoshop document's rows (I-117); null
/// draws the page whole.
///
/// ↩️A scale multiplied the page's size in the FORM'S UNITS, which was the
/// paper while a unit was a pixel of it. F-294 gave the paper pixels of its
/// own and left that behind: a sheet exported at 1x came out 1113×1574 (유저
/// 2026-10-05: 「최신빌드로 시트 출력하면 1113x1574인데? … 1x하더라도
/// 100%크기인채로 출력해야되니 아까 말한대로 출력되야하는거아닌가」). The
/// scale itself went on 2026-10-06 ([offscreenRasterSize]).
Future<ui.Image> renderTimesheetPageImage({
  required TimesheetDocument document,
  required TimesheetDocumentLayout layout,
  required int pageIndex,
  required TimesheetWords words,
  required TextStyle face,
  CanvasSize? outputSize,
  ({
    List<SheetInk> windows,
    ui.Image? Function(BrushFrameKey key) rasterFor,
    List<CelPhoto> Function(BrushFrameKey key) photosFor,
  })?
  ink,
  SheetImageRun? images,
  Set<SheetPaintLayer>? layers,
}) {
  final page = layout.pageRect(pageIndex);
  final paper = layout.paperPixelSize;
  final (:width, :height) = offscreenRasterSize(
    naturalWidth: paper.width.toDouble(),
    naturalHeight: paper.height.toDouble(),
    outputSize: outputSize,
  );
  // The panel's strata, in the panel's order ([SheetStratum]), which
  // differ in nothing but the strata.
  TimesheetDocumentPainter painterOf(Set<SheetPaintLayer> drawn) =>
      TimesheetDocumentPainter(
        document: document,
        layout: layout,
        face: face,
        layers: drawn,
        words: words,
        ink: ink?.windows ?? const [],
        inkImageFor: ink?.rasterFor,
        inkPhotosFor: ink?.photosFor,
        imageFor: images?.imageFor,
        // The image's pixels to a unit of the sheet, as it lays the page
        // below — what the photos are sampled for.
        effectiveRatio: math.min(width / page.width, height / page.height),
      );
  void paintPage(ui.Canvas canvas) {
    canvas.scale(width / page.width, height / page.height);
    canvas.translate(-page.left, -page.top);
    canvas.clipRect(page);
    for (final stratum in SheetStratum.values) {
      final drawn = {
        for (final layer in stratum.layers)
          if (drawsSheetLayer(layers, layer)) layer,
      };
      if (drawn.isNotEmpty) {
        painterOf(drawn).paint(canvas, layout.documentSize);
      }
    }
  }

  return rasterizeOffscreen(
    width: width,
    height: height,
    paint: (canvas) => paintWithSheetImages(canvas, images, paintPage),
  );
}
