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
