import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/canvas_size.dart';
import '../../models/text_cel_style.dart' show TextCelContent, TextCelStyle;
import '../../services/se_name_tag_plan.dart';
import '../canvas/display_resample.dart'
    show wholeLevelPixelsOutward;
import 'canvas_letter_shapes.dart' show CanvasLetterShapes;
import 'text_cel_render.dart';

/// [tag] as the GPU engine is handed it to raster its plate itself
/// (`EngineLetters.seNameTagPlate`): the layers of its blocks
/// ([_laidOf]), bottom to top, where they stand in the tag's own space
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
  final (:box, :name, :rule, :delivery, :line) = _laidOf(
    tag,
    canvasSize: canvasSize,
  );
  final layers = [
    if (name != null) ...[
      if (tag.content.style.backgroundColor case final background?)
        name.rectLayer(box, background),
      ...name.letterLayers,
      if (rule != null) name.rectLayer(rule, _ruleColor),
      ...?delivery?.letterLayers,
    ],
    ...?line?.shapes,
  ];
  return layers.isEmpty ? null : layers;
}

/// The rect of its own space [tag] may paint, on whole pixels — what its
/// plate is drawn over, and what a row of it stands for (as a cel number's
/// letters do, `celNumberExtent`). Empty for a tag with no blocks.
ui.Rect seNameTagExtent(
  ResolvedSeNameTag tag, {
  required CanvasSize canvasSize,
}) {
  final laid = _laidOf(tag, canvasSize: canvasSize);
  final blocks = [laid.name, laid.delivery, laid.line].nonNulls;
  return blocks.isEmpty
      ? ui.Rect.zero
      : wholeLevelPixelsOutward(
          blocks
              .map((block) => block.paintBounds)
              .fold(laid.box, (union, rect) => union.expandToInclude(rect)),
          0,
        );
}

/// A tag as it is laid in its own space ([_laidOf]): its one [box] — a
/// sliver at the anchor with no name in it —, the [name] in it, the
/// [delivery] under a [rule] in the same box, and the dialogue [line] off
/// the box's right edge.
typedef SeNameTagLaid = ({
  ui.Rect box,
  TextCelLayout? name,
  ui.Rect? rule,
  TextCelLayout? delivery,
  TextCelLayout? line,
});

/// How large the delivery's letters are set, as a share of the name's as
/// they are drawn.
///
/// 🗣️I-173 (유저 2026-11-13): 「타입 텍스트는 최대한 작게」; I-173-Q1 (유저
/// 2026-11-14, of 30 · 40 · 50% drawn for the choice): 「글자크기는 권장」
/// — two fifths.
const double _deliveryShare = 0.4;

/// How thick the rule between the name and the delivery is, as a share of
/// the name's letters.
const double _ruleShare = 0.06;

/// The rule's colour.
///
/// 🗣️I-173 (유저 2026-11-14): 「박스하나로 하고 가로선두란건 진짜 박스 하나로
/// 하고 사이에 가로선 검정색 두란거였어. 공간두란게아니라」. ↩️The name's
/// letters' colour — white in a tag's own style, which read as a gap that
/// split the box in two.
const int _ruleColor = 0xFF000000;

/// [tag] as it is laid ([_laidOf]) — what a test states the rules by, in
/// place of re-deriving them.
@visibleForTesting
SeNameTagLaid seNameTagLaid(
  ResolvedSeNameTag tag, {
  required CanvasSize canvasSize,
}) => _laidOf(tag, canvasSize: canvasSize);

/// [tag]'s text blocks, laid out where they stand in the tag's own space —
/// kept ([textCelLaidOut]): a pan, a zoom and a run paint the same tag at
/// every frame.
///
/// GEOMETRY (R5 #7, the user's rule, corrected twice on the mockup):
/// the tag's stored position is the BOX's exact geometric centre, and
/// the dialogue hangs off the box's right edge, vertically centred on it.
/// So turning the dialogue off leaves the box exactly where it was —
/// anchoring on the pair's combined centre would have slid it.
///
/// 🗣️I-173 (유저 2026-11-13): 「지금 이름이랑 ON OFF같은 타입이랑 별도
/// 박스로 나오도록 설계햇는데, 바꾸고싶음. 같은 박스안에 존재하도록.
/// 구체적으론 이름텍스트는 지금이랑 같은느낌이고, ON OFF같은 텍스트가
/// 존재할땐 박스가 커져서, 이름밑에 가로선두고 그 밑에 중앙정렬로 ON OFF같은
/// 타입 텍스트 둠. 타입 텍스트는 최대한 작게.」 — the name's box, grown down
/// by a rule and the storey the delivery stands in, and widened about its
/// middle where the delivery is the wider. ↩️I-20 (유저 2026-09-30:
/// 「위치는 캐릭터 이름 박스 위 중앙정렬」) set the delivery in a box of its
/// own, the name's size, a line's gap over the name's.
///
/// 🗣️I-173-Q2 (유저 2026-11-14): 「기준점은 박스 전체의 가운데」 — the box
/// the anchor centres is the WHOLE of it, so a name with a delivery under
/// it stands half that storey over the anchor. ↩️The name's box alone,
/// while the delivery stood outside it.
///
/// The placement lives here rather than in the plan because it needs the
/// laid-out box, and nothing knows how wide a box is until it is measured.
SeNameTagLaid _laidOf(
  ResolvedSeNameTag tag, {
  required CanvasSize canvasSize,
}) {
  final anchor = seNameTagAnchorOf(tag, canvasSize: canvasSize);
  TextCelLayout at(TextCelContent block, ui.Offset position) => textCelLaidOut(
    content: block.copyWith(position: position),
    canvas: canvasSize,
    maxWidth: tag.widthBudget,
  );
  // With no name the box is a zero-width sliver AT the anchor, so the
  // line still hangs off "the box's right edge" — one rule, not two.
  var box = ui.Rect.fromLTWH(anchor.dx, anchor.dy, 0, 0);
  TextCelLayout? name;
  ui.Rect? rule;
  TextCelLayout? delivery;
  if (tag.content.text.isNotEmpty) {
    // A block is laid out once to measure, then MOVED by what it
    // measured: where its ink lands is known only once it is set.
    final measured = at(tag.content, anchor);
    // The delivery is said under a name (`ResolvedSeNameTag.delivery`).
    final typed = switch (tag.delivery) {
      final said? when said.text.isNotEmpty => said.copyWith(
        style: _deliveryLetters(
          said.style,
          size: measured.letterSize * _deliveryShare,
        ),
      ),
      _ => null,
    };
    final lettered = typed == null ? null : at(typed, anchor);
    final ruled = lettered == null ? 0.0 : measured.letterSize * _ruleShare;
    final storey = ruled + (lettered?.textSize.height ?? 0);
    name = at(
      tag.content,
      anchor + (anchor - ui.Offset(0, storey / 2) - measured.box.center),
    );
    final named = name.box;
    final half =
        math.max(
          named.width,
          (lettered?.textSize.width ?? 0) + name.pad * 2,
        ) /
        2;
    box = ui.Rect.fromLTRB(
      named.center.dx - half,
      named.top,
      named.center.dx + half,
      named.bottom + storey,
    );
    if (lettered != null) {
      rule = ui.Rect.fromLTRB(
        box.left,
        named.bottom,
        box.right,
        named.bottom + ruled,
      );
      delivery = at(
        typed!,
        anchor +
            (ui.Offset(
                  named.center.dx - lettered.textSize.width / 2,
                  rule.bottom,
                ) -
                lettered.topLeft),
      );
    }
  }

  TextCelLayout? line;
  if (tag.line case final said? when said.text.isNotEmpty) {
    final probe = at(said, anchor);
    final gap = said.style.fontSize * 0.3;
    // Left edge on the box's right edge; vertically centred on the anchor
    // — the box's centre — so a taller line reads as sitting beside the
    // box, not under it.
    line = at(
      said,
      anchor +
          ui.Offset(
            box.right + gap - probe.inkBounds.left,
            anchor.dy - probe.inkBounds.center.dy,
          ),
    );
  }
  return (box: box, name: name, rule: rule, delivery: delivery, line: line);
}

/// The letters a delivery is set in: [style]'s — the name's
/// (`ResolvedSeNameTag.delivery`) — at [size], what it measures by scaled
/// with it.
TextCelStyle _deliveryLetters(TextCelStyle style, {required double size}) {
  final scale = size / style.fontSize;
  return style.copyWith(
    fontSize: size,
    letterSpacing: style.letterSpacing * scale,
    outlineWidth: style.outlineWidth * scale,
  );
}

/// The tag's anchor — the box's centre. Null position means "centre on
/// the canvas", the grammar [TextCelContent] already speaks.
ui.Offset seNameTagAnchorOf(
  ResolvedSeNameTag tag, {
  required CanvasSize canvasSize,
}) =>
    tag.content.position ??
    ui.Offset(canvasSize.width / 2, canvasSize.height / 2);

/// Where the tag's BOX lands for [tag] — the name's, grown by its
/// delivery's storey: the rectangle the anchor centres —, exposed so a
/// test can state the rule the painter follows instead of re-deriving it,
/// and so the canvas gizmo can frame the same box. It is the tag's own
/// rectangle: [ResolvedSeNameTag.placement] lays it.
ui.Rect seNameTagBoxBounds(
  ResolvedSeNameTag tag, {
  required CanvasSize canvasSize,
}) => _laidOf(tag, canvasSize: canvasSize).box;
