import 'dart:ui' as ui;

import '../../models/canvas_size.dart';
import '../../models/text_cel_style.dart' show TextCelContent;
import '../../services/se_name_tag_plan.dart';
import '../canvas/display_resample.dart'
    show wholeLevelPixelsOutward;
import 'canvas_letter_shapes.dart' show CanvasLetterShapes;
import 'text_cel_render.dart';

/// [tag] as the GPU engine is handed it to raster its plate itself
/// (`EngineLetters.seNameTagPlate`): the layers of its blocks
/// ([_layoutsOf]), bottom to top, where they stand in the tag's own space
/// — null for a tag with none.
///
/// 🚨★★★CANVAS PIXELS, LAID AS A ROW'S PICTURE IS (card
/// cel-number-letters-drawn-as-vectors, 유저 2026-11-07 「지금까지가 셀번호가
/// 벡터엿던게 버그야. 통일하지 않았던거니까」): the letters a picture holds are
/// a plate, as a cel number's are. ↩️The blocks were drawn as vectors under
/// the placement, at the screen's or the file's resolution; then as a
/// plate of Flutter's own, over the frame each route had composited.
List<CanvasLetterShapes>? seNameTagShapes(
  ResolvedSeNameTag tag, {
  required CanvasSize canvasSize,
}) {
  final layouts = _layoutsOf(tag, canvasSize: canvasSize);
  return layouts.isEmpty
      ? null
      : [for (final layout in layouts) ...layout.shapes];
}

/// The rect of its own space [tag] may paint, on whole pixels — what its
/// plate is drawn over, and what a row of it stands for (as a cel number's
/// letters do, `celNumberExtent`). Empty for a tag with no blocks.
ui.Rect seNameTagExtent(
  ResolvedSeNameTag tag, {
  required CanvasSize canvasSize,
}) => switch (_layoutsOf(tag, canvasSize: canvasSize)) {
  [] => ui.Rect.zero,
  final layouts => _drawnBy(layouts),
};

/// What [layouts] may paint, on whole pixels.
ui.Rect _drawnBy(List<TextCelLayout> layouts) => wholeLevelPixelsOutward(
  layouts
      .map((layout) => layout.paintBounds)
      .reduce((union, rect) => union.expandToInclude(rect)),
  0,
);

/// [tag]'s text blocks, laid out where they stand in the tag's own space —
/// kept ([textCelLaidOut]): a pan, a zoom and a run paint the same tag at
/// every frame.
///
/// GEOMETRY (R5 #7, the user's rule, corrected twice on the mockup):
/// the tag's stored position is the name BOX's exact geometric centre, and
/// the dialogue hangs off the box's right edge, vertically centred on it.
/// So turning the dialogue off leaves the box exactly where it was —
/// anchoring on the pair's combined centre would have slid it.
///
/// The placement lives here rather than in the plan because it needs the
/// laid-out box, and nothing knows how wide a box is until it is measured.
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
