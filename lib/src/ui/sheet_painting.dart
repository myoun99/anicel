import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/canvas_viewport.dart';
import 'canvas/viewport_canvas_transform.dart';

/// Draws one baked ink window into [rect]: the raster is [scale]× the
/// window in each axis, clipped to the window so a stroke that ran past
/// the box does not bleed into its neighbour.
///
/// ⛔BOTH SHEETS DRAW INK THIS WAY. The conte page and the cut envelope
/// each wrote out the save / clip / drawImageRect / restore with the same
/// medium filter. The SOURCE rect is the part that has to agree with
/// whatever rendered the ink, so two copies of it is two chances to scale
/// a sheet's ink differently from the sheet it was drawn on.
void paintSheetInkWindow(
  Canvas canvas,
  ui.Image image,
  Rect rect,
  double scale,
) {
  canvas.save();
  canvas.clipRect(rect);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, rect.width * scale, rect.height * scale),
    rect,
    Paint()..filterQuality = FilterQuality.medium,
  );
  canvas.restore();
}

/// Lays down a sheet's PAPER — the one way the timesheet, the conte and the
/// cut envelope fill it.
///
/// 🚨NOT anti-aliased (F-179, 유저 2026-09-25: 「용지 외곽에 반투명 라인
/// 있는데 이런거 필요없어」). A sheet's view never rotates, and its paper
/// edge lands wherever zoom × page size puts it — a fractional device
/// position more often than not. An anti-aliased fill covers that pixel
/// partly: a one-pixel line of paper blended over the backdrop, around
/// every page. Cut on the pixel centres, the edge is the same hard boundary
/// F-67 gives the drawing canvas's paper.
///
/// ↩️The timesheet also stroked a 1.4px border ON its page edge, half of
/// it over the backdrop — the other line. It is gone, not moved here.
void paintSheetPaper(Canvas canvas, Rect rect, Color color) {
  canvas.drawRect(
    rect,
    Paint()
      ..color = color
      ..isAntiAlias = false,
  );
}

/// Puts [canvas] into a sheet's PAPER units, either through the panel's
/// live viewport or by fitting the paper into [size].
///
/// ⛔BOTH SHEETS OPEN THIS WAY, AND THE COMMENT THAT MATTERS IS THE SHARED
/// ONE: the snap ALREADY HAPPENED at the host, so this viewport and the
/// one the ink windows derive from are the same value — which is what
/// keeps written ink on its cell. Passing the ratio here keeps that snap
/// idempotent rather than re-rounding to a coarser grid. Written out per
/// sheet, one of them starts re-rounding and its ink drifts off the boxes.
///
/// With no viewport it is the EXPORT/PREVIEW path: the export renders at
/// paper size (scale 1) and a preview at a fraction of it, both from these
/// same paper units.
void enterSheetPaperSpace(
  Canvas canvas,
  Size size,
  ({CanvasViewport? viewport, double devicePixelRatio, Size paper}) sheet,
) {
  final viewport = sheet.viewport;
  if (viewport != null) {
    canvas.clipRect(Offset.zero & size);
    applyViewportTransform(
      canvas,
      viewport,
      devicePixelRatio: sheet.devicePixelRatio,
    );
    return;
  }
  final scale = math.min(
    size.width / sheet.paper.width,
    size.height / sheet.paper.height,
  );
  canvas.scale(scale, scale);
}
