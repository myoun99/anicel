import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';

/// R4 improvement 2 — the SE span visual must never throw the striped
/// RenderFlex overflow: long names scale down into the name box, and spans
/// narrower than the box (storyboard zoom-out) drop the box entirely.
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

  testWidgets('spans narrower than the name box drop the box instead of '
      'overflowing (storyboard zoom-out)', (tester) async {
    await tester.pumpWidget(host(width: 10, height: 52, name: 'SE'));
    expect(tester.takeException(), isNull);
    expect(
      find.bySemanticsLabel(RegExp('SE name')),
      findsNothing,
      reason: 'too narrow for the box — dialogue keeps the whole span',
    );
  });

  testWidgets('normal spans keep the name box', (tester) async {
    await tester.pumpWidget(host(width: 120, height: 52, name: 'ドア'));
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('SE name ドア'), findsOneWidget);
  });
}
