import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextStyle;

import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/sheet_marks.dart';
import '../../models/sheet_paint_layer.dart';
import '../../models/timesheet_document.dart';
import '../timesheet/timesheet_document_painter.dart';
import '../timesheet/timesheet_notation.dart';
import 'offscreen_raster.dart';

/// One sheet PAGE exporting as an image (EX6): the same B4 paper the
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

/// Renders one page of [document] at [scale]× the panel's logical paper
/// size. The painter's strata are exactly what the panel shows — the
/// export IS the panel's picture, no second sheet layout to disagree with
/// it — the saved [ink] included: the windows it shows through (the
/// panel's own walk) and each window's baked raster.
Future<ui.Image> renderTimesheetPageImage({
  required TimesheetDocument document,
  required TimesheetDocumentLayout layout,
  required int pageIndex,
  required TimesheetNotation notation,
  required TextStyle face,
  double scale = 2,
  CanvasSize? outputSize,
  ({List<SheetInk> windows, ui.Image? Function(BrushFrameKey key) imageFor})?
  ink,
}) {
  final page = layout.pageRect(pageIndex);
  final (:width, :height) = offscreenRasterSize(
    naturalWidth: page.width,
    naturalHeight: page.height,
    scale: scale,
    outputSize: outputSize,
  );
  // The panel's strata, in the panel's order ([SheetStratum]), which
  // differ in nothing but the strata.
  TimesheetDocumentPainter painterOf(SheetStratum stratum) =>
      TimesheetDocumentPainter(
        document: document,
        layout: layout,
        face: face,
        layers: stratum.layers,
        notation: notation,
        ink: ink?.windows ?? const [],
        inkImageFor: ink?.imageFor,
      );
  return rasterizeOffscreen(
    width: width,
    height: height,
    paint: (canvas) {
      canvas.scale(width / page.width, height / page.height);
      canvas.translate(-page.left, -page.top);
      canvas.clipRect(page);
      for (final stratum in SheetStratum.values) {
        painterOf(stratum).paint(canvas, layout.documentSize);
      }
    },
  );
}
