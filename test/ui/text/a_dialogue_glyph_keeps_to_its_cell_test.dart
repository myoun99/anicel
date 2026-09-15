import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';

/// F-93 — a dialogue glyph keeps to its cell.
///
/// 유저 2026-09-12: 「se블록의 대사 텍스트. 타임라인 줌을 낮추면 대사 글자끼리
/// 겹쳐져서 시인성이 안좋음. 이렇게 겹쳐질땐 글자 한글자의 좌우 길이? 를 줄여서
/// 한 칸에 한 글자라는 느낌이 나도록」.
///
/// Dialogue spreads its glyphs one to a cell over the block and painted each
/// at its own size, so once a zoomed-out block gave a glyph less room than
/// its width, it ran into its neighbours. [SeSpanVisual] is the block the
/// timeline's SE rows and the storyboard's both draw; down a column it
/// paints through `paintDialogueFitColumn`, the printed sheet's own call.
///
/// ⚠️The oracle is the box each glyph is PAINTED in, read off a canvas that
/// follows the transforms. The centres were right all along — a test on the
/// layout's numbers passes while the painter draws wide glyphs around them.
class _PaintedBoxes implements Canvas {
  final boxes = <Rect>[];
  final _saved = <Matrix4>[];
  var _transform = Matrix4.identity();

  @override
  void save() => _saved.add(_transform.clone());

  @override
  void restore() => _transform = _saved.removeLast();

  @override
  void translate(double dx, double dy) =>
      _transform = _transform.multiplied(Matrix4.translationValues(dx, dy, 0));

  @override
  void rotate(double radians) =>
      _transform = _transform.multiplied(Matrix4.rotationZ(radians));

  @override
  void scale(double sx, [double? sy]) => _transform = _transform.multiplied(
    Matrix4.diagonal3Values(sx, sy ?? sx, 1),
  );

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => boxes.add(
    MatrixUtils.transformRect(
      _transform,
      offset & Size(paragraph.maxIntrinsicWidth, paragraph.height),
    ),
  );

  @override
  int getSaveCount() => _saved.length + 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The boxes [SeSpanVisual]'s dialogue paints its glyphs in, over a block
/// of [size].
Future<List<Rect>> _paintedGlyphs(
  WidgetTester tester, {
  required Axis axis,
  required Size size,
  required String dialogue,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: SeSpanVisual(axis: axis, dialogue: dialogue),
          ),
        ),
      ),
    ),
  );
  final glyphs = find.descendant(
    of: find.byType(DialogueFitText),
    matching: find.byType(CustomPaint),
  );
  final canvas = _PaintedBoxes();
  tester
      .widget<CustomPaint>(glyphs)
      .painter!
      .paint(canvas, tester.getSize(glyphs));
  return canvas.boxes;
}

void main() {
  // Eight glyphs, each of them standing in a column.
  const dialogue = 'せりふのテキスト';

  testWidgets('along a row, a glyph wider than its cell narrows into it', (
    tester,
  ) async {
    final natural = await _paintedGlyphs(
      tester,
      axis: Axis.horizontal,
      size: const Size(400, 20),
      dialogue: dialogue,
    );
    // Eight to 24px: a 3px cell each.
    final boxes = await _paintedGlyphs(
      tester,
      axis: Axis.horizontal,
      size: const Size(24, 20),
      dialogue: dialogue,
    );

    expect(boxes, hasLength(8), reason: 'fixture: one paragraph per glyph');
    for (var i = 0; i < boxes.length; i += 1) {
      expect(
        natural[i].width,
        greaterThan(3),
        reason: 'fixture: glyph $i is wider than its cell',
      );
      expect(
        boxes[i].left,
        moreOrLessEquals(3.0 * i, epsilon: 1e-6),
        reason: 'glyph $i starts where its cell does',
      );
      expect(
        boxes[i].right,
        moreOrLessEquals(3.0 * (i + 1), epsilon: 1e-6),
        reason: 'glyph $i ends where its cell does',
      );
      expect(
        boxes[i].height,
        moreOrLessEquals(natural[i].height, epsilon: 1e-6),
        reason: 'across the row glyph $i keeps its size',
      );
    }
  });

  testWidgets('along a row, a glyph its cell holds keeps its own width', (
    tester,
  ) async {
    final natural = await _paintedGlyphs(
      tester,
      axis: Axis.horizontal,
      size: const Size(400, 20),
      dialogue: dialogue,
    );
    // Eight to 240px: a 30px cell each.
    final boxes = await _paintedGlyphs(
      tester,
      axis: Axis.horizontal,
      size: const Size(240, 20),
      dialogue: dialogue,
    );

    expect(boxes, hasLength(8), reason: 'fixture: one paragraph per glyph');
    for (var i = 0; i < boxes.length; i += 1) {
      expect(
        natural[i].width,
        lessThan(30),
        reason: 'fixture: glyph $i fits its cell',
      );
      expect(
        boxes[i].width,
        moreOrLessEquals(natural[i].width, epsilon: 1e-6),
        reason: 'a roomy cell does not stretch glyph $i',
      );
      expect(
        boxes[i].center.dx,
        moreOrLessEquals(30.0 * i + 15, epsilon: 1e-6),
        reason: 'glyph $i sits in the middle of its cell',
      );
    }
  });

  testWidgets('down a column, a glyph taller than its cell narrows into it', (
    tester,
  ) async {
    final natural = await _paintedGlyphs(
      tester,
      axis: Axis.vertical,
      size: const Size(20, 400),
      dialogue: dialogue,
    );
    // Eight to 24px: a 3px cell each.
    final boxes = await _paintedGlyphs(
      tester,
      axis: Axis.vertical,
      size: const Size(20, 24),
      dialogue: dialogue,
    );

    expect(boxes, hasLength(8), reason: 'fixture: one paragraph per glyph');
    for (var i = 0; i < boxes.length; i += 1) {
      expect(
        natural[i].height,
        greaterThan(3),
        reason: 'fixture: glyph $i is taller than its cell',
      );
      expect(
        boxes[i].top,
        moreOrLessEquals(3.0 * i, epsilon: 1e-6),
        reason: 'glyph $i starts where its cell does',
      );
      expect(
        boxes[i].bottom,
        moreOrLessEquals(3.0 * (i + 1), epsilon: 1e-6),
        reason: 'glyph $i ends where its cell does',
      );
      expect(
        boxes[i].width,
        moreOrLessEquals(natural[i].width, epsilon: 1e-6),
        reason: 'across the column glyph $i keeps its size',
      );
    }
  });

  testWidgets('down a column, a turned glyph narrows into its cell too', (
    tester,
  ) async {
    // The long-vowel bar lies down the column; the kana either side stand.
    const withBar = 'ガーン';
    final natural = await _paintedGlyphs(
      tester,
      axis: Axis.vertical,
      size: const Size(20, 300),
      dialogue: withBar,
    );
    // Three to 9px: a 3px cell each.
    final boxes = await _paintedGlyphs(
      tester,
      axis: Axis.vertical,
      size: const Size(20, 9),
      dialogue: withBar,
    );

    expect(boxes, hasLength(3), reason: 'fixture: one paragraph per glyph');
    expect(
      natural[1].height,
      greaterThan(3),
      reason: 'fixture: the bar is longer than its cell',
    );
    expect(
      boxes[1].top,
      moreOrLessEquals(3, epsilon: 1e-6),
      reason: 'the bar starts where its cell does',
    );
    expect(
      boxes[1].bottom,
      moreOrLessEquals(6, epsilon: 1e-6),
      reason: 'the bar ends where its cell does',
    );
    expect(
      boxes[1].width,
      moreOrLessEquals(natural[1].width, epsilon: 1e-6),
      reason: 'across the column the bar keeps its size',
    );
  });
}
