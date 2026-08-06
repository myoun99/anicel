import 'dart:ui' as ui;

import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/timesheet_document.dart';
import '../timesheet/timesheet_document_painter.dart';
import '../timesheet/timesheet_notation.dart';

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
/// size. The painter pair (form + content) is exactly what the panel
/// shows — the export IS the panel's picture, no second sheet layout to
/// disagree with it.
Future<ui.Image> renderTimesheetPageImage({
  required TimesheetDocument document,
  required TimesheetDocumentLayout layout,
  required int pageIndex,
  required TimesheetNotation notation,
  double scale = 2,
  CanvasSize? outputSize,
}) async {
  final page = layout.pageRect(pageIndex);
  final width = outputSize?.width ?? (page.width * scale).round();
  final height = outputSize?.height ?? (page.height * scale).round();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(width / page.width, height / page.height);
  canvas.translate(-page.left, -page.top);
  canvas.clipRect(page);
  TimesheetDocumentPainter(
    document: document,
    layout: layout,
    layers: const {SheetPaintLayer.paper, SheetPaintLayer.form},
    notation: notation,
  ).paint(canvas, layout.documentSize);
  TimesheetDocumentPainter(
    document: document,
    layout: layout,
    layers: const {SheetPaintLayer.content},
    notation: notation,
  ).paint(canvas, layout.documentSize);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}
