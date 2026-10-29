import 'dart:ui' as ui;

import '../../models/canvas_size.dart';
import '../../models/composite_tree.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/pasteboard_bounds.dart' show PasteboardBounds;
import '../../models/text_cel_style.dart' show TextCelContent;
import '../../services/composite_effect_paint.dart';
import '../../services/layer_pose_matrix.dart' show placementMatrix;
import '../../services/se_name_tag_plan.dart';
import '../canvas/subtree_image_composite.dart';
import 'text_cel_render.dart';

/// Draws the SE name tags (R5b, §6-z15) — the one implementation every
/// surface calls, so the editing canvas, playback, the parked multitrack
/// stack and the export can never disagree on where a tag sits or how it
/// looks.
///
/// The caller has already set up whatever transform puts CANVAS space on
/// screen (viewport, camera projection, cut pose); each tag is laid by its
/// row's transform in its shot, and this lays it on the canvas through the
/// tag's own [ResolvedSeNameTag.placement] before it paints (I-67-Q1,
/// F-387). Positions and sizes below are the tag's own. [rasterScale] is
/// how many device pixels a canvas pixel covers under that transform — the
/// scale a tag that has to be one picture rasters at.
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
  required double rasterScale,
}) {
  for (final tag in tags) {
    if (tag.opacity <= 0) {
      continue;
    }
    _composite(
      canvas,
      tag,
      canvasSize: canvasSize,
      rasterScale: rasterScale,
    );
  }
}

/// [tag]'s picture composited as a layer's is — its opacity and its effect
/// chain on the tag as ONE picture, the way a folder takes its members: a
/// sub-tree rastered whole ([drawSubtreeAsImage]), so the box under the name
/// is not seen through the name, and a blur reads both. It is laid normal,
/// whatever the row's blend ([ResolvedSeNameTag.opacity] has the 🗣️F-387-Q5
/// decision).
///
/// 🗣️F-387 (유저 2026-10-19): 「같은 fx인데 다른건 말이안됨. 다른것도
/// 확인해서 통일」. ↩️The row's opacity alone reached the tag, through a
/// `saveLayer` of its own; its effects reached nothing.
///
/// A tag the row composites plainly draws straight on: a raster of it would
/// be the same pixels.
void _composite(
  ui.Canvas canvas,
  ResolvedSeNameTag tag, {
  required CanvasSize canvasSize,
  required double rasterScale,
}) {
  final layouts = _layoutsOf(tag, canvasSize: canvasSize);
  final placement = placementMatrix(tag.placement);
  void paintTag(ui.Canvas into) {
    into.save();
    into.transform(placement.storage);
    for (final layout in layouts) {
      layout.paint(into);
    }
    into.restore();
  }

  final effects = resolveCompositeEffectPlan(
    tag.effects,
    paper: canvasSize.canvasRect,
  );
  if (tag.opacity >= 1 &&
      effects.isSingleDraw &&
      effects.finalPaint.isEmpty) {
    paintTag(canvas);
    return;
  }
  if (layouts.isEmpty) {
    return;
  }
  final drawn = layouts
      .map((layout) => layout.paintBounds)
      .reduce((union, rect) => union.expandToInclude(rect));
  drawSubtreeAsImage(
    canvas: canvas,
    bounds: effectBufferBounds(
      subtreeBufferBounds(
        CompositeLeaf(tag),
        within: canvas.getLocalClipBounds(),
        extentOf: (_) => drawn,
        placementOf: (tag) => tag.placement,
      ),
      effects.outsetPixels,
    ),
    rasterScale: rasterScale,
    paintSubtree: (into, _) => paintTag(into),
    compose: (blit) => blit(
      layerCompositePaint(
        opacity: tag.opacity,
        blendMode: LayerBlendMode.normal,
        effects: effects.finalPaint,
      ),
    ),
    steps: effects.preSteps,
    // The canvas the tag is laid on, as a row's chain is.
    paper: canvasSize.canvasRect,
    cell: rasterCellFor(effects.outsetPixels),
  );
}

/// [tag]'s text blocks, laid out where they stand in the tag's own space —
/// kept ([textCelLaidOut]): a pan, a zoom and a run paint the same tag at
/// every frame.
List<TextCelLayout> _layoutsOf(
  ResolvedSeNameTag tag, {
  required CanvasSize canvasSize,
}) {
  final layouts = <TextCelLayout>[];
  final anchor = seNameTagAnchorOf(tag, canvasSize: canvasSize);
  // The name is laid out once to measure, then MOVED so its ink (box
  // included) is centred on the anchor.
  var nameInk = ui.Rect.fromLTWH(anchor.dx, anchor.dy, 0, 0);
  if (tag.content.text.isNotEmpty) {
    final probe = textCelLaidOut(
      content: tag.content.copyWith(position: anchor),
      canvas: canvasSize,
      maxWidth: tag.widthBudget,
    );
    final drift = probe.inkBounds.center - anchor;
    final name = textCelLaidOut(
      content: tag.content.copyWith(position: anchor - drift),
      canvas: canvasSize,
      maxWidth: tag.widthBudget,
    );
    layouts.add(name);
    nameInk = name.inkBounds;
  }
  // With no name the box is a zero-width sliver AT the anchor, so the
  // line still hangs off "the box's right edge" — one rule, not two.

  // I-20: the delivery tag, centred over the box — measured the way the
  // line is, since neither knows where it goes until the box has a size.
  final delivery = tag.delivery;
  if (delivery != null && delivery.text.isNotEmpty) {
    layouts.add(
      textCelLaidOut(
        content: delivery.copyWith(
          position: _deliveryPosition(
            tag,
            delivery,
            box: nameInk,
            canvasSize: canvasSize,
          ),
        ),
        canvas: canvasSize,
        maxWidth: tag.widthBudget,
      ),
    );
  }

  final line = tag.line;
  if (line != null && line.text.isNotEmpty) {
    final probe = textCelLaidOut(
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
    layouts.add(
      textCelLaidOut(
        content: line.copyWith(position: anchor + shift),
        canvas: canvasSize,
        maxWidth: tag.widthBudget,
      ),
    );
  }
  return layouts;
}

/// Where [delivery] is laid out to sit over [box]: centred on it and a
/// line's gap above it.
///
/// 🗣️I-20 (유저 2026-09-30): 「위치는 캐릭터 이름 박스 위 중앙정렬」. The
/// painter and [seNameTagDeliveryBounds] both ask here, so the rule is
/// written once.
ui.Offset _deliveryPosition(
  ResolvedSeNameTag tag,
  TextCelContent delivery, {
  required ui.Rect box,
  required CanvasSize canvasSize,
}) {
  final anchor = seNameTagAnchorOf(tag, canvasSize: canvasSize);
  final probe = textCelLaidOut(
    content: delivery.copyWith(position: anchor),
    canvas: canvasSize,
    maxWidth: tag.widthBudget,
  );
  final ink = probe.inkBounds;
  final gap = delivery.style.fontSize * 0.3;
  return anchor +
      ui.Offset(box.center.dx - ink.center.dx, box.top - gap - ink.bottom);
}

/// Where the delivery tag lands for [tag], or null when it has none —
/// exposed for the same reason [seNameTagBoxBounds] is.
ui.Rect? seNameTagDeliveryBounds(
  ResolvedSeNameTag tag, {
  required CanvasSize canvasSize,
}) {
  final delivery = tag.delivery;
  if (delivery == null || delivery.text.isEmpty) {
    return null;
  }
  final landed = textCelLaidOut(
    content: delivery.copyWith(
      position: _deliveryPosition(
        tag,
        delivery,
        box: seNameTagBoxBounds(tag, canvasSize: canvasSize),
        canvasSize: canvasSize,
      ),
    ),
    canvas: canvasSize,
    maxWidth: tag.widthBudget,
  );
  final ink = landed.inkBounds;
  return ink;
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
/// re-deriving it, and so the canvas gizmo can frame the same box. It is
/// the tag's own rectangle: [ResolvedSeNameTag.placement] lays it.
ui.Rect seNameTagBoxBounds(
  ResolvedSeNameTag tag, {
  required CanvasSize canvasSize,
}) {
  final anchor = seNameTagAnchorOf(tag, canvasSize: canvasSize);
  if (tag.content.text.isEmpty) {
    return ui.Rect.fromLTWH(anchor.dx, anchor.dy, 0, 0);
  }
  final probe = textCelLaidOut(
    content: tag.content.copyWith(position: anchor),
    canvas: canvasSize,
    maxWidth: tag.widthBudget,
  );
  final ink = probe.inkBounds;
  return ui.Rect.fromCenter(
    center: anchor,
    width: ink.width,
    height: ink.height,
  );
}
