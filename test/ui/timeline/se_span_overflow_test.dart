import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/se_dialogue_spacing.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';

import '../../helpers/an_se_row.dart';
import '../../helpers/painted_glyph_boxes.dart';

/// R4 improvement 2 — the SE span visual must never throw the striped
/// RenderFlex overflow: long names scale down into the name box, and a span
/// narrower than the box keeps it and narrows it instead (F-93).
void main() {
  Widget host({
    required double width,
    required double height,
    String? name,
    Axis axis = Axis.horizontal,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: height,
            child: SeSpanVisual(
              layer: anSeRow(),
              axis: axis,
              frames: 1,
              dialogue: 'せりふのテキスト',
              seName: name,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a LONG name never overflows the row (scales down instead)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(width: 200, height: 52, name: 'とてもながいおとのなまえドンドンドン'),
    );
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel(RegExp('SE name')), findsOneWidget);
  });

  testWidgets('a span narrower than the box KEEPS it and narrows it '
      '(storyboard zoom-out)', (tester) async {
    await tester.pumpWidget(host(width: 10, height: 52, name: 'SE'));
    expect(tester.takeException(), isNull);
    final box = find.bySemanticsLabel(RegExp('SE name'));
    expect(
      box,
      findsOneWidget,
      reason: '유저 2026-09-16: 「이름 상자를 버리는게아니야. 유지한채로 '
          '가로 길이만 작게하란거야」',
    );
    expect(tester.getSize(box).width, greaterThan(0));
  });

  // 🗣️F-224 (유저 2026-09-29): 「대사는 줄어들어가는데 이름칸은 줄어들기
  // 시작하는게 늦어서 … 대사랑 이름칸이랑 동일하게 줄어들기시작하도록」.
  for (final axis in Axis.values) {
    testWidgets('🚨F-224: the chip and the dialogue start narrowing together, '
        'by one ratio (${axis.name})', (tester) async {
      const cross = 52.0;
      Widget along(double extent) => axis == Axis.horizontal
          ? host(width: extent, height: cross, name: 'SE')
          : host(width: cross, height: extent, name: 'SE', axis: axis);
      double extentOf(Finder finder) =>
          extentAlong(axis, tester.getSize(finder));

      /// How long each glyph of the dialogue is PAINTED along the block.
      List<double> glyphLengths() {
        final glyphs = find.descendant(
          of: find.byType(DialogueFitText),
          matching: find.byType(CustomPaint),
        );
        final canvas = PaintedGlyphBoxes();
        tester
            .widget<CustomPaint>(glyphs)
            .painter!
            .paint(canvas, tester.getSize(glyphs));
        return [for (final box in canvas.boxes) extentAlong(axis, box.size)];
      }

      // One frame, eight glyphs: each has an eighth of the block (F-496 ③)
      // — far more than it needs at this length.
      await tester.pumpWidget(along(4000));
      final natural = glyphLengths();
      expect(natural, hasLength(8), reason: '⛔전제: every glyph painted');
      final longest = natural.reduce(math.max);

      for (final extent in [8 * longest, 6 * longest, 3 * longest, 20.0]) {
        await tester.pumpWidget(along(extent));
        final lengths = glyphLengths();
        final narrowed = [
          for (var i = 0; i < lengths.length; i += 1) lengths[i] / natural[i],
        ].reduce(math.min);
        final chip = extentOf(find.bySemanticsLabel(RegExp('SE name')));
        final dialogue = extentOf(find.byType(DialogueFitText));
        expect(dialogue, closeTo(extent, 1e-6), reason: 'at $extent');
        expect(
          chip / seNameBoxExtent,
          // A narrowed glyph is quantised down to 1/64 (`wordCondensation`).
          closeTo(narrowed, 1 / 64 + 1e-6),
          reason: 'at $extent: the chip narrows by the ratio the dialogue '
              'narrows by — ↩️it kept its 16 until the block was under 32',
        );
      }
      expect(
        extentOf(find.bySemanticsLabel(RegExp('SE name'))),
        lessThan(seNameBoxExtent),
        reason: '⛔전제: the words narrowed by the last length',
      );
    });
  }

  testWidgets('the chip narrows by the room the block\'s own koma give a '
      'glyph — not the standard\'s (F-496 ③)', (tester) async {
    Future<double> chipAt(SeDialogueSpacing spacing) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              // Thirty frames of four: a glyph is longer than its frame.
              width: 120,
              height: 52,
              child: SeSpanVisual(
                layer: anSeRow(),
                axis: Axis.horizontal,
                frames: 30,
                dialogue: 'せりふ',
                seName: 'SE',
                spacing: spacing,
              ),
            ),
          ),
        ),
      );
      return tester.getSize(find.bySemanticsLabel(RegExp('SE name'))).width;
    }

    expect(
      await chipAt(SeDialogueSpacing.standard),
      seNameBoxExtent,
      reason: '⛔전제: three koma of four hold a glyph',
    );
    expect(
      await chipAt(const SeDialogueSpacing(komaPerGlyph: 1)),
      lessThan(seNameBoxExtent),
      reason: 'one koma of four does not: the glyphs narrow, and the chip',
    );
  });

  testWidgets('normal spans keep the name box', (tester) async {
    await tester.pumpWidget(host(width: 120, height: 52, name: 'ドア'));
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('SE name ドア'), findsOneWidget);
    expect(
      tester.getSize(find.bySemanticsLabel('SE name ドア')).width,
      seNameBoxExtent,
      reason: 'a span with room keeps the chip at its full extent — it is a '
          'ceiling, not a fraction',
    );
  });
}
