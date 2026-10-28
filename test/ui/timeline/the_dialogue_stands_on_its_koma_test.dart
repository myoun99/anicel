import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/se_dialogue_spacing.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';

import '../../helpers/an_se_row.dart';
import '../../helpers/painted_glyph_boxes.dart';

/// 🗣️F-496 ③ (유저 2026-10-28): 「지금까지는 중앙정렬 기준으로 텍스트
/// 배치했는데, 왼쪽정렬로 둬서 1코마부터 첫번째 글자가 시작되도록. 대사
/// 오프셋은 이 시작되는 위치를 변경함. 1코마기준으로 움직임. 글자별 코마는
/// … 3코마로 설정하면 글자 하나당 3코마의 공간을 차지하는느낌 … 프레임블록의
/// 글자 그대로 법 통일해서 적용. 참고로 띄어쓰기도 동일하게 코마 적용됨」.
///
/// Measured as the boxes the span's dialogue PAINTS, along the block, both
/// ways the timeline turns.
void main() {
  const frame = 24.0;
  const frames = 12;
  const cross = 52.0;

  for (final axis in Axis.values) {
    Future<List<Rect>> paintedAlong(
      WidgetTester tester, {
      required String dialogue,
      required SeDialogueSpacing spacing,
      int frames = frames,
      double frameExtent = frame,
    }) async {
      final along = frames * frameExtent;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: sizedAlong(
              axis,
              along: along,
              across: cross,
              child: SeSpanVisual(
                layer: anSeRow(),
                axis: axis,
                frames: frames,
                dialogue: dialogue,
                spacing: spacing,
              ),
            ),
          ),
        ),
      );
      final glyphs = find.descendant(
        of: find.byType(DialogueFitText),
        matching: find.byType(CustomPaint),
      );
      final canvas = PaintedGlyphBoxes();
      tester
          .widget<CustomPaint>(glyphs)
          .painter!
          .paint(canvas, tester.getSize(glyphs));
      return canvas.boxes;
    }

    /// Where along the block [box] is centred, in frames.
    double centreFrame(Rect box) => partAlong(axis, box.center) / frame;

    testWidgets('the first glyph stands on the first frame, and each takes '
        'its koma — not spread over the block (${axis.name})', (tester) async {
      final boxes = await paintedAlong(
        tester,
        dialogue: 'あいう',
        spacing: SeDialogueSpacing.standard,
      );
      expect(boxes, hasLength(3), reason: '⛔전제: every glyph painted');
      expect(
        [for (final box in boxes) centreFrame(box)],
        [for (final at in [0, 3, 6]) closeTo(at + 0.5, 1e-6)],
        reason: 'three a glyph, each centred on the first of its frames — '
            '↩️the line used to be spread evenly over all twelve',
      );
      for (final box in boxes) {
        expect(
          extentAlong(axis, box.size),
          lessThan(frame),
          reason: '⛔전제: a glyph that fits its frame keeps its size',
        );
      }
    });

    testWidgets('the offset moves the line by frames; the koma set how far '
        'apart its glyphs stand — a space\'s too (${axis.name})', (
      tester,
    ) async {
      final boxes = await paintedAlong(
        tester,
        dialogue: 'あ い',
        spacing: const SeDialogueSpacing(offset: 2, komaPerGlyph: 4),
        // Its three glyphs end on the block's last frame.
        frames: 14,
      );
      expect(boxes, hasLength(3));
      expect(
        [for (final box in boxes) centreFrame(box)],
        [for (final at in [2, 6, 10]) closeTo(at + 0.5, 1e-6)],
      );
    });

    // 「프레임블록의 글자 그대로 법 통일」: past its frame a block word grows
    // on toward the block's end from that frame (`timelineBlockWordStart`).
    testWidgets('a glyph longer than its frame stands from it, on into its '
        'koma — not centred over it, hanging into the frame before '
        '(${axis.name})', (tester) async {
      const narrow = 6.0;
      final boxes = await paintedAlong(
        tester,
        dialogue: 'あいう',
        spacing: SeDialogueSpacing.standard,
        frameExtent: narrow,
      );
      expect(boxes, hasLength(3));
      for (final (index, box) in boxes.indexed) {
        final cellStart = index * 3 * narrow;
        expect(
          extentAlong(axis, box.size),
          greaterThan(narrow),
          reason: '⛔전제: glyph $index is longer than its frame',
        );
        expect(
          partAlong(axis, box.center),
          greaterThan(cellStart + narrow / 2 + 1),
          reason: 'glyph $index grows on from its frame',
        );
        expect(
          endAlong(axis, box),
          lessThanOrEqualTo(cellStart + 3 * narrow + 1e-6),
          reason: 'glyph $index inside its koma',
        );
      }
    });

    testWidgets('a line its koma run past the block shares the frames after '
        'its offset, each glyph narrowed to its share (${axis.name})', (
      tester,
    ) async {
      final boxes = await paintedAlong(
        tester,
        dialogue: 'あいうえおかきくけこさしすせそ',
        spacing: const SeDialogueSpacing(offset: 2),
        frames: 4,
      );
      expect(boxes, hasLength(15));
      const share = (4 - 2) / 15;
      expect(centreFrame(boxes.first), greaterThanOrEqualTo(2));
      for (final (index, box) in boxes.indexed) {
        final start = 2 + index * share;
        expect(
          startAlong(axis, box),
          greaterThanOrEqualTo(start * frame - 1e-6),
          reason: 'glyph $index inside its share',
        );
        expect(
          endAlong(axis, box),
          lessThanOrEqualTo((start + share) * frame + 1e-6),
          reason: 'glyph $index inside its share',
        );
      }
    });
  }
}
