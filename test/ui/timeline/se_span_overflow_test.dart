import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/text/dialogue_fit_paint.dart'
    show dialogueNaturalExtent;
import 'package:anicel/src/ui/timeline/dialogue_fit_text.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';

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
      double extentOf(Finder finder) {
        final size = tester.getSize(finder);
        return axis == Axis.horizontal ? size.width : size.height;
      }

      await tester.pumpWidget(along(400));
      final natural =
          seNameBoxExtent +
          dialogueNaturalExtent(
            'せりふのテキスト',
            axis: axis,
            style: dialogueFitStyle(
              tester.element(find.byType(SeSpanVisual)),
              color: Colors.black,
            ),
            maxCrossExtent: cross,
          );
      expect(natural, lessThan(400), reason: 'fixture: 400 holds both');

      for (final extent in [natural, natural * 0.75, natural / 2, 20.0, 6.0]) {
        await tester.pumpWidget(along(extent));
        final chip = extentOf(find.bySemanticsLabel(RegExp('SE name')));
        final dialogue = extentOf(find.byType(DialogueFitText));
        expect(chip + dialogue, closeTo(extent, 1e-6), reason: 'at $extent');
        expect(
          chip / seNameBoxExtent,
          closeTo(extent / natural, 1e-6),
          reason: 'at $extent: the chip narrows as the block does — ↩️it '
              'kept its 16 until the block was under 32',
        );
        expect(
          dialogue / (natural - seNameBoxExtent),
          closeTo(extent / natural, 1e-6),
          reason: 'at $extent: by the ratio the dialogue narrows by',
        );
      }
    });
  }

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
