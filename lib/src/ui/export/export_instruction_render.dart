import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../models/canvas_size.dart';
import 'export_cel_group_plan.dart';
import 'offscreen_raster.dart';

/// Renders one instruction event (지시 — PAN etc.) as an image cel for
/// the 撮影 hand-off: the row text large over a spanning arrow, the
/// covered length beside it. Instruction rows carry writing, not
/// strokes — this IS their picture.
Future<ui.Image> renderInstructionCelImage({
  required ExportInstructionTask task,
  required CanvasSize size,
  ui.Color? background,
}) => rasterizeOffscreen(
  width: size.width,
  height: size.height,
  paint: (canvas) => _paintInstructionCel(
    canvas,
    task: task,
    size: size,
    background: background,
  ),
);

void _paintInstructionCel(
  ui.Canvas canvas, {
  required ExportInstructionTask task,
  required CanvasSize size,
  required ui.Color? background,
}) {
  final width = size.width.toDouble();
  final height = size.height.toDouble();
  if (background != null && background.a > 0) {
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width, height),
      ui.Paint()..color = background,
    );
  }
  const ink = ui.Color(0xFFC02020);
  final labelPainter = TextPainter(
    text: TextSpan(
      text: task.label,
      style: TextStyle(
        color: ink,
        fontSize: (height * 0.16).clamp(10.0, 96.0),
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width * 0.9);
  final framesPainter = TextPainter(
    text: TextSpan(
      text: '${task.length}K',
      style: TextStyle(
        color: ink,
        fontSize: (height * 0.08).clamp(8.0, 48.0),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final centerY = height / 2;
  labelPainter.paint(
    canvas,
    ui.Offset(
      (width - labelPainter.width) / 2,
      centerY - labelPainter.height - height * 0.04,
    ),
  );
  // The spanning arrow under the writing (the sheet gesture).
  final arrowY = centerY + height * 0.06;
  final arrowLeft = width * 0.18;
  final arrowRight = width * 0.82;
  final stroke = ui.Paint()
    ..color = ink
    ..strokeWidth = (height * 0.012).clamp(1.5, 6.0)
    ..strokeCap = ui.StrokeCap.round;
  canvas.drawLine(
    ui.Offset(arrowLeft, arrowY),
    ui.Offset(arrowRight, arrowY),
    stroke,
  );
  final head = (height * 0.03).clamp(4.0, 24.0);
  canvas.drawLine(
    ui.Offset(arrowRight, arrowY),
    ui.Offset(arrowRight - head, arrowY - head * 0.6),
    stroke,
  );
  canvas.drawLine(
    ui.Offset(arrowRight, arrowY),
    ui.Offset(arrowRight - head, arrowY + head * 0.6),
    stroke,
  );
  framesPainter.paint(
    canvas,
    ui.Offset(
      arrowRight - framesPainter.width,
      arrowY + height * 0.03,
    ),
  );
}
