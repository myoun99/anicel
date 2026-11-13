import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/se_line_type.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart' show LayerPlacement;
import 'package:anicel/src/services/playback/cut_frame_composite_signature.dart'
    show SeNameTagRowSignature;
import 'package:anicel/src/services/se_name_tag_plan.dart';
import 'package:anicel/src/ui/text/canvas_letter_shapes.dart';
import 'package:anicel/src/ui/text/se_name_tag_paint.dart';

/// 🗣️I-173 (유저 2026-11-13): 「지금 이름이랑 ON OFF같은 타입이랑 별도
/// 박스로 나오도록 설계햇는데, 바꾸고싶음. 같은 박스안에 존재하도록.
/// 구체적으론 이름텍스트는 지금이랑 같은느낌이고, ON OFF같은 텍스트가
/// 존재할땐 박스가 커져서, 이름밑에 가로선두고 그 밑에 중앙정렬로 ON OFF같은
/// 타입 텍스트 둠. 타입 텍스트는 최대한 작게.」 — and of what was drawn for
/// it (유저 2026-11-14): 「글자크기는 권장. 기준점은 박스 전체의 가운데.
/// 이름없는 대사는 타입도 안보이게. 그리고 박스하나로 하고 가로선두란건 진짜
/// 박스 하나로 하고 사이에 가로선 검정색 두란거였어. 공간두란게아니라.」
///
/// 🗣️I-20 (유저 2026-09-30): 「해당 타입의 텍스트는 네임태그로서 화면에
/// 보이게함」 — and every type shows on the canvas, ON included (「ON일때는
/// … 캔버스에는 표시」). ↩️「위치는 캐릭터 이름 박스 위 중앙정렬」: it sat
/// over the name, in a box of its own.
void main() {
  // The tag's blocks are kept for the fonts there are, which the binding
  // tells (`textCelLaidOut`).
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvas = CanvasSize(width: 2340, height: 1654);
  const camera = CanvasSize(width: 1920, height: 1080);

  ResolvedSeNameTag tagFor(SeLineType type, {String? seName = 'タモツ'}) {
    const frameId = FrameId('s-cel');
    final row = Layer(
      id: const LayerId('s'),
      name: 'SE',
      kind: LayerKind.se,
      frames: [
        Frame(
          id: frameId,
          duration: 12,
          strokes: const [],
          name: 'おはよう',
          seName: seName,
          seTypes: SeLineTypes(own: type),
        ),
      ],
      timeline: {0: const TimelineExposure.drawing(frameId, length: 12)},
    );
    return resolveSeNameTagsAt(
      trackSeLayers: [row],
      shown: (globalFrame: 3, cutId: const CutId('cut')),
      cameraFrame: camera,
      shot: const LayerPlacement.identity(),
    ).single;
  }

  /// [tag] with no delivery — the name's box as it stands alone.
  ResolvedSeNameTag undelivered(ResolvedSeNameTag tag) => ResolvedSeNameTag(
    layerId: tag.layerId,
    content: tag.content,
    widthBudget: tag.widthBudget,
    shot: tag.shot,
    line: tag.line,
  );

  SeNameTagLaid laid(ResolvedSeNameTag tag) =>
      seNameTagLaid(tag, canvasSize: canvas);

  ui.Offset anchorOf(ResolvedSeNameTag tag) =>
      seNameTagAnchorOf(tag, canvasSize: canvas);

  /// Where a tag's delivery's letters are set.
  ui.Rect lettersOf(SeNameTagLaid laid) =>
      laid.delivery!.topLeft & laid.delivery!.textSize;

  /// The one rect [layer] covers, where it covers just one.
  ui.Rect? only(CanvasLetterShapes layer) => switch (layer.shapes) {
    [CanvasLetterRect(:final rect)] => rect,
    _ => null,
  };

  test('every delivery shows on the canvas, in the name\'s own style', () {
    for (final type in SeLineType.values) {
      final tag = tagFor(type);
      expect(tag.delivery?.text, type.label, reason: type.name);
      expect(tag.delivery?.style, tag.content.style, reason: '「네임태그로서」');
    }
  });

  test('it stands IN the name\'s box — under the name, under a rule from '
      'edge to edge, centred', () {
    for (final type in SeLineType.values) {
      final tag = laid(tagFor(type));
      final box = tag.box;
      final name = tag.name!.box;
      final rule = tag.rule!;
      final letters = lettersOf(tag);

      expect(rule.top, name.bottom, reason: '「이름밑에 가로선」');
      expect((rule.left, rule.right), (box.left, box.right));
      expect(rule.height, greaterThan(0));
      expect(letters.top, closeTo(rule.bottom, 0.001), reason: '「그 밑에」');
      expect(
        letters.center.dx,
        closeTo(box.center.dx, 0.001),
        reason: '「중앙정렬」',
      );
      expect(box.bottom, closeTo(letters.bottom, 0.001));
      expect(box.top, name.top);
      expect(
        seNameTagBoxBounds(tagFor(type), canvasSize: canvas),
        box,
        reason: 'the box the canvas frames is the whole of it',
      );
    }
  });

  test('the name is the size it was — the box grows by the rule and the '
      'delivery\'s storey alone', () {
    final tag = tagFor(SeLineType.off);
    final alone = laid(undelivered(tag));
    final both = laid(tag);

    expect(both.name!.box.size, alone.name!.box.size, reason: '「같은느낌」');
    expect(alone.rule, isNull);
    expect(alone.box, rectMoreOrLessEquals(alone.name!.box, epsilon: 0.001));
    expect((both.box.left, both.box.right), (alone.box.left, alone.box.right));
    expect(
      both.box.height,
      closeTo(
        alone.box.height + both.rule!.height + lettersOf(both).height,
        0.001,
      ),
    );
  });

  test('the anchor is the middle of the WHOLE box — so a name with a '
      'delivery under it stands half that storey over the anchor', () {
    final tag = tagFor(SeLineType.off);
    final anchor = anchorOf(tag);
    final alone = laid(undelivered(tag));
    final both = laid(tag);

    for (final box in [alone.box, both.box]) {
      expect(box.center.dx, closeTo(anchor.dx, 0.001));
      expect(box.center.dy, closeTo(anchor.dy, 0.001), reason: '「박스 전체」');
    }
    final storey = both.rule!.height + lettersOf(both).height;
    expect(storey, greaterThan(10), reason: 'a storey to tell the two by');
    expect(
      both.name!.box.center.dy,
      closeTo(anchor.dy - storey / 2, 0.001),
    );
  });

  test('its letters are two fifths of the name\'s — of the name as it is '
      'DRAWN, so a tag shrunk to its budget keeps its proportions', () {
    final tag = tagFor(SeLineType.mono);
    final whole = laid(tag);
    expect(whole.name!.letterSize, tag.content.style.fontSize);
    expect(
      whole.delivery!.letterSize,
      closeTo(tag.content.style.fontSize * 0.4, 0.001),
      reason: '「타입 텍스트는 최대한 작게」 · 「글자크기는 권장」',
    );

    final shrunk = laid(
      ResolvedSeNameTag(
        layerId: tag.layerId,
        content: tag.content,
        delivery: tag.delivery,
        widthBudget: 40,
        shot: tag.shot,
      ),
    );
    expect(shrunk.name!.letterSize, lessThan(tag.content.style.fontSize));
    expect(
      shrunk.delivery!.letterSize,
      closeTo(shrunk.name!.letterSize * 0.4, 0.001),
    );
  });

  test('a delivery wider than its name widens the box about its middle', () {
    final tag = laid(tagFor(SeLineType.mono, seName: 'ユ'));
    final name = tag.name!.box;

    expect(lettersOf(tag).width, greaterThan(name.width - tag.name!.pad * 2));
    expect(tag.box.width, greaterThan(name.width));
    expect(tag.box.center.dx, closeTo(name.center.dx, 0.001));
    expect(
      tag.box.width,
      closeTo(lettersOf(tag).width + tag.name!.pad * 2, 0.001),
      reason: 'the delivery takes the name\'s breathing room',
    );
    expect((tag.rule!.left, tag.rule!.right), (tag.box.left, tag.box.right));
    expect(
      tag.line!.inkBounds.left,
      closeTo(tag.box.right + tag.line!.style.fontSize * 0.3, 1),
      reason: 'the line hangs off the BOX, not off the name in it',
    );
  });

  test('the box is ONE box: the engine is handed one rect behind the name '
      'and the delivery both, and a black rule over it', () {
    final tag = tagFor(SeLineType.off);
    final placed = laid(tag);
    final layers = seNameTagShapes(tag, canvasSize: canvas)!;

    expect(
      [
        for (final layer in layers)
          if (layer.argb == tag.content.style.backgroundColor) only(layer),
      ],
      [placed.box],
      reason: 'no box of the delivery\'s own',
    );
    expect(only(layers.first), placed.box, reason: 'under every letter');
    expect(
      [
        for (final layer in layers)
          if (only(layer) case final rect? when rect != placed.box)
            (layer.argb, rect),
      ],
      [(0xFF000000, placed.rule)],
      reason: '「사이에 가로선 검정색」 — a line, not a gap',
    );
  });

  test('the line hangs off the box\'s right edge, at the box\'s middle', () {
    final tag = laid(tagFor(SeLineType.off));
    final line = tag.line!.inkBounds;

    expect(line.left, greaterThan(tag.box.right));
    expect(line.center.dy, closeTo(tag.box.center.dy, 1));
  });

  test('a line with no name shows no delivery: its dialogue alone, off the '
      'anchor', () {
    final tag = tagFor(SeLineType.off, seName: null);
    expect(tag.delivery, isNull, reason: '「이름없는 대사는 타입도 안보이게」');

    final anchor = anchorOf(tag);
    // And a painter handed one all the same sets none: it is said under a
    // name.
    for (final unnamed in [
      tag,
      ResolvedSeNameTag(
        layerId: tag.layerId,
        content: tag.content,
        delivery: tagFor(SeLineType.off).delivery,
        line: tag.line,
        widthBudget: tag.widthBudget,
        shot: tag.shot,
      ),
    ]) {
      final placed = laid(unnamed);
      expect(placed.name, isNull);
      expect(placed.delivery, isNull);
      expect(placed.rule, isNull);
      expect(placed.box, ui.Rect.fromLTWH(anchor.dx, anchor.dy, 0, 0));
      expect(placed.line!.inkBounds.left, greaterThan(anchor.dx));
      expect(
        seNameTagShapes(unnamed, canvasSize: canvas)!.map(only).nonNulls,
        isEmpty,
        reason: 'no box and no rule — the letters of the line alone',
      );
    }
  });

  test('a new delivery is a new picture — the frame\'s key sees it', () {
    expect(
      SeNameTagRowSignature(tagFor(SeLineType.on)),
      isNot(SeNameTagRowSignature(tagFor(SeLineType.off))),
    );
  });
}
