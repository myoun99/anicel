import 'dart:ui' as ui;

import '../../models/canvas_size.dart';
import '../../models/conte/conte_sheet_layout.dart';
import '../../models/conte/conte_sheet_source.dart';
import '../conte/conte_page_painter.dart';

/// Renders one conte page offscreen with the panel's own renderer
/// ([ContePagePainter], fit-to-size path) — what the Conte tab shows is
/// what exports, the timesheet render's rule.
///
/// [scale] rasters at a multiple of the page's logical point size;
/// [outputSize] (previews) wins over it when set.
Future<ui.Image> renderContePageImage({
  required ContePageLayout page,
  required ConteSheetSource source,
  ui.Image? Function(String cutId, int pictureFrame)? pictureFor,
  double scale = 1,
  CanvasSize? outputSize,
}) {
  final metrics = page.metrics;
  final width = outputSize?.width ?? (metrics.pageWidth * scale).round();
  final height = outputSize?.height ?? (metrics.pageHeight * scale).round();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  ContePagePainter(
    page: page,
    source: source,
    pictureFor: pictureFor,
  ).paint(canvas, ui.Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  try {
    return picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}
