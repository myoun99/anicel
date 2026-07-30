import 'dart:ui' as ui;

import '../../models/canvas_size.dart';
import '../../services/se_name_tag_plan.dart';
import 'text_cel_render.dart';

/// Draws the SE name tags in CANVAS coordinates (R5b, §6-z15) — the one
/// implementation every surface calls, so the editing canvas, playback,
/// the parked multitrack stack and the export can never disagree on where
/// a tag sits or how it looks.
///
/// The caller has already set up whatever transform puts canvas space on
/// screen (viewport, camera projection, cut pose); this only paints.
void paintSeNameTags(
  ui.Canvas canvas, {
  required List<ResolvedSeNameTag> tags,
  required CanvasSize canvasSize,
}) {
  for (final tag in tags) {
    final layout = layoutTextCel(
      content: tag.content,
      canvas: canvasSize,
      maxWidth: tag.widthBudget,
    );
    try {
      layout.paint(canvas);
    } finally {
      layout.dispose();
    }
  }
}
