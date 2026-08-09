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
///
/// GEOMETRY (R5 #7, the user's rule, corrected twice on the mockup):
/// the tag's stored position is the name BOX's exact geometric centre, and
/// the dialogue hangs off the box's right edge, vertically centred on it.
/// So turning the dialogue off leaves the box exactly where it was —
/// anchoring on the pair's combined centre would have slid it.
///
/// The placement lives here rather than in the plan because it needs the
/// laid-out box, and nothing knows how wide a box is until it is measured.
void paintSeNameTags(
  ui.Canvas canvas, {
  required List<ResolvedSeNameTag> tags,
  required CanvasSize canvasSize,
}) {
  for (final tag in tags) {
    final layouts = <TextCelLayout>[];
    final anchor = seNameTagAnchorOf(tag, canvasSize: canvasSize);
    try {
      // The name is laid out once to measure, then MOVED so its ink (box
      // included) is centred on the anchor.
      var nameInk = ui.Rect.fromLTWH(anchor.dx, anchor.dy, 0, 0);
      if (tag.content.text.isNotEmpty) {
        final probe = layoutTextCel(
          content: tag.content.copyWith(position: anchor),
          canvas: canvasSize,
          maxWidth: tag.widthBudget,
        );
        final drift = probe.inkBounds.center - anchor;
        probe.dispose();
        final name = layoutTextCel(
          content: tag.content.copyWith(position: anchor - drift),
          canvas: canvasSize,
          maxWidth: tag.widthBudget,
        );
        layouts.add(name);
        nameInk = name.inkBounds;
      }
      // With no name the box is a zero-width sliver AT the anchor, so the
      // line still hangs off "the box's right edge" — one rule, not two.

      final line = tag.line;
      if (line != null && line.text.isNotEmpty) {
        final probe = layoutTextCel(
          content: line.copyWith(position: anchor),
          canvas: canvasSize,
          maxWidth: tag.widthBudget,
        );
        final gap = line.style.fontSize * 0.3;
        // Left edge on the box's right edge; vertically centred on the box
        // so a taller line reads as sitting beside the name, not under it.
        final shift = ui.Offset(
          nameInk.right + gap - probe.inkBounds.left,
          nameInk.center.dy - probe.inkBounds.center.dy,
        );
        probe.dispose();
        layouts.add(
          layoutTextCel(
            content: line.copyWith(position: anchor + shift),
            canvas: canvasSize,
            maxWidth: tag.widthBudget,
          ),
        );
      }

      for (final layout in layouts) {
        layout.paint(canvas);
      }
    } finally {
      for (final layout in layouts) {
        layout.dispose();
      }
    }
  }
}

/// The tag's anchor — the name box's centre. Null position means "centre
/// on the canvas", the grammar [TextCelContent] already speaks.
ui.Offset seNameTagAnchorOf(
  ResolvedSeNameTag tag, {
  required CanvasSize canvasSize,
}) =>
    tag.content.position ??
    ui.Offset(canvasSize.width / 2, canvasSize.height / 2);

/// Where the name BOX lands for [tag] — the rectangle the anchor centres,
/// exposed so a test can state the rule the painter follows instead of
/// re-deriving it, and so the canvas gizmo can frame the same box.
ui.Rect seNameTagBoxBounds(
  ResolvedSeNameTag tag, {
  required CanvasSize canvasSize,
}) {
  final anchor = seNameTagAnchorOf(tag, canvasSize: canvasSize);
  if (tag.content.text.isEmpty) {
    return ui.Rect.fromLTWH(anchor.dx, anchor.dy, 0, 0);
  }
  final probe = layoutTextCel(
    content: tag.content.copyWith(position: anchor),
    canvas: canvasSize,
    maxWidth: tag.widthBudget,
  );
  final ink = probe.inkBounds;
  probe.dispose();
  return ui.Rect.fromCenter(
    center: anchor,
    width: ink.width,
    height: ink.height,
  );
}

