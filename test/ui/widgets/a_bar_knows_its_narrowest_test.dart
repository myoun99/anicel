// 🗣️top-strip-narrow-overflow-Q1 (유저 2026-10-01, the answer as corrected):
// 「막대 먼저 줄어들고 다음 목록으로」 — 「이름과 숫자가 막대 안에 들어가는
// 최소 폭까지 줄어든다(최소 폭은 실측해서 정한다)」.
//
// THE BAR MEASURES THAT WIDTH ITSELF, from its own parts: at
// [FieldSlider.narrowestIn] its name and the widest number of its range are
// whole, and a few pixels under it they are not.
//
// ⚠️In the app's faces or not at all ([loadTheAppFaces]) — the widths are the
// faces'.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/words_cut_off.dart';

FieldSlider sizeBar(double value) => FieldSlider(
  label: 'Size',
  value: value,
  min: 1,
  max: 2000,
  scale: FieldSliderScale.exponential,
  unit: ' px',
  height: 42,
  onChanged: (_) {},
);

FieldSlider microBar() => FieldSlider.opacity(value: 1, onChanged: (_) {});

Future<void> pumpBar(WidgetTester tester, FieldSlider bar, double width) =>
    tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: bar),
          ),
        ),
      ),
    );

/// What [bar] says its narrowest is, where the test lays it out.
Future<double> narrowestOf(WidgetTester tester, FieldSlider bar) async {
  await pumpBar(tester, bar, 300);
  return bar.narrowestIn(tester.element(find.byType(FieldSlider)));
}

RenderParagraph paragraphOf(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text));

void main() {
  setUpAll(loadTheAppFaces);

  testWidgets('at its narrowest a labelled bar writes its name and the '
      'widest number of its range whole, and they do not touch', (
    tester,
  ) async {
    final narrowest = await narrowestOf(tester, sizeBar(2000));

    await pumpBar(tester, sizeBar(2000), narrowest);

    expect(find.text('Size'), findsOneWidget, reason: '⛔LIVENESS');
    expect(find.text('2000.0 px'), findsOneWidget, reason: '⛔LIVENESS');
    expect(wordsCutAcross(find.byType(FieldSlider)), isEmpty);
    final name = paragraphOf(tester, 'Size');
    final nameEnd =
        name.localToGlobal(Offset.zero).dx +
        name.getMaxIntrinsicWidth(double.infinity);
    final numberStart = paragraphOf(
      tester,
      '2000.0 px',
    ).localToGlobal(Offset.zero).dx;
    expect(
      numberStart - nameEnd,
      greaterThan(3),
      reason: 'a name run into its number reads as one word',
    );
  });

  testWidgets('a few pixels under it the name is cut — the measure is the '
      'bar\'s, not a round number with room to spare', (tester) async {
    final narrowest = await narrowestOf(tester, sizeBar(2000));

    await pumpBar(tester, sizeBar(2000), narrowest - 6);

    expect(
      wordsCutAcross(find.byType(FieldSlider)),
      contains(contains('Size')),
    );
  });

  testWidgets('it is measured for the number at an END of the range, not '
      'the one the bar holds — so it does not move under a drag', (
    tester,
  ) async {
    final atTheTop = await narrowestOf(tester, sizeBar(2000));
    final atTheBottom = await narrowestOf(tester, sizeBar(1));

    expect(atTheBottom, atTheTop);

    // And the bar holding its SHORTEST number is whole there too.
    await pumpBar(tester, sizeBar(1), atTheBottom);
    expect(wordsCutAcross(find.byType(FieldSlider)), isEmpty);
  });

  testWidgets('the micro bar — no name, no stepper — asks only for its '
      'number', (tester) async {
    final narrowest = await narrowestOf(tester, microBar());
    expect(
      narrowest,
      lessThan(await narrowestOf(tester, sizeBar(2000))),
      reason: '⛔premise: it asks for less than a labelled bar',
    );

    await pumpBar(tester, microBar(), narrowest);
    expect(find.text('100'), findsOneWidget, reason: '⛔LIVENESS');
    expect(wordsCutAcross(find.byType(FieldSlider)), isEmpty);

    await pumpBar(tester, microBar(), narrowest - 2);
    expect(
      wordsCutAcross(find.byType(FieldSlider)),
      contains(contains('100')),
    );
  });
}
