import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart'
    show LayerPlacement;
import 'package:anicel/src/services/se_name_tag_plan.dart';
import 'package:anicel/src/ui/text/se_name_tag_paint.dart';

/// 🔬card paint-walk-redoes-the-same-work-each-step (2026-10-27): every
/// paint of the SE name tags — each frame of a pan, a zoom or a run — laid
/// each of a tag's blocks out twice, once to measure and once where it
/// goes, and let them go, though the tag had not changed
/// (`textCelLaidOut`).
///
/// The oracle is the paragraph a paint DRAWS: blocks laid out once are the
/// same paragraph at every paint, and still alive to be drawn.
class _Paragraphs implements ui.Canvas {
  final drawn = <ui.Paragraph>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, ui.Offset offset) =>
      drawn.add(paragraph);

  @override
  int getSaveCount() => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _canvas = CanvasSize(width: 1920, height: 1080);

ResolvedSeNameTag _tag(String name) => ResolvedSeNameTag(
  layerId: 's1',
  widthBudget: 1920,
  shot: const LayerPlacement.identity(),
  content: TextCelContent(
    text: name,
    style: SeNameTag.defaultStyle,
    position: const ui.Offset(960, 900),
  ),
  line: const TextCelContent(
    text: 'おはよう',
    style: SeNameTag.defaultLineStyle,
  ),
  delivery: const TextCelContent(text: 'OFF', style: SeNameTag.defaultStyle),
);

List<ui.Paragraph> _painted(ResolvedSeNameTag tag) {
  final canvas = _Paragraphs();
  paintSeNameTags(canvas, tags: [tag], canvasSize: _canvas, rasterScale: 1);
  return canvas.drawn;
}

void main() {
  testWidgets('a tag painted again draws the blocks it laid out, still '
      'held', (tester) async {
    final first = _painted(_tag('タモツ'));
    expect(first, isNotEmpty, reason: 'LIVENESS: the tag painted');

    final again = _painted(_tag('タモツ'));
    expect(again, hasLength(first.length));
    for (var i = 0; i < first.length; i += 1) {
      expect(
        identical(again[i], first[i]),
        isTrue,
        reason: '🚨a second paint laid paragraph $i out again',
      );
      expect(
        again[i].debugDisposed,
        isFalse,
        reason: '🚨a kept block was let go of by the paint that drew it',
      );
    }
  });

  test('nothing in the app lays a text block out but the one that keeps '
      'it', () {
    const keeper = 'lib/src/ui/text/text_cel_render.dart';
    expect(
      File(keeper).readAsStringSync(),
      contains('layoutTextCel('),
      reason: 'premise: the scan sees the keeper lay one out',
    );
    final own = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.path.replaceAll(r'\', '/') != keeper &&
            file.readAsStringSync().contains('layoutTextCel('))
          file.path,
    ];
    expect(
      own,
      isEmpty,
      reason: '🚨laid out afresh at every paint, and let go of',
    );
  });

  testWidgets('another name is another layout', (tester) async {
    final here = _painted(_tag('ヒロシ'));
    final there = _painted(_tag('ヒロミ'));
    expect(there, isNotEmpty, reason: 'LIVENESS: the tag painted');
    expect(
      identical(there.first, here.first),
      isFalse,
      reason: '🚨another name answered with these letters',
    );
  });
}
