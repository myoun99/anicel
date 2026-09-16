import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';

/// R4 improvement 2 — the SE span visual must never throw the striped
/// RenderFlex overflow: long names scale down into the name box, and a span
/// narrower than the box keeps it and narrows it instead (F-93).
void main() {
  Widget host({required double width, required double height, String? name}) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: height,
            child: SeSpanVisual(
              axis: Axis.horizontal,
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
    expect(
      tester.getSize(box).width,
      5,
      reason: 'half the span — the ceiling the old drop threshold named',
    );
  });

  testWidgets('the chip meets its full extent at twice the box, and does not '
      'step there', (tester) async {
    await tester.pumpWidget(host(width: 32, height: 52, name: 'SE'));
    expect(
      tester.getSize(find.bySemanticsLabel(RegExp('SE name'))).width,
      seNameBoxExtent,
      reason: 'half of 32 IS the box — the narrowing is continuous',
    );

    await tester.pumpWidget(host(width: 31, height: 52, name: 'SE'));
    expect(
      tester.getSize(find.bySemanticsLabel(RegExp('SE name'))).width,
      15.5,
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
